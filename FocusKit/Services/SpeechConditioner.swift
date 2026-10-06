import Foundation

struct SpeechConditioner {
    private let sampleRate: Double
    private var b0 = 0.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
    private var gain = 1.0
    private var noiseFloor = 0.002
    private var envelope = 0.0

    private let target = 0.1
    private let maximumGain = 20.0

    init(sampleRate: Double, cutoff: Double = 90) {
        self.sampleRate = sampleRate
        let omega = 2 * Double.pi * cutoff / sampleRate
        let alpha = sin(omega) / (2 * 0.707)
        let cosine = cos(omega)
        let a0 = 1 + alpha
        b0 = (1 + cosine) / 2 / a0
        b1 = -(1 + cosine) / a0
        b2 = (1 + cosine) / 2 / a0
        a1 = -2 * cosine / a0
        a2 = (1 - alpha) / a0
    }

    mutating func process(_ samples: UnsafeMutablePointer<Float>, count: Int) {
        guard count > 0 else { return }
        var energy = 0.0
        for index in 0..<count {
            let x = Double(samples[index])
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1
            x1 = x
            y2 = y1
            y1 = y
            samples[index] = Float(y)
            energy += y * y
        }

        let rms = sqrt(energy / Double(count))
        let seconds = Double(count) / sampleRate
        noiseFloor = rms < noiseFloor ? noiseFloor + (rms - noiseFloor) * min(1, seconds / 0.5) : noiseFloor + (rms - noiseFloor) * min(1, seconds / 12)
        envelope = rms > envelope ? envelope + (rms - envelope) * min(1, seconds / 0.05) : envelope + (rms - envelope) * min(1, seconds / 0.6)

        if envelope > noiseFloor * 2.2 {
            let desired = min(maximumGain, max(0.5, target / max(envelope, 1e-5)))
            let speed = desired < gain ? seconds / 0.08 : seconds / 1.5
            gain += (desired - gain) * min(1, speed)
        }

        let start = Float(gain)
        for index in 0..<count {
            let boosted = samples[index] * start
            samples[index] = boosted / (1 + abs(boosted) * 0.6)
        }
    }
}
