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
        var isSilent = false
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
    @ObservationIgnored private var quietTimer: Timer?
    @ObservationIgnored private var quietUpdate: URL?
    @ObservationIgnored var canRestart: (@MainActor () -> Bool)?
    private(set) var isQuiet = false

    static let installsFixesKey = "installsFixesAutomatically"
    static let updatedFromKey = "quietlyUpdatedFrom"

    var installsFixesAutomatically: Bool {
        get { UserDefaults.standard.object(forKey: Self.installsFixesKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.installsFixesKey) }
    }

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
        if isQuiet { return nil }
        switch state {
        case .available, .downloading, .ready: return pending
        default: return nil
        }
    }

    var isConfigured: Bool {
        Self.repository.contains("/") && !Self.repository.hasPrefix("you/")
    }

    static let failureMarker = URL.cachesDirectory.appending(path: "FocusKitUpdateFailed")

    private(set) var wasBlocked = false
    private(set) var needsAppManagement = false

    func checkOnLaunch() {
        if FileManager.default.fileExists(atPath: Self.failureMarker.path(percentEncoded: false)) {
            try? FileManager.default.removeItem(at: Self.failureMarker)
            wasBlocked = true
        }
        guard (checksAutomatically || wasBlocked), isConfigured else { return }
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
            let body = payload.body ?? ""
            let silent = body.contains("<!-- silent -->")
            let notes = body.replacingOccurrences(of: "<!-- silent -->", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            let release = Release(version: version, notes: notes, diskImage: diskImage, page: page, isSilent: silent)
            if quietUpdate != nil, pending?.version == version, !userInitiated {
                return
            }
            isQuiet = silent && installsFixesAutomatically && !userInitiated && !wasBlocked && !SandboxMigration.isSandboxed
            state = .available(release)
            pending = release
            if isQuiet {
                install(release)
                return
            }
            if !userInitiated || wasBlocked {
                try? await Task.sleep(for: .seconds(wasBlocked ? 0.4 : 1.2))
                presented = release
            }
        } catch {
            state = userInitiated ? .failed("Could not reach GitHub. Check your connection and try again.") : .idle
        }
    }

    @discardableResult
    func checkPermission() -> Bool {
        let probe = Bundle.main.bundleURL.appending(path: "Contents/.update-check").path(percentEncoded: false)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "[ -n \"$1\" ] && touch \"$1\" && rm -f \"$1\"", "sh", probe]
        let allowed = (try? process.run()).map { process.waitUntilExit(); return process.terminationStatus == 0 } ?? false
        needsAppManagement = !allowed
        return allowed
    }

    enum Relaunch: String {
        case open
        case background
        case quiet
        case none
    }

    func openInstaller(_ url: URL) {
        if url.pathExtension == "app", !checkPermission() {
            return
        }
        stopWaitingQuietly()
        guard url.pathExtension == "app" else {
            NSWorkspace.shared.open(url)
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                NSApp.terminate(nil)
            }
            return
        }
        if launchInstaller(url, relaunch: .open) {
            NSApp.terminate(nil)
        } else {
            state = .failed("FocusKit could not install the update by itself. Download it from the release page.")
        }
    }

    @discardableResult
    private func launchInstaller(_ url: URL, relaunch: Relaunch) -> Bool {
        var destination = Bundle.main.bundleURL.standardizedFileURL
        if destination.path(percentEncoded: false).contains("/AppTranslocation/") {
            destination = URL(fileURLWithPath: "/Applications/FocusKit.app")
        }
        let script = """
        [ -n "$1" ] && [ -n "$2" ] && [ -n "$3" ] && [ -n "$4" ] && [ -n "$5" ] || exit 1
        STAGED="${2%/}"
        APP="${3%/}"
        WORK="${4%/}"
        case "$APP" in */*.app) ;; *) exit 1 ;; esac
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        rm -rf "$APP.updating" "$APP.previous"
        if ditto "$STAGED" "$APP.updating" && mv "$APP" "$APP.previous"; then
          if mv "$APP.updating" "$APP"; then
            rm -rf "$APP.previous"
            xattr -dr com.apple.quarantine "$APP" 2>/dev/null
          else
            mv "$APP.previous" "$APP"
            touch "$5"
          fi
        else
          rm -rf "$APP.updating"
          touch "$5"
        fi
        case "$6" in
          none) ;;
          quiet) open -g -j "$APP" --args --quiet-relaunch ;;
          background) open -g "$APP" ;;
          *) open "$APP" ;;
        esac
        rm -rf "$WORK"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        try? FileManager.default.removeItem(at: Self.failureMarker)
        process.arguments = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier), Self.plainPath(url), Self.plainPath(destination), Self.plainPath(url.deletingLastPathComponent()), Self.plainPath(Self.failureMarker), relaunch.rawValue]
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    func installBeforeQuitting() {
        guard let quietUpdate else { return }
        stopWaitingQuietly()
        UserDefaults.standard.set(Self.currentVersion, forKey: Self.updatedFromKey)
        launchInstaller(quietUpdate, relaunch: .none)
    }

    private func waitQuietly(with url: URL) {
        quietUpdate = url
        quietTimer?.invalidate()
        quietTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.installIfQuiet() }
        }
        quietTimer?.tolerance = 20
    }

    private func stopWaitingQuietly() {
        quietTimer?.invalidate()
        quietTimer = nil
        quietUpdate = nil
    }

    private func installIfQuiet() {
        guard let quietUpdate, installsFixesAutomatically, canRestart?() ?? false else { return }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        guard LockScreen.isLocked || idle > 15 * 60 else { return }
        let showsWindow = NSApp.windows.contains { $0.isVisible && $0.identifier?.rawValue.hasPrefix("main") == true }
        stopWaitingQuietly()
        UserDefaults.standard.set(Self.currentVersion, forKey: Self.updatedFromKey)
        if launchInstaller(quietUpdate, relaunch: showsWindow ? .background : .quiet) {
            NSApp.terminate(nil)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.updatedFromKey)
        }
    }

    static func takeQuietUpdateNotice() -> String? {
        let defaults = UserDefaults.standard
        guard let previous = defaults.string(forKey: updatedFromKey) else { return nil }
        defaults.removeObject(forKey: updatedFromKey)
        return isNewer(currentVersion, than: previous) ? currentVersion : nil
    }

    nonisolated private static func plainPath(_ url: URL) -> String {
        var path = url.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
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
                    let staged = try await Self.stage(destination, in: work)
                    state = .ready(staged)
                    if checkPermission(), isQuiet {
                        waitQuietly(with: staged)
                        return
                    }
                }
                isQuiet = false
                presented = release
            } catch {
                guard !isQuiet else {
                    isQuiet = false
                    state = .idle
                    pending = nil
                    return
                }
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
