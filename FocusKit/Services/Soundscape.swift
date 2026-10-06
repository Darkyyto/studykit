import AVFoundation
import Observation

@MainActor
@Observable
final class Soundscape {
    enum Kind: Int, Sendable {
        case cabin, ocean, space, rain, breeze

        init(mode: FocusMode) {
            switch mode {
            case .flight: self = .cabin
            case .tide: self = .ocean
            case .orbit: self = .space
            case .bloom: self = .rain
            }
        }

        var title: String {
            switch self {
            case .cabin: "Cabin"
            case .ocean: "Waves"
            case .space: "Deep space"
            case .rain: "Soft rain"
            case .breeze: "Breeze"
            }
        }
    }

    private(set) var current: Kind?

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private let synth = Synth()
    @ObservationIgnored private var fade: Task<Void, Never>?

    var isEnabled = UserDefaults.standard.bool(forKey: Preference.soundscape) {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Preference.soundscape) }
    }

    var volume: Float {
        let stored = UserDefaults.standard.object(forKey: Preference.soundscapeVolume) as? Float
        return stored ?? 0.55
    }

    func sync(kind: Kind?) {
        let target = isEnabled ? kind : nil
        guard target != current else { return }
        if let target {
            play(target)
        } else {
            stop()
        }
    }

    func applyVolume() {
        guard current != nil else { return }
        fade?.cancel()
        engine?.mainMixerNode.outputVolume = volume
    }

    private func play(_ kind: Kind) {
        let wasPlaying = current != nil
        current = kind
        fade?.cancel()
        fade = Task {
            if wasPlaying {
                await ramp(to: 0, over: 0.5)
            }
            guard !Task.isCancelled else { return }
            synth.select(kind)
            startEngineIfNeeded()
            await ramp(to: volume, over: 1.6)
        }
    }

    private func stop() {
        current = nil
        fade?.cancel()
        fade = Task {
            await ramp(to: 0, over: 0.9)
            guard !Task.isCancelled, current == nil else { return }
            engine?.stop()
            engine = nil
        }
    }

    private func startEngineIfNeeded() {
        guard engine == nil else { return }
        let engine = AVAudioEngine()
        let output = engine.outputNode.inputFormat(forBus: 0)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: output.sampleRate > 0 ? output.sampleRate : 48_000, channels: 2) else { return }
        synth.sampleRate = format.sampleRate
        let node = Self.makeSource(format: format, synth: synth)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0
        do {
            try engine.start()
            self.engine = engine
        } catch {
            self.engine = nil
        }
    }

    private nonisolated static func makeSource(format: AVAudioFormat, synth: Synth) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, bufferList in
            synth.render(frameCount: Int(frameCount), into: UnsafeMutableAudioBufferListPointer(bufferList))
            return noErr
        }
    }

    private func ramp(to target: Float, over duration: TimeInterval) async {
        guard let mixer = engine?.mainMixerNode else { return }
        let start = mixer.outputVolume
        let steps = max(1, Int(duration * 40))
        for step in 1...steps {
            guard !Task.isCancelled else { return }
            let t = Float(step) / Float(steps)
            mixer.outputVolume = start + (target - start) * (t * t * (3 - 2 * t))
            try? await Task.sleep(for: .milliseconds(25))
        }
    }
}

private final class Synth: @unchecked Sendable {
    var sampleRate = 48_000.0
    private var kind = Soundscape.Kind.cabin.rawValue
    private var time = 0.0
    private var seed: UInt32 = 0x1234_5678
    private var brown = 0.0
    private var pink = (0.0, 0.0, 0.0)
    private var low = 0.0
    private var lowSlow = 0.0
    private var drop = 0.0
    private var dropTone = 0.0

    func select(_ kind: Soundscape.Kind) {
        self.kind = kind.rawValue
    }

    func render(frameCount: Int, into buffers: UnsafeMutableAudioBufferListPointer) {
        let step = 1 / sampleRate
        let left = buffers[0].mData?.assumingMemoryBound(to: Float.self)
        let right = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
        for frame in 0..<frameCount {
            let sample = Float(next())
            left?[frame] = sample
            right?[frame] = sample
            time += step
            if time > 3600 { time -= 3600 }
        }
    }

    private func white() -> Double {
        seed ^= seed << 13
        seed ^= seed >> 17
        seed ^= seed << 5
        return Double(seed) / Double(UInt32.max) * 2 - 1
    }

    private func next() -> Double {
        let w = white()
        brown = (brown + 0.02 * w) / 1.02
        pink.0 = 0.99765 * pink.0 + w * 0.0990460
        pink.1 = 0.96300 * pink.1 + w * 0.2965164
        pink.2 = 0.57000 * pink.2 + w * 1.0526913
        let pinkNoise = (pink.0 + pink.1 + pink.2 + w * 0.1848) * 0.05
        let tau = 2 * Double.pi

        switch kind {
        case Soundscape.Kind.cabin.rawValue:
            low += 0.04 * (brown * 3.5 - low)
            let hum = sin(tau * 94 * time) * 0.012 + sin(tau * 188.3 * time) * 0.005
            return (low * 0.9 + hum) * (0.94 + 0.06 * sin(tau * time / 7))
        case Soundscape.Kind.ocean.rawValue:
            low += 0.09 * (pinkNoise - low)
            let swell = 0.5 + 0.5 * sin(tau * time / 8.5)
            let second = 0.5 + 0.5 * sin(tau * time / 13 + 1.7)
            let envelope = 0.18 + 0.82 * pow(swell, 2.4) * (0.6 + 0.4 * second)
            return low * 2.6 * envelope
        case Soundscape.Kind.space.rawValue:
            lowSlow += 0.01 * (brown * 3.5 - lowSlow)
            let breath = 0.75 + 0.25 * sin(tau * time / 13)
            let drone = sin(tau * 55 * time) * 0.07 + sin(tau * 82.6 * time) * 0.045 + sin(tau * 110.4 * time) * 0.022
            return drone * breath + lowSlow * 0.35
        case Soundscape.Kind.rain.rawValue:
            low += 0.2 * (w - low)
            let hiss = (w - low) * 0.06
            lowSlow += 0.02 * (brown * 3.5 - lowSlow)
            if drop < 0.002, white() > 0.9993 {
                drop = 0.18 + 0.2 * abs(white())
                dropTone = 1800 + 1600 * abs(white())
            }
            drop *= 0.9965
            let droplet = drop * sin(tau * dropTone * time)
            return hiss + lowSlow * 0.25 + droplet * 0.4
        default:
            low += 0.03 * (pinkNoise - low)
            let gust = 0.4 + 0.6 * pow(0.5 + 0.5 * sin(tau * time / 11), 1.6)
            return low * 3.2 * gust
        }
    }
}
