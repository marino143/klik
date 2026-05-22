import Foundation
import Accelerate

/// Time-domain NLMS (normalized least-mean-squares) adaptive echo canceller.
///
/// Given a `reference` signal (the clean system audio that was playing through
/// the speakers) and a `mic` signal (the user's voice plus the acoustic echo
/// of those speakers picked up by the microphone), it adaptively estimates the
/// echo path and subtracts the echo from the mic, leaving mostly the user's
/// voice.
///
/// This runs entirely in post-processing on the two already-recorded audio
/// tracks, so unlike macOS voice processing (VPIO) it never touches the live
/// audio I/O and never degrades the system-audio recording.
final class EchoCanceller {
    private let filterLength: Int
    private let mu: Float            // NLMS step size (0..1)
    private let eps: Float = 1e-6    // regularization
    private let leak: Float          // weight leakage (slightly < 1 for stability)

    // Double-talk detector (Geigel): when the mic level approaches the recent
    // reference level, the user is likely speaking, so we freeze adaptation
    // (but keep subtracting the current estimate) to avoid cancelling speech.
    private let dtThreshold: Float
    private let dtHangoverSamples: Int

    init(filterLength: Int = 2048,
         stepSize: Float = 0.2,
         doubleTalkThreshold: Float = 0.5,
         doubleTalkHangoverSamples: Int = 4800) {
        self.filterLength = filterLength
        self.mu = stepSize
        self.leak = 0.99999
        self.dtThreshold = doubleTalkThreshold
        self.dtHangoverSamples = doubleTalkHangoverSamples
    }

    /// Process whole mono signals. `reference` and `mic` must be time-aligned
    /// at the same sample rate. Returns the cleaned mic (echo removed).
    func process(reference: [Float], mic: [Float]) -> [Float] {
        let n = min(reference.count, mic.count)
        guard n > 0 else { return mic }
        let L = filterLength

        var output = [Float](repeating: 0, count: n)
        var weights = [Float](repeating: 0, count: L)

        // Front-pad the reference with L-1 zeros so a length-L window ending at
        // sample i is paddedRef[i ..< i+L].
        var paddedRef = [Float](repeating: 0, count: L - 1 + n)
        for i in 0..<n { paddedRef[L - 1 + i] = reference[i] }

        var hangover = 0

        weights.withUnsafeMutableBufferPointer { w in
            paddedRef.withUnsafeBufferPointer { rp in
                let wBase = w.baseAddress!
                let rBase = rp.baseAddress!
                for i in 0..<n {
                    let xPtr = rBase + i // window paddedRef[i ..< i+L]

                    // Echo estimate y = w · x
                    var y: Float = 0
                    vDSP_dotpr(wBase, 1, xPtr, 1, &y, vDSP_Length(L))

                    let d = mic[i]
                    let e = d - y
                    output[i] = e

                    // Geigel double-talk detection
                    var maxRef: Float = 0
                    vDSP_maxmgv(xPtr, 1, &maxRef, vDSP_Length(L))
                    if maxRef > 1e-5 && abs(d) > dtThreshold * maxRef {
                        hangover = dtHangoverSamples
                    } else if hangover > 0 {
                        hangover -= 1
                    }

                    // NLMS update (skip while in double-talk)
                    if hangover == 0 {
                        var energy: Float = 0
                        vDSP_svesq(xPtr, 1, &energy, vDSP_Length(L))
                        var scale = mu * e / (energy + eps)
                        // optional leakage for numerical stability
                        if leak != 1.0 {
                            var lk = leak
                            vDSP_vsmul(wBase, 1, &lk, wBase, 1, vDSP_Length(L))
                        }
                        vDSP_vsma(xPtr, 1, &scale, wBase, 1, wBase, 1, vDSP_Length(L))
                    }
                }
            }
        }

        return output
    }
}
