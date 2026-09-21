import AVFoundation
import AppKit
import CWebRTCAEC3
@testable import Klik
import Foundation
import XCTest

final class CWebRTCAEC3Tests: XCTestCase {
    @MainActor
    func testRecordingBarTogglesManualHeadphonesMode() throws {
        let bar = RecordingControlBar()
        guard let contentView = bar.window?.contentView else {
            XCTFail("Recording bar has no content view")
            return
        }
        let buttons = allSubviews(of: contentView).compactMap { $0 as? NSButton }
        guard let audioModeButton = buttons.first(where: { $0.toolTip?.hasPrefix("Speaker mode") == true }) else {
            XCTFail("Speaker mode button is missing")
            return
        }
        XCTAssertNotNil(buttons.first(where: { $0.toolTip == "Mute microphone" }))

        var selectedMode: RecordingAudioMode?
        bar.onAudioModeChange = { selectedMode = $0 }
        audioModeButton.performClick(nil)

        XCTAssertEqual(selectedMode, .headphones)
        XCTAssertTrue(audioModeButton.toolTip?.hasPrefix("Headphones mode") == true)
        XCTAssertNotNil(audioModeButton.image)
    }

    func testAudioAlignmentPreservesTrackTimestamps() throws {
        let system = [EchoCancellingMixer.AudioChunk(startSeconds: 10, samples: [1, 2, 3])]
        let microphone = [EchoCancellingMixer.AudioChunk(startSeconds: 10.001, samples: [4, 5, 6])]

        let aligned = try EchoCancellingMixer.align(systemChunks: system, micChunks: microphone)

        XCTAssertEqual(aligned.micStartOffset, 48)
        XCTAssertEqual(Array(aligned.system.prefix(3)), [1, 2, 3])
        XCTAssertEqual(aligned.mic[48], 4)
        XCTAssertEqual(aligned.mic[49], 5)
        XCTAssertEqual(aligned.mic[50], 6)
    }

