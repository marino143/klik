import AppKit
@preconcurrency import AVFoundation
@preconcurrency import ScreenCaptureKit
@preconcurrency import CoreMedia

enum RecordingError: Error, LocalizedError {
    case alreadyRecording
    case notRecording
    case writerSetupFailed(String)
    case streamStartFailed(Error)
    case recordingInterrupted(Error)
    case noDisplay

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:           return "Recording is already in progress."
        case .notRecording:               return "No active recording."
        case .writerSetupFailed(let m):   return "Failed to start recording: \(m)"
        case .streamStartFailed(let e):   return "ScreenCaptureKit error: \(e.localizedDescription)"
        case .recordingInterrupted(let e):return "Recording stopped unexpectedly: \(e.localizedDescription)"
        case .noDisplay:                  return "No displays available."
        }
    }
}

enum RecordingAudioMode: Equatable, Sendable {
    case speakers
    case headphones
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
    private let microphoneStateLock = NSLock()
    private var microphoneEnabledValue = true
    private var audioModeValue: RecordingAudioMode = .speakers
    private var firstFrameTime: CMTime?
    private(set) var outputURL: URL?
    private(set) var startedAt: Date?
    var onUnexpectedStop: (@MainActor (Error) -> Void)?
    var onAutomaticStop: (@MainActor () -> Void)?
    @MainActor private(set) var stopDiagnostics = RecordingStopDiagnostics()
    @MainActor private let stopTimer = RecordingStopTimer()
    @MainActor var automaticStopRemaining: TimeInterval? { stopTimer.remaining }
    @MainActor private var isFinishing = false
    @MainActor private var isStarting = false

    /// Number of microphone sample buffers appended to the writer during the
    /// most recent recording. Reset on each `startRecording` call.
    private var microphoneSampleCountValue: Int = 0

    var microphoneSampleCount: Int {
        queue.sync { microphoneSampleCountValue }
    }

    var isRecording: Bool { stream != nil }

    var isMicrophoneEnabled: Bool {
        microphoneStateLock.withLock { microphoneEnabledValue }
    }

    var audioMode: RecordingAudioMode {
        microphoneStateLock.withLock { audioModeValue }
    }

    func setMicrophoneEnabled(_ enabled: Bool) {
        microphoneStateLock.withLock {
            microphoneEnabledValue = enabled
        }
        KlikLog("Klik: microphone \(enabled ? "enabled" : "muted") by user")
    }

    func setAudioMode(_ mode: RecordingAudioMode) {
        microphoneStateLock.withLock {
            audioModeValue = mode
        }
        KlikLog("Klik: audio mode set to \(mode == .headphones ? "headphones" : "speakers")")
    }

