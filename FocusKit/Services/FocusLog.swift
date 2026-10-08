import Foundation

final class FocusLog: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.focuskit.focuslog")
    private let handler: @Sendable (String, Bool) -> Void
    private var process: Process?
    private var isWanted = false
    private var buffer = Data()
    private var last: (identifier: String, isOn: Bool, date: Date)?

    init(handler: @escaping @Sendable (String, Bool) -> Void) {
        self.handler = handler
    }

    func start() {
        queue.async {
            self.isWanted = true
            self.launch()
        }
    }

    func stop() {
        queue.async {
            self.isWanted = false
            self.process?.terminate()
            self.process = nil
        }
    }

    private func launch() {
        guard isWanted, process == nil else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        task.arguments = [
            "stream", "--style", "compact",
            "--predicate", "process == \"duetexpertd\" AND eventMessage CONTAINS \"userFocusComputedModeEvent\"",
        ]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            guard let owner = self else { return }
            owner.queue.async { owner.consume(data) }
        }
        task.terminationHandler = { [weak self] ended in
            guard let owner = self else { return }
            owner.queue.asyncAfter(deadline: .now() + 5) {
                guard owner.process === ended else { return }
                owner.process = nil
                owner.launch()
            }
        }
        do {
            try task.run()
            process = task
        } catch {
            process = nil
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex...newline)
            parse(line)
        }
        if buffer.count > 65_536 {
            buffer.removeAll()
        }
    }

    private func parse(_ line: String) {
        guard let starting = line.range(of: "starting: ") else { return }
        let isOn = line[starting.upperBound...].hasPrefix("1")
        var identifier = ""
        if let key = line.range(of: "semanticModeIdentifier: ") {
            identifier = String(line[key.upperBound...].prefix { $0 != "," && $0 != " " && $0 != "\n" })
        }
        if let last, last.identifier == identifier, last.isOn == isOn, Date.now.timeIntervalSince(last.date) < 2 {
            return
        }
        last = (identifier, isOn, .now)
        handler(identifier, isOn)
    }
}
