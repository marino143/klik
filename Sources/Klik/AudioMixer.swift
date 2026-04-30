import Foundation
import AVFoundation
import CoreMedia

enum AudioMixerError: Error, LocalizedError {
    case readerSetup(String)
    case writerSetup(String)
    case noVideoTrack
    case noAudioTracks
    case onlyOneAudioTrack
    case readerFailed(Error?)
    case writerFailed(Error?)

    var errorDescription: String? {
        switch self {
        case .readerSetup(let m):    return "Reader setup: \(m)"
        case .writerSetup(let m):    return "Writer setup: \(m)"
        case .noVideoTrack:          return "No video track in MP4."
        case .noAudioTracks:         return "No audio tracks in MP4."
        case .onlyOneAudioTrack:     return "Only one audio track — nothing to mix."
        case .readerFailed(let e):   return "Reader: \(e?.localizedDescription ?? "?")"
        case .writerFailed(let e):   return "Writer: \(e?.localizedDescription ?? "?")"
        }
    }
}

enum AudioMixer {

    static func mixAudioTracks(inputURL: URL, outputURL: URL) async throws {
        let asset = AVURLAsset(url: inputURL)

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else { throw AudioMixerError.noVideoTrack }

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else { throw AudioMixerError.noAudioTracks }
        if audioTracks.count == 1 { throw AudioMixerError.onlyOneAudioTrack }

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw AudioMixerError.readerSetup(error.localizedDescription)
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            throw AudioMixerError.writerSetup(error.localizedDescription)
        }

        // VIDEO: read raw, write passthrough (no decode)
        let videoReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        videoReaderOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoReaderOutput) else { throw AudioMixerError.readerSetup("video output") }
        reader.add(videoReaderOutput)

        let videoSourceFormat = (videoTrack.formatDescriptions.first as! CMFormatDescription)
        let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: videoSourceFormat)
        videoWriterInput.expectsMediaDataInRealTime = false
        if let transform = try? await videoTrack.load(.preferredTransform) {
            videoWriterInput.transform = transform
        }
        guard writer.canAdd(videoWriterInput) else { throw AudioMixerError.writerSetup("video input") }
        writer.add(videoWriterInput)

        // AUDIO: decode all tracks to PCM Float32, then mix and re-encode to AAC
        let pcmSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
        ]
        var audioReaderOutputs: [AVAssetReaderTrackOutput] = []
        for track in audioTracks {
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: pcmSettings)
            output.alwaysCopiesSampleData = true
            if reader.canAdd(output) {
                reader.add(output)
                audioReaderOutputs.append(output)
            }
        }
        guard audioReaderOutputs.count >= 2 else { throw AudioMixerError.readerSetup("audio outputs") }

        let aacSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192_000,
        ]
        let audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: aacSettings)
        audioWriterInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(audioWriterInput) else { throw AudioMixerError.writerSetup("audio input") }
        writer.add(audioWriterInput)

        guard reader.startReading() else { throw AudioMixerError.readerFailed(reader.error) }
        guard writer.startWriting() else { throw AudioMixerError.writerFailed(writer.error) }
        writer.startSession(atSourceTime: .zero)

        let videoQueue = DispatchQueue(label: "klik.audiomixer.video")
        let audioQueue = DispatchQueue(label: "klik.audiomixer.audio")

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
            let outputs = audioReaderOutputs
            audioWriterInput.requestMediaDataWhenReady(on: audioQueue) {
                while audioWriterInput.isReadyForMoreMediaData {
                    if let mixed = readAndMix(outputs: outputs) {
                        audioWriterInput.append(mixed)
                    } else {
                        audioWriterInput.markAsFinished()
                        group.leave()
                        return
                    }
                }
            }
            group.notify(queue: .global()) {
                continuation.resume()
            }
        }

        await writer.finishWriting()
        if writer.status != .completed {
            throw AudioMixerError.writerFailed(writer.error)
        }
        if reader.status == .failed {
            throw AudioMixerError.readerFailed(reader.error)
        }
    }

    private static func readAndMix(outputs: [AVAssetReaderTrackOutput]) -> CMSampleBuffer? {
        var buffers: [CMSampleBuffer] = []
        for output in outputs {
            if let buf = output.copyNextSampleBuffer() {
                buffers.append(buf)
            }
        }
        if buffers.isEmpty { return nil }
        if buffers.count == 1 { return buffers[0] }
        return mixPCMBuffers(buffers)
    }

    private static func mixPCMBuffers(_ buffers: [CMSampleBuffer]) -> CMSampleBuffer? {
        guard let firstBuffer = buffers.first else { return nil }

        var minFrameCount = Int.max
        for buf in buffers {
            minFrameCount = min(minFrameCount, CMSampleBufferGetNumSamples(buf))
        }
        guard minFrameCount > 0,
              let formatDesc = CMSampleBufferGetFormatDescription(firstBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return firstBuffer
        }
        let asbd = asbdPtr.pointee
        let channelCount = Int(asbd.mChannelsPerFrame)
        let bytesPerFrame = Int(asbd.mBytesPerFrame)
        let totalFloats = minFrameCount * channelCount
        let totalBytes = minFrameCount * bytesPerFrame

        let outputBufferPtr = UnsafeMutableRawPointer.allocate(byteCount: totalBytes, alignment: MemoryLayout<Float>.alignment)
        let outFloats = outputBufferPtr.bindMemory(to: Float.self, capacity: totalFloats)
        for i in 0..<totalFloats {
            outFloats[i] = 0
        }

        let gain: Float = 1.0 / max(1.0, Float(buffers.count) * 0.65)

        for buf in buffers {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(buf) else { continue }
            var dataPointer: UnsafeMutablePointer<Int8>?
            var lengthAtOffset = 0
            var totalLength = 0
            let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0,
                                                    lengthAtOffsetOut: &lengthAtOffset,
                                                    totalLengthOut: &totalLength,
                                                    dataPointerOut: &dataPointer)
            guard status == noErr, let dataPtr = dataPointer else { continue }
            let floats = UnsafeRawPointer(dataPtr).assumingMemoryBound(to: Float.self)
            let availableFloats = totalLength / MemoryLayout<Float>.size
            let copyCount = min(totalFloats, availableFloats)
            for i in 0..<copyCount {
                outFloats[i] += floats[i]
            }
        }
        for i in 0..<totalFloats {
            var v = outFloats[i] * gain
            if v > 1.0 { v = 1.0 } else if v < -1.0 { v = -1.0 }
            outFloats[i] = v
        }

        var blockBuffer: CMBlockBuffer?
        let bbStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: outputBufferPtr,
            blockLength: totalBytes,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: totalBytes,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard bbStatus == noErr, let bb = blockBuffer else {
            outputBufferPtr.deallocate()
            return nil
        }

        var asbdMutable = asbd
        var formatDescOut: CMAudioFormatDescription?
        let fdStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbdMutable,
            layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescOut
        )
        guard fdStatus == noErr, let outFormatDesc = formatDescOut else { return nil }

        let pts = CMSampleBufferGetPresentationTimeStamp(firstBuffer)
        let duration = CMTime(value: Int64(minFrameCount), timescale: Int32(asbd.mSampleRate))
        var timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: pts, decodeTimeStamp: .invalid)
        var sampleSize = bytesPerFrame

        var outSampleBuffer: CMSampleBuffer?
        let sbStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: bb,
            formatDescription: outFormatDesc,
            sampleCount: minFrameCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &outSampleBuffer
        )
        guard sbStatus == noErr else { return nil }
        return outSampleBuffer
    }
}
