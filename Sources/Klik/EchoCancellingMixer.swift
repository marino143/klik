import Foundation
import AVFoundation
import CoreMedia

enum EchoCancellingMixerError: Error, LocalizedError {
    case noVideoTrack
    case fewerThanTwoAudioTracks
    case readerSetup(String)
    case writerSetup(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:            return "No video track in MP4."
        case .fewerThanTwoAudioTracks: return "Need two audio tracks (system + mic) to echo-cancel."
        case .readerSetup(let m):      return "Reader setup: \(m)"
        case .writerSetup(let m):      return "Writer setup: \(m)"
        case .failed(let m):           return m
        }
    }
}

/// Removes acoustic echo from the mic track using the system-audio track as a
/// reference (NLMS), then mixes the cleaned mic with the system audio into a
/// single track. Video is passed through without re-encoding.
enum EchoCancellingMixer {
    private static let sampleRate: Double = 48000

    static func process(inputURL: URL, outputURL: URL) async throws {
        let asset = AVURLAsset(url: inputURL)

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else { throw EchoCancellingMixerError.noVideoTrack }

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard audioTracks.count >= 2 else { throw EchoCancellingMixerError.fewerThanTwoAudioTracks }

        // Track 0 = system audio (reference), track 1 = microphone — matches the
        // order they're added in VideoRecordingManager.
        var systemSamples = try extractMonoFloat(asset: asset, track: audioTracks[0])
        var micSamples = try extractMonoFloat(asset: asset, track: audioTracks[1])
        NSLog("Klik: AEC extracted system=\(systemSamples.count) mic=\(micSamples.count) samples")

        // Echo-cancel the mic using the system audio as reference.
        let canceller = EchoCanceller(filterLength: 2048, stepSize: 0.2)
        let cleanedMic = canceller.process(reference: systemSamples, mic: micSamples)
        micSamples = []

        // Mix cleaned mic + system audio (clip to [-1, 1]).
        let count = max(systemSamples.count, cleanedMic.count)
        var mixed = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let s = i < systemSamples.count ? systemSamples[i] : 0
            let m = i < cleanedMic.count ? cleanedMic[i] : 0
            var v = s + m
            if v > 1 { v = 1 } else if v < -1 { v = -1 }
            mixed[i] = v
        }
        systemSamples = []

