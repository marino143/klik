import CWebRTCAEC3
import Foundation

enum EchoCancellerError: Error, LocalizedError {
    case initializationFailed
    case invalidFrameSize
    case processingFailed

    var errorDescription: String? {
        switch self {
        case .initializationFailed: return "WebRTC AEC3 could not be initialized."
        case .invalidFrameSize: return "WebRTC AEC3 returned an invalid frame size."
        case .processingFailed: return "WebRTC AEC3 failed while processing audio."
        }
    }
}

/// Offline WebRTC AEC3 processing. The clean system track is the render
/// reference; the microphone track is capture audio containing voice and room
/// echo. Input tracks must already share the same 48 kHz timeline.
final class EchoCanceller {
    private let sampleRate: Int32

    init(sampleRate: Int32 = 48_000) {
        self.sampleRate = sampleRate
    }

    func process(reference: [Float], mic: [Float]) throws -> [Float] {
        let sampleCount = min(reference.count, mic.count)
        guard sampleCount > 0 else { return [] }
        guard let processor = klik_aec3_create(sampleRate) else {
            throw EchoCancellerError.initializationFailed
        }
        defer { klik_aec3_destroy(processor) }

        let frameSize = Int(klik_aec3_frame_size(processor))
        guard frameSize > 0 else { throw EchoCancellerError.invalidFrameSize }

        var output = [Float](repeating: 0, count: sampleCount)
        var paddedRender = [Float](repeating: 0, count: frameSize)
        var paddedCapture = [Float](repeating: 0, count: frameSize)
        var paddedOutput = [Float](repeating: 0, count: frameSize)

        try reference.withUnsafeBufferPointer { renderPointer in
            try mic.withUnsafeBufferPointer { capturePointer in
                try output.withUnsafeMutableBufferPointer { outputPointer in
                    var offset = 0
                    while offset < sampleCount {
                        let available = min(frameSize, sampleCount - offset)
                        let result: Int32

                        if available == frameSize {
                            result = klik_aec3_process_frame(
                                processor,
                                renderPointer.baseAddress?.advanced(by: offset),
                                capturePointer.baseAddress?.advanced(by: offset),
                                outputPointer.baseAddress?.advanced(by: offset),
                                frameSize
                            )
                        } else {
                            paddedRender = [Float](repeating: 0, count: frameSize)
                            paddedCapture = [Float](repeating: 0, count: frameSize)
                            paddedOutput = [Float](repeating: 0, count: frameSize)
                            for index in 0..<available {
                                paddedRender[index] = renderPointer[offset + index]
                                paddedCapture[index] = capturePointer[offset + index]
                            }
                            result = paddedRender.withUnsafeBufferPointer { renderFrame in
                                paddedCapture.withUnsafeBufferPointer { captureFrame in
                                    paddedOutput.withUnsafeMutableBufferPointer { outputFrame in
                                        klik_aec3_process_frame(
                                            processor,
                                            renderFrame.baseAddress,
                                            captureFrame.baseAddress,
                                            outputFrame.baseAddress,
                                            frameSize
                                        )
                                    }
                                }
                            }
                            for index in 0..<available {
                                outputPointer[offset + index] = paddedOutput[index]
                            }
                        }

                        guard result == 1 else { throw EchoCancellerError.processingFailed }
                        offset += available
                    }
                }
            }
        }

        return output
    }
}
