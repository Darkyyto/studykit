import AppKit
import Observation

@MainActor
@Observable
final class Updater {
    struct Release: Equatable, Identifiable {
        var id: String { version }
        let version: String
        let notes: String
        let diskImage: URL
        let page: URL
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading(Double)
        case ready(URL)
        case failed(String)
    }

    private(set) var state = State.idle
    private(set) var lastChecked: Date?
    var presented: Release?
    private(set) var pending: Release?

    @ObservationIgnored private var download: Task<Void, Never>?

    nonisolated static let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    nonisolated static var repositoryName: String { repository }
    nonisolated private static let repository = Bundle.main.object(forInfoDictionaryKey: "FocusKitRepository") as? String ?? ""
    private static let checksAutomaticallyKey = "checksForUpdates"
    private static let lastCheckKey = "lastUpdateCheck"
    private static let skippedKey = "skippedVersion"

    var checksAutomatically: Bool {
        get { UserDefaults.standard.object(forKey: Self.checksAutomaticallyKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.checksAutomaticallyKey) }
    }

    var available: Release? {
        switch state {
        case .available, .downloading, .ready: pending
        default: nil
        }
    }

    var isConfigured: Bool {
        Self.repository.contains("/") && !Self.repository.hasPrefix("you/")
    }

    func checkOnLaunch() {
        guard checksAutomatically, isConfigured else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        guard Date.now.timeIntervalSince(last) > 60 else { return }
        Task { await check(userInitiated: false) }
    }

    func check(userInitiated: Bool) async {
        guard isConfigured else {
            state = .failed("Set FOCUSKIT_REPOSITORY in project.yml to enable updates.")
            return
        }
        if case .downloading = state { return }
        state = .checking
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                state = .failed("No published release was found.")
                return
            }
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            let version = payload.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            UserDefaults.standard.set(Date.now, forKey: Self.lastCheckKey)
            lastChecked = .now

            guard
                Self.isNewer(version, than: Self.currentVersion),
                userInitiated || UserDefaults.standard.string(forKey: Self.skippedKey) != version,
                let asset = payload.assets.first(where: { $0.name.hasSuffix(".dmg") }),
                let diskImage = URL(string: asset.browser_download_url),
                let page = URL(string: payload.html_url)
            else {
                state = .upToDate
                return
            }
            let release = Release(version: version, notes: payload.body ?? "", diskImage: diskImage, page: page)
            state = .available(release)
            pending = release
            if !userInitiated {
                try? await Task.sleep(for: .seconds(1.2))
                presented = release
            }
        } catch {
            state = userInitiated ? .failed("Could not reach GitHub. Check your connection and try again.") : .idle
        }
    }

    func openInstaller(_ url: URL) {
        guard url.pathExtension == "app" else {
            NSWorkspace.shared.open(url)
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                NSApp.terminate(nil)
            }
            return
        }
        var destination = Bundle.main.bundleURL
        if destination.path(percentEncoded: false).contains("/AppTranslocation/") {
            destination = URL(fileURLWithPath: "/Applications/FocusKit.app")
        }
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        rm -rf "$3.previous"
        if mv "$3" "$3.previous" && ditto "$2" "$3"; then
          rm -rf "$3.previous"
        else
          rm -rf "$3"
          mv "$3.previous" "$3"
        fi
        xattr -dr com.apple.quarantine "$3" 2>/dev/null
        open "$3"
        rm -rf "$4"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier), url.path(percentEncoded: false), destination.path(percentEncoded: false), url.deletingLastPathComponent().path(percentEncoded: false)]
        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            state = .failed("FocusKit could not install the update by itself. Download it from the release page.")
        }
    }

    nonisolated private static func stage(_ diskImage: URL, in work: URL) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let mount = work.appending(path: "volume", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
            try run("/usr/bin/hdiutil", ["attach", "-quiet", "-nobrowse", "-readonly", "-mountpoint", mount.path(percentEncoded: false), diskImage.path(percentEncoded: false)])
            defer { try? run("/usr/bin/hdiutil", ["detach", "-quiet", "-force", mount.path(percentEncoded: false)]) }
            let source = mount.appending(path: "FocusKit.app", directoryHint: .isDirectory)
            guard Bundle(url: source)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let staged = work.appending(path: "FocusKit.app", directoryHint: .isDirectory)
            try? FileManager.default.removeItem(at: staged)
            try run("/usr/bin/ditto", [source.path(percentEncoded: false), staged.path(percentEncoded: false)])
            try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path(percentEncoded: false)])
            return staged
        }.value
    }

    nonisolated private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    func skip(_ release: Release) {
        UserDefaults.standard.set(release.version, forKey: Self.skippedKey)
        state = .idle
        pending = nil
        presented = nil
    }

    func install(_ release: Release) {
        guard download == nil else { return }
        state = .downloading(0)
        download = Task {
            defer { download = nil }
            do {
                let (bytes, response) = try await URLSession.shared.bytes(from: release.diskImage)
                let expected = Double(max(response.expectedContentLength, 1))
                let work = FileManager.default.temporaryDirectory.appending(path: "FocusKitUpdate", directoryHint: .isDirectory)
                try? FileManager.default.removeItem(at: work)
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                let destination = work.appending(path: "FocusKit-\(release.version).dmg")
                try? FileManager.default.removeItem(at: destination)
                FileManager.default.createFile(atPath: destination.path(percentEncoded: false), contents: nil)
                let handle = try FileHandle(forWritingTo: destination)
                var buffer = Data()
                var received = 0.0
                for try await byte in bytes {
                    buffer.append(byte)
                    if buffer.count >= 256 * 1024 {
                        try handle.write(contentsOf: buffer)
                        received += Double(buffer.count)
                        buffer.removeAll(keepingCapacity: true)
                        state = .downloading(min(1, received / expected))
                    }
                }
                try handle.write(contentsOf: buffer)
                try handle.close()
                Backup.make(reason: "before-\(release.version)")
                if SandboxMigration.isSandboxed {
                    state = .ready(destination)
                } else {
                    state = .ready(try await Self.stage(destination, in: work))
                }
                presented = release
            } catch {
                state = .failed("The download did not finish. You can get it from the release page instead.")
                NSWorkspace.shared.open(release.page)
            }
        }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(lhs.count, rhs.count) {
            let a = index < lhs.count ? lhs[index] : 0
            let b = index < rhs.count ? rhs[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private struct Payload: Decodable {
        let tag_name: String
        let html_url: String
        let body: String?
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
    }
}

enum Backup {
    private static let keep = 8
    private static let versionKey = "lastLaunchedVersion"

    static var directory: URL {
        Library.Location.standard.root.appending(path: "Backups", directoryHint: .isDirectory)
    }

    static func onLaunch() {
        let previous = UserDefaults.standard.string(forKey: versionKey)
        if previous != Updater.currentVersion {
            make(reason: "from-\(previous ?? "first-launch")")
            UserDefaults.standard.set(Updater.currentVersion, forKey: versionKey)
            return
        }
        let newest = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey]))?
            .compactMap { try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate }
            .max() ?? .distantPast
        if Date.now.timeIntervalSince(newest) > 24 * 3600 {
            make(reason: "daily")
        }
    }

    static func make(reason: String) {
        let source = Library.Location.standard.database
        guard FileManager.default.fileExists(atPath: source.path(percentEncoded: false)) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacing(":", with: "-")
        try? FileManager.default.copyItem(at: source, to: directory.appending(path: "Library \(stamp) \(reason).json"))

        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        let sorted = files.sorted {
            let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return a > b
        }
        for file in sorted.dropFirst(keep) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
