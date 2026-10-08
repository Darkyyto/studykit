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
        var archive: URL?
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
    @ObservationIgnored private var periodicCheck: Timer?
    @ObservationIgnored private var wakeObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var lastBackgroundCheck = Date.distantPast
    private(set) var isQuiet = false

    static let installsFixesKey = "installsFixesAutomatically"

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
        guard isConfigured else { return }
        if checksAutomatically || wasBlocked {
            lastBackgroundCheck = .now
            Task { await check(userInitiated: false) }
        }
        periodicCheck?.invalidate()
        periodicCheck = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkInBackground() }
        }
        periodicCheck?.tolerance = 120
        guard wakeObservers.isEmpty else { return }
        let names: [(NotificationCenter, Notification.Name)] = [
            (NotificationCenter.default, NSApplication.didBecomeActiveNotification),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification),
        ]
        wakeObservers = names.map { center, name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.checkInBackground() }
                }
            }
        }
    }

    private func checkInBackground() {
        guard checksAutomatically, isConfigured, quietUpdate == nil, download == nil,
              Date.now.timeIntervalSince(lastBackgroundCheck) > 10 * 60 else { return }
        if case .checking = state { return }
        lastBackgroundCheck = .now
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
            guard let latest = try await Self.latest() else {
                state = .failed("GitHub is not responding right now. Try again in a few minutes.")
                return
            }
            let version = latest.version
            UserDefaults.standard.set(Date.now, forKey: Self.lastCheckKey)
            lastChecked = .now

            guard
                Self.isNewer(version, than: Self.currentVersion),
                userInitiated || UserDefaults.standard.string(forKey: Self.skippedKey) != version
            else {
                state = .upToDate
                return
            }
            let diskImage = latest.diskImage
            let page = latest.page
            let archive = latest.archive
            let body = latest.notes
            let silent = body.contains("<!-- silent -->")
            let notes = body.replacingOccurrences(of: "<!-- silent -->", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            let release = Release(version: version, notes: notes, diskImage: diskImage, page: page, isSilent: silent, archive: archive)
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

    private struct Latest {
        let version: String
        let notes: String
        let diskImage: URL
        let page: URL
        var archive: URL?
    }

    private struct Manifest: Decodable {
        let version: String
        let notes: String
        let dmg: String
        let page: String
        let zip: String?
    }

    private static func latest() async throws -> Latest? {
        var manifest = URLRequest(url: URL(string: "https://github.com/\(repository)/releases/latest/download/update.json")!)
        manifest.timeoutInterval = 15
        manifest.cachePolicy = .reloadIgnoringLocalCacheData
        if let (data, response) = try? await URLSession.shared.data(for: manifest),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let decoded = try? JSONDecoder().decode(Manifest.self, from: data),
           let diskImage = URL(string: decoded.dmg),
           let page = URL(string: decoded.page) {
            return Latest(version: decoded.version.trimmingCharacters(in: CharacterSet(charactersIn: "vV")), notes: decoded.notes, diskImage: diskImage, page: page, archive: decoded.zip.flatMap(URL.init(string:)))
        }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard
            let asset = payload.assets.first(where: { $0.name.hasSuffix(".dmg") }),
            let diskImage = URL(string: asset.browser_download_url),
            let page = URL(string: payload.html_url)
        else { return nil }
        return Latest(version: payload.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV")), notes: payload.body ?? "", diskImage: diskImage, page: page)
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
        while kill -0 "$1" 2>/dev/null; do sleep 0.1; done
        rm -rf "$APP.updating" "$APP.previous"
        if { mv "$STAGED" "$APP.updating" 2>/dev/null || ditto "$STAGED" "$APP.updating"; } && mv "$APP" "$APP.previous"; then
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
        process.arguments = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier), Self.plainPath(url), Self.plainPath(destination), Self.plainPath(FileManager.default.temporaryDirectory.appending(path: "FocusKitUpdate", directoryHint: .isDirectory)), Self.plainPath(Self.failureMarker), relaunch.rawValue]
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
        launchInstaller(quietUpdate, relaunch: .none)
    }

    private func waitQuietly(with url: URL) {
        quietUpdate = url
        quietTimer?.invalidate()
        quietTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.installIfQuiet() }
        }
        quietTimer?.tolerance = 5
        installIfQuiet()
    }

    private func stopWaitingQuietly() {
        quietTimer?.invalidate()
        quietTimer = nil
        quietUpdate = nil
    }

    private func installIfQuiet() {
        guard let quietUpdate, installsFixesAutomatically, canRestart?() ?? false else { return }
        let showsWindow = NSApp.windows.contains { $0.isVisible && $0.identifier?.rawValue.hasPrefix("main") == true }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        guard !showsWindow || LockScreen.isLocked || idle > 120 else { return }
        stopWaitingQuietly()
        if launchInstaller(quietUpdate, relaunch: showsWindow ? .background : .quiet) {
            NSApp.terminate(nil)
        }
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
            try run("/usr/bin/hdiutil", ["attach", "-quiet", "-nobrowse", "-readonly", "-noverify", "-noautofsck", "-mountpoint", mount.path(percentEncoded: false), diskImage.path(percentEncoded: false)])
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

    nonisolated private static func unpack(_ archive: URL, in work: URL) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let folder = work.appending(path: "unpacked", directoryHint: .isDirectory)
            try? FileManager.default.removeItem(at: folder)
            try run("/usr/bin/ditto", ["-x", "-k", archive.path(percentEncoded: false), folder.path(percentEncoded: false)])
            let staged = folder.appending(path: "FocusKit.app", directoryHint: .isDirectory)
            guard Bundle(url: staged)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
                throw CocoaError(.fileReadCorruptFile)
            }
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
                let tracker = DownloadTracker()
                let progress = Task {
                    while !Task.isCancelled {
                        if let fraction = tracker.fraction, case .downloading = state {
                            state = .downloading(min(1, fraction))
                        }
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                }
                defer { progress.cancel() }
                let archive = SandboxMigration.isSandboxed ? nil : release.archive
                let (location, response) = try await URLSession.shared.download(from: archive ?? release.diskImage, delegate: tracker)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                let work = FileManager.default.temporaryDirectory.appending(path: "FocusKitUpdate", directoryHint: .isDirectory)
                try? FileManager.default.removeItem(at: work)
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                let destination = work.appending(path: "FocusKit-\(release.version).\(archive == nil ? "dmg" : "zip")")
                try FileManager.default.moveItem(at: location, to: destination)
                state = .downloading(1)
                Backup.make(reason: "before-\(release.version)")
                if SandboxMigration.isSandboxed {
                    state = .ready(destination)
                } else {
                    let staged = try await archive == nil ? Self.stage(destination, in: work) : Self.unpack(destination, in: work)
                    state = .ready(staged)
                    if isQuiet {
                        if checkPermission() {
                            waitQuietly(with: staged)
                        }
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

private final class DownloadTracker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?

    var fraction: Double? {
        lock.withLock { task.map { $0.progress.fractionCompleted } }
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        lock.withLock { self.task = task }
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
