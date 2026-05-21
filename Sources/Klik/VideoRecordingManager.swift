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

    private var stream: SCStream?
    private var streamOutput: VideoStreamOutput?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var microphoneInput: AVAssetWriterInput?
    private var micAudioEngine: AVAudioEngine?
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
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        // Voice processing = echo cancellation + noise suppression + AGC.
        // Without this, recordings made without headphones double up on the
        // other person's voice (clean copy from system audio + faint copy
        // captured acoustically from the speakers via the mic). With voice
        // processing on, macOS subtracts the speaker output from the mic
        // input at the system level, so the mic track has only the user's
        // voice.
        do {
            try inputNode.setVoiceProcessingEnabled(true)
            NSLog("Klik: voice processing (AEC + NS + AGC) enabled on microphone")
        } catch {
            NSLog("Klik: voice processing not available — \(error). Recording without echo cancellation.")
        }

        let format = inputNode.outputFormat(forBus: 0)
        NSLog("Klik: mic format sampleRate=\(format.sampleRate) channels=\(format.channelCount)")

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
            guard let self else { return }
            if let sb = self.cmSampleBuffer(from: buffer, at: time) {
                self.handleMicrophoneSampleBuffer(sb)
            }
        }

        do {
            try engine.start()
            self.micAudioEngine = engine
            NSLog("Klik: AVAudioEngine for microphone started")
        } catch {
            NSLog("Klik: failed to start AVAudioEngine — \(error)")
            inputNode.removeTap(onBus: 0)
        }
    }

    private func cmSampleBuffer(from pcmBuffer: AVAudioPCMBuffer, at time: AVAudioTime) -> CMSampleBuffer? {
        let frameLength = Int(pcmBuffer.frameLength)
        guard frameLength > 0 else { return nil }

        var asbd = pcmBuffer.format.streamDescription.pointee
        var formatDescription: CMAudioFormatDescription?
        let fdStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard fdStatus == noErr, let fd = formatDescription else { return nil }

        // PTS in host time clock to stay in the same time base as SCStream's
        // video / system-audio sample buffers.
        let pts: CMTime
        if time.isHostTimeValid {
            pts = CMClockMakeHostTimeFromSystemUnits(time.hostTime)
        } else {
            pts = CMTime(value: time.sampleTime, timescale: Int32(time.sampleRate))
        }

        var sampleBuffer: CMSampleBuffer?
        let createStatus = CMAudioSampleBufferCreateWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: fd,
            sampleCount: CMItemCount(frameLength),
            presentationTimeStamp: pts,
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard createStatus == noErr, let sb = sampleBuffer else { return nil }

        let setStatus = CMSampleBufferSetDataBufferFromAudioBufferList(
            sb,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: pcmBuffer.audioBufferList
        )
        guard setStatus == noErr else { return nil }

        return sb
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
        guard let engine = micAudioEngine else { return }
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning {
            engine.stop()
        }
        micAudioEngine = nil
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
        micAudioEngine = nil
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

