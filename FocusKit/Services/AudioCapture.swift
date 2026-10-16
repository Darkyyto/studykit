@preconcurrency import AVFoundation
import CoreAudio
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
    private let queue = DispatchQueue(label: "AudioCapture")
    private var file: AVAudioFile?
    private var fileFormat: AVAudioFormat?
    private var fileConverter: AVAudioConverter?
    private var speechConverter: AVAudioConverter?
    private var speechInput: AsyncStream<AnalyzerInput>.Continuation?
    private var levelHandler: (@Sendable (Float) -> Void)?
    private var conditioner = SpeechConditioner(sampleRate: AudioCapture.sampleRate)
    private var lastBuffer = Date.now
    private var running = false
    private var changeObserver: NSObjectProtocol?
    private var watchdog: DispatchSourceTimer?

    static let sampleRate = 16_000.0
    static let fileExtension = "caf"

    func start(
        writingTo url: URL,
        speechFormat: AVAudioFormat?,
        speechInput: AsyncStream<AnalyzerInput>.Continuation?,
        onLevel: @escaping @Sendable (Float) -> Void
    ) throws {
        guard let fileFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1, interleaved: false) else {
            throw Failure.unsupportedFormat
        }

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
            self.fileFormat = fileFormat
            self.conditioner = SpeechConditioner(sampleRate: Self.sampleRate)
            self.speechConverter = speechFormat.flatMap { AVAudioConverter(from: fileFormat, to: $0) }
            self.speechInput = speechInput
            self.levelHandler = onLevel
        }

        try connectInput()
        lock.withLock { running = true }

        // The engine stops on its own when the input changes (AirPods, a dock, a system hiccup). Bring it back.
        changeObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            self?.queue.async { self?.reconnect() }
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 3, repeating: 2)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let stalled = lock.withLock { running && Date.now.timeIntervalSince(lastBuffer) > 3 }
            if stalled { reconnect() }
        }
        timer.resume()
        watchdog = timer
    }

    private func connectInput() throws {
        let input = engine.inputNode
        Self.preferBuiltInMicrophone(for: input)
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw Failure.noInputDevice }
        guard let fileFormat = lock.withLock({ self.fileFormat }),
              let fileConverter = AVAudioConverter(from: inputFormat, to: fileFormat) else { throw Failure.unsupportedFormat }
        lock.withLock {
            self.fileConverter = fileConverter
            lastBuffer = .now
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    private func reconnect() {
        let healthy = lock.withLock { Date.now.timeIntervalSince(lastBuffer) < 1 }
        guard lock.withLock({ running }), !(engine.isRunning && healthy) else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine.reset()
        do {
            try connectInput()
        } catch {
            // No usable microphone right now: the watchdog tries again in a couple of seconds.
            lock.withLock { lastBuffer = .now }
        }
    }

    func stop() {
        watchdog?.cancel()
        watchdog = nil
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
        changeObserver = nil
        queue.sync {
            lock.withLock { running = false }
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
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
            lastBuffer = .now
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

    /// Bluetooth headsets record in narrow phone quality and switch the music to it too. For a lecture the Mac's own microphone hears far better.
    private static func preferBuiltInMicrophone(for input: AVAudioInputNode) {
        guard let unit = input.audioUnit,
              let current = defaultInputDevice(),
              [kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE].contains(transportType(of: current)),
              let builtIn = inputDevices().first(where: { transportType(of: $0) == kAudioDeviceTransportTypeBuiltIn }) else { return }
        var device = builtIn
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, UInt32(MemoryLayout<AudioDeviceID>.size))
    }

    private static func defaultInputDevice() -> AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr, device != 0 else { return nil }
        return device
    }

    private static func inputDevices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices.filter { device in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var bytes: UInt32 = 0
            return AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &bytes) == noErr && bytes > 0
        }
    }

    private static func transportType(of device: AudioDeviceID) -> UInt32 {
        var type: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &type)
        return type
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
