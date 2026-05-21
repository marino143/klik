import AppKit
import AVFoundation
import ScreenCaptureKit
import CoreMedia

enum RecordingError: Error, LocalizedError {
    case alreadyRecording
    case notRecording
    case writerSetupFailed(String)
    case streamStartFailed(Error)
    case noDisplay

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:           return "Recording is already in progress."
        case .notRecording:               return "No active recording."
        case .writerSetupFailed(let m):   return "Failed to start recording: \(m)"
        case .streamStartFailed(let e):   return "ScreenCaptureKit error: \(e.localizedDescription)"
        case .noDisplay:                  return "No displays available."
        }
    }
}

final class VideoRecordingManager: NSObject, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.marino.klik.recording.queue", qos: .userInitiated)
    private let micCaptureQueue = DispatchQueue(label: "com.marino.klik.mic.queue", qos: .userInitiated)

    private var stream: SCStream?
    private var streamOutput: VideoStreamOutput?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var microphoneInput: AVAssetWriterInput?
    private var micCaptureSession: AVCaptureSession?
    private var micCaptureDelegate: MicrophoneCaptureDelegate?
    private var firstFrameTime: CMTime?
    private(set) var outputURL: URL?
    private(set) var startedAt: Date?

    /// Number of microphone sample buffers appended to the writer during the
    /// most recent recording. Reset on each `startRecording` call.
    private(set) var microphoneSampleCount: Int = 0

    var isRecording: Bool { stream != nil }

    @MainActor
    func startRecording(
        region: CGRect,
        on display: SCDisplay,
        screen: NSScreen,
        excluding windows: [SCWindow] = [],
        excludingApps: [SCRunningApplication] = []
    ) async throws -> URL {
        guard !isRecording else {
            NSLog("Klik: startRecording called while already recording — ignoring")
            throw RecordingError.alreadyRecording
        }

        let scale = screen.backingScaleFactor
        let nativeWidth = max(2, Int(region.width * scale))
        let nativeHeight = max(2, Int(region.height * scale))

        // Cap output at 1080p height. Combined with the HEVC encoder below
        // this aims for HandBrake "Fast 1080p30"-class file sizes out of the
        // box, so the user doesn't have to re-encode meeting recordings.
        let maxOutputHeight = 1080
        let scaleFactor: Double = nativeHeight > maxOutputHeight
            ? Double(maxOutputHeight) / Double(nativeHeight)
            : 1.0
        let pixelWidth = max(2, Int(Double(nativeWidth) * scaleFactor) & ~1)   // even
        let pixelHeight = max(2, Int(Double(nativeHeight) * scaleFactor) & ~1) // even
        NSLog("Klik: startRecording region=\(region) scale=\(scale) native=\(nativeWidth)x\(nativeHeight) output=\(pixelWidth)x\(pixelHeight)")

        let fileURL = Storage.shared.makeTempVideoURL()
        NSLog("Klik: temp output URL = \(fileURL.path)")

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: fileURL, fileType: .mp4)
        } catch {
            NSLog("Klik: AVAssetWriter init failed — \(error)")
            throw RecordingError.writerSetupFailed(error.localizedDescription)
        }

        // HEVC + ~1.5 bits/pixel + 6 Mbps cap. Screen content compresses
        // exceptionally well with HEVC; this matches HandBrake Fast 1080p30
        // size-wise without requiring a second compression pass.
        let computedBitrate = Int(Double(pixelWidth * pixelHeight) * 1.5)
        let bitrate = min(computedBitrate, 6_000_000)
        NSLog("Klik: video bitrate = \(bitrate) bps (~\(bitrate / 1_000_000) Mbps), codec=HEVC")
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: pixelWidth,
            AVVideoHeightKey: pixelHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoExpectedSourceFrameRateKey: 30,
            ] as [String: Any]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            throw RecordingError.writerSetupFailed("AVAssetWriter does not support video input.")
        }
        writer.add(input)

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000,
        ]

        let systemAudio = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        systemAudio.expectsMediaDataInRealTime = true
        if writer.canAdd(systemAudio) {
            writer.add(systemAudio)
        } else {
            NSLog("Klik: writer cannot add system audio input")
        }

        let micAudio = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        micAudio.expectsMediaDataInRealTime = true
        if writer.canAdd(micAudio) {
            writer.add(micAudio)
        } else {
            NSLog("Klik: writer cannot add mic audio input")
        }

        let config = SCStreamConfiguration()
        config.width = pixelWidth
        config.height = pixelHeight
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 3
        config.showsCursor = true
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.displayP3
        config.sourceRect = region
        config.scalesToFit = true
        config.capturesAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        // Note: SCStream's captureMicrophone (macOS 15+) silently drops samples
        // when other audio consumers (e.g. Teams in a browser) hold the device.
        // We use AVCaptureSession for the microphone instead — it coexists
        // properly with other apps.

        let filter: SCContentFilter
        if !excludingApps.isEmpty {
            filter = SCContentFilter(display: display, excludingApplications: excludingApps, exceptingWindows: [])
        } else {
            filter = SCContentFilter(display: display, excludingWindows: windows)
        }
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        let output = VideoStreamOutput(owner: self)
        do {
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: queue)
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: queue)
            NSLog("Klik: addStreamOutput OK (screen + system audio)")
        } catch let e as NSError {
            NSLog("Klik: addStreamOutput FAILED — domain=\(e.domain) code=\(e.code) desc=\(e.localizedDescription)")
            throw RecordingError.streamStartFailed(e)
        }

        guard writer.startWriting() else {
            let werr = writer.error?.localizedDescription ?? "startWriting failed"
            NSLog("Klik: writer.startWriting() returned false — \(werr)")
            throw RecordingError.writerSetupFailed(werr)
        }
        NSLog("Klik: writer.startWriting OK (writer status=\(writer.status.rawValue))")

        self.writer = writer
        self.videoInput = input
        self.systemAudioInput = systemAudio
        self.microphoneInput = micAudio
        self.stream = stream
        self.streamOutput = output
        self.outputURL = fileURL
        self.firstFrameTime = nil
        self.microphoneSampleCount = 0

        do {
            NSLog("Klik: calling stream.startCapture()…")
            try await stream.startCapture()
            self.startedAt = Date()
            NSLog("Klik: stream.startCapture() OK — recording in progress")
        } catch let e as NSError {
            NSLog("Klik: startCapture FAILED — domain=\(e.domain) code=\(e.code) desc=\(e.localizedDescription) info=\(e.userInfo)")
            writer.finishWriting { }
            self.cleanupRecordingState()
            try? FileManager.default.removeItem(at: fileURL)
            throw RecordingError.streamStartFailed(e)
        }

        // Spin up a separate AVCaptureSession for the microphone — it
        // coexists with browser/Teams mic usage, unlike SCStream's built-in
        // microphone capture which silently dropped samples in those cases.
        if MicrophoneAccess.isGranted {
            startMicrophoneCapture()
        } else {
            NSLog("Klik: microphone permission not granted, recording without voice")
        }

        return fileURL
    }

    private func startMicrophoneCapture() {
        guard let micDevice = AVCaptureDevice.default(for: .audio) else {
            NSLog("Klik: no default microphone device found")
            return
        }
        NSLog("Klik: microphone device — name=\(micDevice.localizedName) uid=\(micDevice.uniqueID)")

        let session = AVCaptureSession()

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: micDevice)
        } catch {
            NSLog("Klik: failed to create AVCaptureDeviceInput for mic — \(error)")
            return
        }
        guard session.canAddInput(input) else {
            NSLog("Klik: cannot add mic input to AVCaptureSession")
            return
        }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        let delegate = MicrophoneCaptureDelegate(owner: self)
        output.setSampleBufferDelegate(delegate, queue: micCaptureQueue)
        guard session.canAddOutput(output) else {
            NSLog("Klik: cannot add audio output to AVCaptureSession")
            return
        }
        session.addOutput(output)

        self.micCaptureSession = session
        self.micCaptureDelegate = delegate

        // startRunning blocks; do it off the main actor
        micCaptureQueue.async {
            session.startRunning()
            NSLog("Klik: AVCaptureSession for microphone is running")
        }
    }

    @MainActor
    func stopRecording() async throws -> URL {
        guard let stream = stream, let writer = writer, let input = videoInput, let url = outputURL else {
            throw RecordingError.notRecording
        }

        stopMicrophoneCapture()
        try await stream.stopCapture()
        input.markAsFinished()
        systemAudioInput?.markAsFinished()
        microphoneInput?.markAsFinished()
        await writer.finishWriting()
        cleanupRecordingState()
        return url
    }

    @MainActor
    func cancelRecording() async {
        guard let stream = stream, let writer = writer, let url = outputURL else { return }
        stopMicrophoneCapture()
        try? await stream.stopCapture()
        videoInput?.markAsFinished()
        systemAudioInput?.markAsFinished()
        microphoneInput?.markAsFinished()
        await writer.finishWriting()
        try? FileManager.default.removeItem(at: url)
        cleanupRecordingState()
    }

    private func stopMicrophoneCapture() {
        guard let session = micCaptureSession else { return }
        if session.isRunning {
            session.stopRunning()
        }
        micCaptureSession = nil
        micCaptureDelegate = nil
    }

    fileprivate func handleSampleBuffer(_ sampleBuffer: CMSampleBuffer, type: SCStreamOutputType) {
        guard sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer) else { return }

        switch type {
        case .screen:
            handleVideoSampleBuffer(sampleBuffer)
        case .audio:
            handleAudioSampleBuffer(sampleBuffer, input: systemAudioInput, isMicrophone: false)
        default:
            break
        }
    }

    fileprivate func handleMicrophoneSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        handleAudioSampleBuffer(sampleBuffer, input: microphoneInput, isMicrophone: true)
    }

    private func handleVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let info = attachments.first,
              let statusRaw = info[.status] as? Int,
              SCFrameStatus(rawValue: statusRaw) == .complete else { return }

        guard let writer = writer, let input = videoInput else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if firstFrameTime == nil {
            writer.startSession(atSourceTime: pts)
            firstFrameTime = pts
        }

        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }

    private func handleAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer, input: AVAssetWriterInput?, isMicrophone: Bool) {
        guard let input = input, firstFrameTime != nil else { return }
        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
            if isMicrophone {
                microphoneSampleCount += 1
            }
        }
    }

    private func cleanupRecordingState() {
        stream = nil
        streamOutput = nil
        writer = nil
        videoInput = nil
        systemAudioInput = nil
        microphoneInput = nil
        micCaptureSession = nil
        micCaptureDelegate = nil
        firstFrameTime = nil
        startedAt = nil
    }
}

extension VideoRecordingManager: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("Klik: SCStream stopped with error \(error)")
    }
}

private final class VideoStreamOutput: NSObject, SCStreamOutput {
    weak var owner: VideoRecordingManager?

    init(owner: VideoRecordingManager) {
        self.owner = owner
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        owner?.handleSampleBuffer(sampleBuffer, type: outputType)
    }
}

final class MicrophoneCaptureDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    weak var owner: VideoRecordingManager?

    init(owner: VideoRecordingManager) {
        self.owner = owner
        super.init()
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        owner?.handleMicrophoneSampleBuffer(sampleBuffer)
    }
}
