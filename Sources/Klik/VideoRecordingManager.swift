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
    private var firstFrameTime: CMTime?
    private(set) var outputURL: URL?
    private(set) var startedAt: Date?

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
        let pixelWidth = max(2, Int(region.width * scale))
        let pixelHeight = max(2, Int(region.height * scale))
        NSLog("Klik: startRecording region=\(region) scale=\(scale) px=\(pixelWidth)x\(pixelHeight)")

        let fileURL = Storage.shared.makeTempVideoURL()
        NSLog("Klik: temp output URL = \(fileURL.path)")

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: fileURL, fileType: .mp4)
        } catch {
            NSLog("Klik: AVAssetWriter init failed — \(error)")
            throw RecordingError.writerSetupFailed(error.localizedDescription)
        }

        let computedBitrate = Int(Double(pixelWidth * pixelHeight) * 2.5)
        let bitrate = min(computedBitrate, 20_000_000)
        NSLog("Klik: video bitrate = \(bitrate) bps (~\(bitrate / 1_000_000) Mbps)")
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: pixelWidth,
            AVVideoHeightKey: pixelHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
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
        config.queueDepth = 6
        config.showsCursor = true
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.displayP3
        config.sourceRect = region
        config.scalesToFit = false
        config.capturesAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        if #available(macOS 15.0, *) {
            config.captureMicrophone = true
        }

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
            if #available(macOS 15.0, *) {
                try stream.addStreamOutput(output, type: .microphone, sampleHandlerQueue: queue)
            }
            NSLog("Klik: addStreamOutput OK (screen + audio + mic)")
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

        do {
            NSLog("Klik: calling stream.startCapture()…")
            try await stream.startCapture()
            self.startedAt = Date()
            NSLog("Klik: stream.startCapture() OK — recording in progress")
            return fileURL
        } catch let e as NSError {
            NSLog("Klik: startCapture FAILED — domain=\(e.domain) code=\(e.code) desc=\(e.localizedDescription) info=\(e.userInfo)")
            writer.finishWriting { }
            self.cleanupRecordingState()
            try? FileManager.default.removeItem(at: fileURL)
            throw RecordingError.streamStartFailed(e)
        }
    }

    @MainActor
    func stopRecording() async throws -> URL {
        guard let stream = stream, let writer = writer, let input = videoInput, let url = outputURL else {
            throw RecordingError.notRecording
        }

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
        try? await stream.stopCapture()
        videoInput?.markAsFinished()
        systemAudioInput?.markAsFinished()
        microphoneInput?.markAsFinished()
        await writer.finishWriting()
        try? FileManager.default.removeItem(at: url)
        cleanupRecordingState()
    }

    fileprivate func handleSampleBuffer(_ sampleBuffer: CMSampleBuffer, type: SCStreamOutputType) {
        guard sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer) else { return }

        switch type {
        case .screen:
            handleVideoSampleBuffer(sampleBuffer)
        case .audio:
            handleAudioSampleBuffer(sampleBuffer, input: systemAudioInput)
        default:
            if #available(macOS 15.0, *), type == .microphone {
                handleAudioSampleBuffer(sampleBuffer, input: microphoneInput)
            }
        }
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

    private func handleAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer, input: AVAssetWriterInput?) {
        guard let input = input, firstFrameTime != nil else { return }
        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }

    private func cleanupRecordingState() {
        stream = nil
        streamOutput = nil
        writer = nil
        videoInput = nil
        systemAudioInput = nil
        microphoneInput = nil
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
