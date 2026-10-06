@preconcurrency import AVFoundation
import Speech

final class AudioCapture: @unchecked Sendable {
    enum Failure: LocalizedError {
        case noInputDevice
        case unsupportedFormat

        var errorDescription: String? {
            switch self {
            case .noInputDevice: "No microphone is available."
            case .unsupportedFormat: "The microphone format is not supported."
            }
        }
    }

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var fileConverter: AVAudioConverter?
    private var speechConverter: AVAudioConverter?
    private var speechInput: AsyncStream<AnalyzerInput>.Continuation?
    private var levelHandler: (@Sendable (Float) -> Void)?
    private var conditioner = SpeechConditioner(sampleRate: AudioCapture.sampleRate)

    static let sampleRate = 16_000.0
    static let fileExtension = "caf"

    func start(
        writingTo url: URL,
        speechFormat: AVAudioFormat?,
        speechInput: AsyncStream<AnalyzerInput>.Continuation?,
        onLevel: @escaping @Sendable (Float) -> Void
    ) throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw Failure.noInputDevice }

        guard
            let fileFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1, interleaved: false),
            let fileConverter = AVAudioConverter(from: inputFormat, to: fileFormat)
        else { throw Failure.unsupportedFormat }

        let file = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatAppleIMA4,
                AVSampleRateKey: Self.sampleRate,
                AVNumberOfChannelsKey: 1,
            ],
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        lock.withLock {
            self.file = file
            self.fileConverter = fileConverter
            self.conditioner = SpeechConditioner(sampleRate: Self.sampleRate)
            self.speechConverter = speechFormat.flatMap { AVAudioConverter(from: fileFormat, to: $0) }
            self.speechInput = speechInput
            self.levelHandler = onLevel
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.withLock {
            speechInput?.finish()
            speechInput = nil
            file?.close()
            file = nil
            fileConverter = nil
            speechConverter = nil
            levelHandler = nil
        }
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            guard let fileConverter, let mono = convert(buffer, using: fileConverter) else { return }
            if let samples = mono.floatChannelData?[0] {
                conditioner.process(samples, count: Int(mono.frameLength))
            }
            try? file?.write(from: mono)
            levelHandler?(Self.level(of: mono))
            if let speechConverter, let speechInput, let converted = convert(mono, using: speechConverter) {
                speechInput.yield(AnalyzerInput(buffer: converted))
            }
        }
    }

    private func convert(_ buffer: AVAudioPCMBuffer, using converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else { return nil }

        let source = SingleBufferSource(buffer)
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, status in
            source.next(status)
        }
        guard status != .error, error == nil, output.frameLength > 0 else { return nil }
        return output
    }

    private static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<count {
            sum += samples[index] * samples[index]
        }
        let decibels = 20 * log10(max(sqrt(sum / Float(count)), 1e-6))
        return min(1, max(0, (decibels + 55) / 50))
    }
}

private final class SingleBufferSource: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard let buffer else {
            status.pointee = .noDataNow
            return nil
        }
        self.buffer = nil
        status.pointee = .haveData
        return buffer
    }
}