        try await writeOutput(asset: asset, videoTrack: videoTrack, mixedMono: mixed, outputURL: outputURL)
    }

    // MARK: - Audio extraction

    private static func extractMonoFloat(asset: AVAsset, track: AVAssetTrack) throws -> [Float] {
        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) }
        catch { throw EchoCancellingMixerError.readerSetup(error.localizedDescription) }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw EchoCancellingMixerError.readerSetup("audio output") }
        reader.add(output)

        guard reader.startReading() else {
            throw EchoCancellingMixerError.readerSetup(reader.error?.localizedDescription ?? "startReading")
        }

        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            if let block = CMSampleBufferGetDataBuffer(buffer) {
                let length = CMBlockBufferGetDataLength(block)
                let floatCount = length / MemoryLayout<Float>.size
                var chunk = [Float](repeating: 0, count: floatCount)
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &chunk)
                samples.append(contentsOf: chunk)
            }
            CMSampleBufferInvalidate(buffer)
        }
        if reader.status == .failed {
            throw EchoCancellingMixerError.failed(reader.error?.localizedDescription ?? "audio read failed")
        }
        return samples
    }

    // MARK: - Mux (video passthrough + mixed audio)

    private static func writeOutput(asset: AVAsset, videoTrack: AVAssetTrack, mixedMono: [Float], outputURL: URL) async throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let reader: AVAssetReader
        let writer: AVAssetWriter
        do {
            reader = try AVAssetReader(asset: asset)
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            throw EchoCancellingMixerError.writerSetup(error.localizedDescription)
        }

        // Video passthrough
        let videoReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        videoReaderOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoReaderOutput) else { throw EchoCancellingMixerError.readerSetup("video output") }
        reader.add(videoReaderOutput)

        let videoFormat = videoTrack.formatDescriptions.first as! CMFormatDescription
        let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: videoFormat)
        videoWriterInput.expectsMediaDataInRealTime = false
        if let transform = try? await videoTrack.load(.preferredTransform) {
            videoWriterInput.transform = transform
        }
        guard writer.canAdd(videoWriterInput) else { throw EchoCancellingMixerError.writerSetup("video input") }
        writer.add(videoWriterInput)

        // Mixed audio (AAC)
        let aacSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128_000,
        ]
        let audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: aacSettings)
        audioWriterInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(audioWriterInput) else { throw EchoCancellingMixerError.writerSetup("audio input") }
        writer.add(audioWriterInput)

        guard reader.startReading() else {
            throw EchoCancellingMixerError.failed(reader.error?.localizedDescription ?? "startReading")
        }
        guard writer.startWriting() else {
            throw EchoCancellingMixerError.failed(writer.error?.localizedDescription ?? "startWriting")
        }
        writer.startSession(atSourceTime: .zero)

        let videoQueue = DispatchQueue(label: "klik.aec.video")
        let audioQueue = DispatchQueue(label: "klik.aec.audio")

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let group = DispatchGroup()

            group.enter()
            videoWriterInput.requestMediaDataWhenReady(on: videoQueue) {
                while videoWriterInput.isReadyForMoreMediaData {
                    if let buffer = videoReaderOutput.copyNextSampleBuffer() {
                        videoWriterInput.append(buffer)
                    } else {
                        videoWriterInput.markAsFinished()
                        group.leave()
                        return
                    }
                }
            }

            group.enter()
            let chunkFrames = 24000 // 0.5 s at 48 kHz
            var writtenFrames = 0
            audioWriterInput.requestMediaDataWhenReady(on: audioQueue) {
                while audioWriterInput.isReadyForMoreMediaData {
                    if writtenFrames >= mixedMono.count {
                        audioWriterInput.markAsFinished()
                        group.leave()
                        return
                    }
                    let end = min(writtenFrames + chunkFrames, mixedMono.count)
                    let slice = Array(mixedMono[writtenFrames..<end])
                    if let sb = makeAudioSampleBuffer(samples: slice, startSample: writtenFrames) {
                        audioWriterInput.append(sb)
                    }
                    writtenFrames = end
                }
            }

            group.notify(queue: .global()) { continuation.resume() }
        }

        await writer.finishWriting()
        if writer.status != .completed {
            throw EchoCancellingMixerError.failed(writer.error?.localizedDescription ?? "write failed")
        }
    }

    private static func makeAudioSampleBuffer(samples: [Float], startSample: Int) -> CMSampleBuffer? {
        let count = samples.count
        guard count > 0 else { return nil }

        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        var formatDesc: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &formatDesc) == noErr,
              let fd = formatDesc else { return nil }

        let dataBytes = count * MemoryLayout<Float>.size
        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: dataBytes, blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: dataBytes, flags: 0, blockBufferOut: &blockBuffer) == noErr,
              let bb = blockBuffer else { return nil }

        let copyOK = samples.withUnsafeBytes { ptr -> Bool in
            guard let base = ptr.baseAddress else { return false }
            return CMBlockBufferReplaceDataBytes(with: base, blockBuffer: bb, offsetIntoDestination: 0, dataLength: dataBytes) == noErr
        }
        guard copyOK else { return nil }

        let pts = CMTime(value: Int64(startSample), timescale: Int32(sampleRate))
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: Int64(count), timescale: Int32(sampleRate)),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )
        var sampleSize = MemoryLayout<Float>.size

        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: bb, formatDescription: fd, sampleCount: count, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize, sampleBufferOut: &sampleBuffer) == noErr else { return nil }

        return sampleBuffer
    }
}
