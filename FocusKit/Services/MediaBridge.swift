import AppKit

@MainActor
final class MediaBridge {
    struct Snapshot: Sendable {
        let bundleID: String
        let app: String
        let title: String
        let artist: String
        let duration: TimeInterval
        let elapsed: TimeInterval
        let timestamp: Date
        let isPlaying: Bool
        let artwork: Data?
    }

    enum Command: Int32 {
        case togglePlayPause = 2
        case next = 4
        case previous = 5
    }

    var onUpdate: ((Snapshot) -> Void)?

    private var process: Process?
    private var restarts = 0
    private static let script = "use DynaLoader; my $l = DynaLoader::dl_load_file($ARGV[0], 0) or exit 3; my $s = DynaLoader::dl_find_symbol($l, $ARGV[1]) or exit 4; DynaLoader::dl_install_xsub('main::run', $s); run();"

    private static var library: URL? {
        guard let url = Bundle.main.url(forResource: "NowPlayingBridge", withExtension: "dylib"),
              FileManager.default.isExecutableFile(atPath: "/usr/bin/perl") else { return nil }
        return url
    }

    var isAvailable: Bool {
        Self.library != nil
    }

    func start() {
        guard process == nil, let library = Self.library else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-e", Self.script, library.path(percentEncoded: false), "FocusKitNowPlayingStream"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let reader = LineReader { [weak self] line in
            guard let snapshot = Self.decode(line) else { return }
            Task { @MainActor in self?.onUpdate?(snapshot) }
        }
        output.fileHandleForReading.readabilityHandler = { handle in
            reader.consume(handle.availableData)
        }
        process.terminationHandler = { [weak self] _ in
            output.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in self?.restart() }
        }
        do {
            try process.run()
            self.process = process
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
        }
    }

    func stop() {
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
    }

    func send(_ command: Command) {
        run(environment: ["FOCUSKIT_COMMAND": String(command.rawValue)])
    }

    func seek(to position: TimeInterval) {
        run(environment: ["FOCUSKIT_POSITION": String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), position)])
    }

    private func run(environment: [String: String]) {
        guard let library = Self.library else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-e", Self.script, library.path(percentEncoded: false), "FocusKitNowPlayingCommand"]
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    private func restart() {
        process = nil
        guard restarts < 5 else { return }
        restarts += 1
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double(self?.restarts ?? 1) * 2))
            self?.start()
        }
    }

    private nonisolated static func decode(_ line: Data) -> Snapshot? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return nil }
        return Snapshot(
            bundleID: object["bundle"] as? String ?? "",
            app: object["app"] as? String ?? "",
            title: object["title"] as? String ?? "",
            artist: object["artist"] as? String ?? "",
            duration: (object["duration"] as? NSNumber)?.doubleValue ?? 0,
            elapsed: (object["elapsed"] as? NSNumber)?.doubleValue ?? 0,
            timestamp: Date(timeIntervalSince1970: (object["timestamp"] as? NSNumber)?.doubleValue ?? Date.now.timeIntervalSince1970),
            isPlaying: object["playing"] as? Bool ?? false,
            artwork: (object["artwork"] as? String).flatMap { Data(base64Encoded: $0) }
        )
    }
}

private final class LineReader: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()
    private let handle: @Sendable (Data) -> Void

    init(handle: @escaping @Sendable (Data) -> Void) {
        self.handle = handle
    }

    func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        buffer.append(data)
        var lines: [Data] = []
        while let index = buffer.firstIndex(of: 0x0A) {
            lines.append(buffer[buffer.startIndex..<index])
            buffer.removeSubrange(buffer.startIndex...index)
        }
        lock.unlock()
        lines.forEach(handle)
    }
}