    @MainActor
    func startRecording(
        region: CGRect,
        on display: SCDisplay,
        screen: NSScreen,
        excluding windows: [SCWindow] = []
    ) async throws -> URL {
        guard !isRecording, !isStarting, !isFinishing else {
            KlikLog("Klik: startRecording called while already recording — ignoring")
            throw RecordingError.alreadyRecording
        }

        stopDiagnostics = RecordingStopDiagnostics()
        stopDiagnostics.event(.sessionStarted)
        isStarting = true
        defer { isStarting = false }
        // A menu-bar app may have no onscreen windows yet. Excluding the process
        // also covers the control bar created AFTER this snapshot and filter.
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let excludedApps = try RecordingCaptureExclusion.ownApplications(
            in: content.applications, processID: ProcessInfo.processInfo.processIdentifier,
            applicationProcessID: { $0.processID })
        stopTimer.cancel()
        let stopDuration = RecordingStopSettings().duration
        let scale = screen.backingScaleFactor
        let nativeWidth = max(2, Int(region.width * scale))
        let nativeHeight = max(2, Int(region.height * scale))

        // Snapshot preferences once; changes apply to the next recording.
        let preferences = RecordingSettings()
        let dimensions = preferences.dimensions(width: nativeWidth, height: nativeHeight)
        let pixelWidth = dimensions.width
        let pixelHeight = dimensions.height
        KlikLog("Klik: startRecording region=\(region) scale=\(scale) native=\(nativeWidth)x\(nativeHeight) output=\(pixelWidth)x\(pixelHeight)")

        let fileURL = Storage.shared.makeTempVideoURL()
        KlikLog("Klik: temp output URL = \(fileURL.path)")

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: fileURL, fileType: .mp4)
        } catch {
            KlikLog("Klik: AVAssetWriter init failed — \(error)")
            throw RecordingError.writerSetupFailed(error.localizedDescription)
        }
        // Emit a self-contained movie fragment every second. A normal MP4 only
        // writes its index when finishWriting() runs, so a hard crash loses the
        // whole recording. Fragmented MP4 remains readable through the most
        // recent completed fragment.
        writer.movieFragmentInterval = CMTime(seconds: 1, preferredTimescale: 600)
        writer.shouldOptimizeForNetworkUse = true

        let bitrate = preferences.bitrate(width: pixelWidth, height: pixelHeight)
        KlikLog("Klik: video bitrate = \(bitrate) bps (~\(bitrate / 1_000_000) Mbps), codec=HEVC")
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: pixelWidth,
            AVVideoHeightKey: pixelHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoMaxKeyFrameIntervalKey: preferences.fps * 2,
                AVVideoExpectedSourceFrameRateKey: preferences.fps,
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
            KlikLog("Klik: writer cannot add system audio input")
        }

        let micAudio = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        micAudio.expectsMediaDataInRealTime = true
        if writer.canAdd(micAudio) {
            writer.add(micAudio)
        } else {
            KlikLog("Klik: writer cannot add mic audio input")
        }

        let config = SCStreamConfiguration()
        config.width = pixelWidth
        config.height = pixelHeight
        config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(preferences.fps))
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

        let filter = SCContentFilter(
            display: display, excludingApplications: excludedApps,
            exceptingWindows: RecordingCaptureExclusion.otherWindows(
                in: windows, processID: ProcessInfo.processInfo.processIdentifier,
                ownerProcessID: { $0.owningApplication?.processID }))
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        let output = VideoStreamOutput(owner: self)
        do {
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: queue)
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: queue)
            KlikLog("Klik: addStreamOutput OK (screen + system audio)")
        } catch let e as NSError {
            KlikLog("Klik: addStreamOutput FAILED — domain=\(e.domain) code=\(e.code) desc=\(e.localizedDescription)")
            throw RecordingError.streamStartFailed(e)
        }

        guard writer.startWriting() else {
            let werr = writer.error?.localizedDescription ?? "startWriting failed"
            KlikLog("Klik: writer.startWriting() returned false — \(werr)")
            throw RecordingError.writerSetupFailed(werr)
        }
        KlikLog("Klik: writer.startWriting OK (writer status=\(writer.status.rawValue))")

        queue.sync {
            self.writer = writer
            self.videoInput = input
            self.systemAudioInput = systemAudio
            self.microphoneInput = micAudio
            self.firstFrameTime = nil
            self.microphoneSampleCountValue = 0
        }
        setMicrophoneEnabled(true)
        setAudioMode(.speakers)
        self.stream = stream
        self.streamOutput = output
        self.outputURL = fileURL

        do {
            KlikLog("Klik: calling stream.startCapture()…")
            try await stream.startCapture()
            self.startedAt = Date()
            stopTimer.start(duration: stopDuration) { [weak self] in
                guard let self else { return }
                self.stopDiagnostics.event(.deadline, source: .automatic, flag: self.onAutomaticStop != nil)
                guard self.isRecording, !self.isFinishing else { return }
                KlikLog("Klik: automatic stop deadline reached")
                self.onAutomaticStop?()
            }
            KlikLog("Klik: stream.startCapture() OK — recording in progress")
        } catch let e as NSError {
            KlikLog("Klik: startCapture FAILED — domain=\(e.domain) code=\(e.code) desc=\(e.localizedDescription) info=\(e.userInfo)")
            writer.finishWriting { }
            self.cleanupRecordingState()
            Storage.shared.discardRecording(at: fileURL)
            throw RecordingError.streamStartFailed(e)
        }

        // Spin up a separate AVCaptureSession for the microphone — it
        // coexists with browser/Teams mic usage, unlike SCStream's built-in
        // microphone capture which silently dropped samples in those cases.
        if MicrophoneAccess.isGranted {
            startMicrophoneCapture()
        } else {
            KlikLog("Klik: microphone permission not granted, recording without voice")
        }

        return fileURL
    }

    private func startMicrophoneCapture() {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        // NOTE: we deliberately do NOT enable voice processing
        // (setVoiceProcessingEnabled). It performs echo cancellation, but it
        // also switches the whole shared audio I/O into "voice chat" mode,
        // which compresses/degrades the system-audio output path that
        // SCStream captures — making the other meeting participant sound
        // tinny/compressed. Plain capture keeps both tracks clean; WebRTC AEC3
        // removes speaker echo later without changing the live output path.

        let format = inputNode.outputFormat(forBus: 0)
        KlikLog("Klik: mic format sampleRate=\(format.sampleRate) channels=\(format.channelCount)")

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
            guard let self else { return }
            if !self.isMicrophoneEnabled {
                let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
                for audioBuffer in buffers {
                    guard let data = audioBuffer.mData else { continue }
                    memset(data, 0, Int(audioBuffer.mDataByteSize))
                }
            }
            if let sb = self.cmSampleBuffer(from: buffer, at: time) {
                let sample = SendableSampleBuffer(sb)
                self.queue.async {
                    self.handleMicrophoneSampleBuffer(sample.value)
                }
            }
        }

        do {
            try engine.start()
            self.micAudioEngine = engine
            KlikLog("Klik: AVAudioEngine for microphone started (clean, no voice processing)")
        } catch {
            KlikLog("Klik: failed to start AVAudioEngine — \(error)")
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
        let trace = stopDiagnostics
        trace.event(.recorderRequest)
        guard !isStarting, !isFinishing, let stream = stream, let writer = writer, let input = videoInput, let url = outputURL else {
            trace.event(.recorderRejected)
            throw RecordingError.notRecording
        }

        isFinishing = true
        stopTimer.cancel()
        trace.event(.recorderAccepted)
        let stopBegan = ProcessInfo.processInfo.systemUptime
        KlikLog("Klik: stop accepted; automatic timer cancelled; stopping microphone")
        defer { isFinishing = false }
        trace.event(.microphoneBegin)
        stopMicrophoneCapture()
        trace.event(.microphoneEnd)
        KlikLog("Klik: microphone stopped; requesting screen capture stop")
        var stopError: Error?
        trace.event(.captureBegin)
        do { try await stream.stopCapture() } catch { stopError = error }
        trace.event(.captureEnd, flag: stopError != nil)
        KlikLog("Klik: screen capture stop returned after \(ProcessInfo.processInfo.systemUptime - stopBegan)s error=\(stopError != nil)")
        trace.event(.writerQueueBegin)
        queue.sync {
            input.markAsFinished()
            systemAudioInput?.markAsFinished()
            microphoneInput?.markAsFinished()
        }
        trace.event(.writerQueueEnd)
        KlikLog("Klik: finishing MP4 writer")
        trace.event(.writerBegin)
        await writer.finishWriting()
        trace.event(.writerEnd, flag: writer.status == .completed)
        KlikLog("Klik: MP4 writer finished after \(ProcessInfo.processInfo.systemUptime - stopBegan)s status=\(writer.status.rawValue)")
        cleanupRecordingState()
        if let stopError { trace.event(.stopFailed); throw stopError }
        if let error = writer.error { trace.event(.stopFailed); throw error }
        trace.event(.stopCompleted)
        return url
    }

    @MainActor
    func cancelRecording() async {
        guard !isFinishing else { return }
        stopTimer.cancel()
        guard let stream = stream, let writer = writer, let url = outputURL else { return }
        isFinishing = true
        defer { isFinishing = false }
        stopMicrophoneCapture()
        try? await stream.stopCapture()
        queue.sync {
            videoInput?.markAsFinished()
            systemAudioInput?.markAsFinished()
            microphoneInput?.markAsFinished()
        }
        await writer.finishWriting()
        Storage.shared.discardRecording(at: url)
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
                microphoneSampleCountValue += 1
            }
        }
    }

    @MainActor
    private func cleanupRecordingState() {
        stopTimer.cancel()
        stream = nil
        streamOutput = nil
        queue.sync {
            writer = nil
            videoInput = nil
            systemAudioInput = nil
            microphoneInput = nil
            firstFrameTime = nil
        }
        micAudioEngine = nil
        setMicrophoneEnabled(true)
        startedAt = nil
    }

    @MainActor
    private func handleUnexpectedStop(_ error: Error, from stoppedStream: SCStream) async {
        guard stream === stoppedStream, !isFinishing else { return }
        isFinishing = true
        stopTimer.cancel()
        defer { isFinishing = false }

        stopMicrophoneCapture()
        let activeWriter = queue.sync { () -> AVAssetWriter? in
            videoInput?.markAsFinished()
            systemAudioInput?.markAsFinished()
            microphoneInput?.markAsFinished()
            return writer
        }
        if let activeWriter {
            await activeWriter.finishWriting()
        }
        // Keep the finalized file and its recovery marker so the next launch
        // can offer it instead of deleting a usable partial recording.
        cleanupRecordingState()
        onUnexpectedStop?(RecordingError.recordingInterrupted(error))
    }
}

private final class SendableSampleBuffer: @unchecked Sendable {
    let value: CMSampleBuffer

    init(_ value: CMSampleBuffer) {
        self.value = value
    }
}

extension VideoRecordingManager: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        KlikLog("Klik: SCStream stopped with error \(error)")
        Task { @MainActor [weak self] in
            await self?.handleUnexpectedStop(error, from: stream)
        }
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