    func testMixerHandlesTimestampOffsetInSpeakerAndHeadphonesModes() async throws {
        let ffmpeg = "/opt/homebrew/bin/ffmpeg"
        guard FileManager.default.isExecutableFile(atPath: ffmpeg) else {
            throw XCTSkip("ffmpeg is not installed")
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("klik-aec3-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("input.mp4")
        let speakerOutput = directory.appendingPathComponent("speaker.mp4")
        let headphonesOutput = directory.appendingPathComponent("headphones.mp4")
        let generator = Process()
        generator.executableURL = URL(fileURLWithPath: ffmpeg)
        generator.arguments = [
            "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "color=c=black:s=320x180:r=30:d=4",
            "-f", "lavfi", "-i", "anoisesrc=color=pink:amplitude=0.2:sample_rate=48000:d=4",
            "-filter_complex",
            "[1:a]asplit=2[system][echo];[echo]adelay=30,volume=0.5,asetpts=PTS+0.037/TB[mic]",
            "-map", "0:v", "-map", "[system]", "-map", "[mic]",
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac",
            input.path,
        ]
        try generator.run()
        generator.waitUntilExit()
        XCTAssertEqual(generator.terminationStatus, 0)

        try await EchoCancellingMixer.process(
            inputURL: input,
            outputURL: speakerOutput,
            echoCancellationEnabled: true
        )
        try await EchoCancellingMixer.process(
            inputURL: input,
            outputURL: headphonesOutput,
            echoCancellationEnabled: false
        )

        for output in [speakerOutput, headphonesOutput] {
            let asset = AVURLAsset(url: output)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            let duration = try await asset.load(.duration).seconds
            XCTAssertEqual(videoTracks.count, 1)
            XCTAssertEqual(audioTracks.count, 1)
            XCTAssertGreaterThan(duration, 3.5)
        }
    }

    func testSwiftEchoCancellerUsesAEC3At48kHz() throws {
        let sampleRate = 48_000
        let frameCount = 400
        let echoDelay = 1_440
        let sampleCount = frameCount * sampleRate / 100
        var state: UInt64 = 0x8765_4321
        var render = [Float](repeating: 0, count: sampleCount)
        var capture = [Float](repeating: 0, count: sampleCount)

        for index in 0..<sampleCount {
            state = state &* 6_364_136_223_846_793_005 &+ 1
            render[index] = Float(Int32(truncatingIfNeeded: state >> 32)) / Float(Int32.max) * 0.25
            if index >= echoDelay {
                capture[index] = render[index - echoDelay] * 0.55
            }
        }

        let output = try EchoCanceller().process(reference: render, mic: capture)
        let measurementStart = sampleRate * 2
        let inputRMS = rms(Array(capture[measurementStart...]))
        let outputRMS = rms(Array(output[measurementStart...]))
        XCTAssertLessThan(outputRMS, inputRMS * 0.5)
    }

    func testAEC3PreservesNearEndVoiceDuringEcho() throws {
        let sampleRate = 48_000
        let sampleCount = sampleRate * 6
        let echoDelay = 1_440
        var state: UInt64 = 0x2468_1357
        var render = [Float](repeating: 0, count: sampleCount)
        var nearEnd = [Float](repeating: 0, count: sampleCount)
        var capture = [Float](repeating: 0, count: sampleCount)

        for index in 0..<sampleCount {
            state = state &* 6_364_136_223_846_793_005 &+ 1
            render[index] = Float(Int32(truncatingIfNeeded: state >> 32)) / Float(Int32.max) * 0.25
            nearEnd[index] = sin(Float(index) * 2 * .pi * 220 / Float(sampleRate)) * 0.08
            capture[index] = nearEnd[index]
            if index >= echoDelay {
                capture[index] += render[index - echoDelay] * 0.55
            }
        }

        let output = try EchoCanceller().process(reference: render, mic: capture)
        let measurementStart = sampleRate * 3
        let inputError = meanSquareError(
            Array(capture[measurementStart...]),
            Array(nearEnd[measurementStart...])
        )
        let outputError = meanSquareError(
            Array(output[measurementStart...]),
            Array(nearEnd[measurementStart...])
        )

        XCTAssertLessThan(outputError, inputError * 0.5)
        XCTAssertGreaterThan(rms(Array(output[measurementStart...])), 0.02)
    }

    func testSuppressesDelayedRenderSignal() throws {
        let sampleRate = 48_000
        let frameSize = sampleRate / 100
        let frameCount = 600
        let echoDelay = frameSize * 3
        guard let processor = klik_aec3_create(Int32(sampleRate)) else {
            XCTFail("Could not create AEC3 processor")
            return
        }
        defer { klik_aec3_destroy(processor) }

        XCTAssertEqual(klik_aec3_frame_size(processor), frameSize)

        var randomState: UInt64 = 0x1234_5678
        var renderHistory = [Float](repeating: 0, count: echoDelay)
        var historyIndex = 0
        var inputEnergy: Double = 0
        var outputEnergy: Double = 0
        var measuredSamples = 0

        for frameIndex in 0..<frameCount {
            var render = [Float](repeating: 0, count: frameSize)
            var capture = [Float](repeating: 0, count: frameSize)
            var output = [Float](repeating: 0, count: frameSize)

            for index in 0..<frameSize {
                randomState = randomState &* 6_364_136_223_846_793_005 &+ 1
                let noise = Float(Int32(truncatingIfNeeded: randomState >> 32)) / Float(Int32.max)
                render[index] = noise * 0.25
                capture[index] = renderHistory[historyIndex] * 0.55
                renderHistory[historyIndex] = render[index]
                historyIndex = (historyIndex + 1) % echoDelay
            }

            let result = render.withUnsafeBufferPointer { renderPointer in
                capture.withUnsafeBufferPointer { capturePointer in
                    output.withUnsafeMutableBufferPointer { outputPointer in
                        klik_aec3_process_frame(
                            processor,
                            renderPointer.baseAddress,
                            capturePointer.baseAddress,
                            outputPointer.baseAddress,
                            frameSize
                        )
                    }
                }
            }
            XCTAssertEqual(result, 1)

            if frameIndex >= 300 {
                for index in 0..<frameSize {
                    inputEnergy += Double(capture[index] * capture[index])
                    outputEnergy += Double(output[index] * output[index])
                    measuredSamples += 1
                }
            }
        }

        let inputRMS = sqrt(inputEnergy / Double(measuredSamples))
        let outputRMS = sqrt(outputEnergy / Double(measuredSamples))
        XCTAssertLessThan(outputRMS, inputRMS * 0.5)
    }

    private func rms(_ samples: [Float]) -> Double {
        sqrt(samples.reduce(0) { $0 + Double($1 * $1) } / Double(samples.count))
    }

    private func meanSquareError(_ lhs: [Float], _ rhs: [Float]) -> Double {
        zip(lhs, rhs).reduce(0) { result, pair in
            let difference = Double(pair.0 - pair.1)
            return result + difference * difference
        } / Double(min(lhs.count, rhs.count))
    }

    @MainActor
    private func allSubviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(allSubviews)
    }
}
