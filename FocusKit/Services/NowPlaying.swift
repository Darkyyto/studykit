import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class NowPlaying {
    enum Player: String, Sendable {
        case spotify = "com.spotify.client"
        case music = "com.apple.Music"

        var scriptName: String {
            switch self {
            case .spotify: "Spotify"
            case .music: "Music"
            }
        }
    }

    private struct Update: Sendable {
        let player: Player
        let title: String
        let artist: String
        let state: String
        let duration: TimeInterval
        let position: TimeInterval?
    }

    struct Source: Equatable, Sendable {
        let bundleID: String
        let name: String
    }

    private(set) var player: Player?
    private(set) var source: Source?
    private(set) var title = ""
    private(set) var artist = ""
    private(set) var isPlaying = false
    private(set) var duration: TimeInterval = 0
    private(set) var artwork: NSImage?
    private(set) var accent = Color(white: 0.85)

    @ObservationIgnored private var position: TimeInterval = 0
    @ObservationIgnored private var positionDate = Date.now
    @ObservationIgnored private var trackKey = ""
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var lastSync = Date.distantPast
    @ObservationIgnored private var resync: Task<Void, Never>?
    @ObservationIgnored private let bridge = MediaBridge()
    @ObservationIgnored private var expectedPlaying: Bool?
    @ObservationIgnored private var expectationEnds = Date.distantPast

    init() {
        observers = [
            DistributedObserver("com.spotify.client.PlaybackStateChanged") { [weak self] note in
                let update = Self.parse(note.userInfo, player: .spotify)
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.apply(update) } }
            },
            DistributedObserver("com.apple.Music.playerInfo") { [weak self] note in
                let update = Self.parse(note.userInfo, player: .music)
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.apply(update) } }
            },
        ]
        bridge.onUpdate = { [weak self] snapshot in self?.apply(snapshot) }
        bridge.start()
    }

    var hasTrack: Bool {
        (player != nil || source != nil) && !title.isEmpty
    }

    var appName: String {
        player?.scriptName ?? source?.name ?? ""
    }

    var appBundleID: String? {
        player?.rawValue ?? source?.bundleID
    }

    func elapsed(at date: Date) -> TimeInterval {
        let value = position + (isPlaying ? date.timeIntervalSince(positionDate) : 0)
        return duration > 0 ? min(duration, value) : value
    }

    func refreshIfNeeded() {
        sync()
    }

    func sync(force: Bool = false) {
        guard force || Date.now.timeIntervalSince(lastSync) > 1.5 else { return }
        lastSync = .now
        var found: [Update] = []
        for candidate in [Player.spotify, .music] where Self.isRunning(candidate) {
            let script = """
                tell application "\(candidate.scriptName)"
                    if player state is stopped then return ""
                    set t to current track
                    set d to duration of t
                    return (name of t) & tab & (artist of t) & tab & (player state as text) & tab & (d as text) & tab & (player position as text)
                end tell
                """
            guard let result = Self.run(script)?.stringValue, !result.isEmpty else { continue }
            let parts = result.components(separatedBy: "\t")
            guard parts.count >= 5 else { continue }
            let rawDuration = Double(parts[3].replacingOccurrences(of: ",", with: ".")) ?? 0
            found.append(Update(
                player: candidate,
                title: parts[0],
                artist: parts[1],
                state: parts[2].lowercased().contains("play") ? "Playing" : "Paused",
                duration: candidate == .spotify ? rawDuration / 1000 : rawDuration,
                position: Double(parts[4].replacingOccurrences(of: ",", with: "."))
            ))
        }
        let chosen = found.first { $0.state == "Playing" } ?? found.first { $0.player == player } ?? found.first
        guard let chosen, source == nil || chosen.state == "Playing" else { return }
        apply(chosen, force: true)
    }

    func togglePlayback() {
        position = elapsed(at: .now)
        positionDate = .now
        if player != nil {
            command("playpause")
        } else if source != nil {
            bridge.send(.togglePlayPause)
        }
        isPlaying.toggle()
        expectedPlaying = isPlaying
        expectationEnds = .now.addingTimeInterval(1.2)
        resyncSoon()
    }

    private func contradictsExpectation(_ playing: Bool) -> Bool {
        guard let expectedPlaying, Date.now < expectationEnds else {
            expectedPlaying = nil
            return false
        }
        return playing != expectedPlaying
    }

    func next() {
        if player != nil {
            command("next track")
        } else if source != nil {
            bridge.send(.next)
        }
        resyncSoon()
    }

    func previous() {
        if player != nil {
            command("previous track")
        } else if source != nil {
            bridge.send(.previous)
        }
        resyncSoon()
    }

    func seek(to fraction: Double) {
        guard duration > 0 else { return }
        let target = min(duration, max(0, duration * fraction))
        if player != nil {
            command("set player position to \(String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), target))")
        } else if source != nil {
            bridge.seek(to: target)
        }
        position = target
        positionDate = .now
        resyncSoon()
    }

    private func resyncSoon() {
        resync?.cancel()
        resync = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1300))
            guard !Task.isCancelled else { return }
            self?.sync(force: true)
        }
    }

    static func isInstalled(_ player: Player) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.rawValue) != nil
    }

    func play(in player: Player) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.rawValue) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                _ = Self.run("tell application \"\(player.scriptName)\" to play")
                self.refreshIfNeeded()
            }
        }
    }

    func open() {
        guard let bundleID = appBundleID, !bundleID.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func command(_ verb: String) {
        guard let player, Self.isRunning(player) else { return }
        Self.run("tell application \"\(player.scriptName)\" to \(verb)")
    }

    private func apply(_ update: Update?, force: Bool = false) {
        guard let update else { return }
        if update.player == player, contradictsExpectation(update.state == "Playing") {
            return
        }
        if !force, isPlaying, update.state != "Playing", source != nil || (player != nil && player != update.player) {
            return
        }
        if update.state == "Stopped" || update.title.isEmpty {
            if player == update.player {
                player = nil
                title = ""
                isPlaying = false
                artwork = nil
            }
            return
        }
        let sameTrack = player == update.player && title == update.title && artist == update.artist
        let current = elapsed(at: .now)
        if let value = update.position {
            position = value
        } else if update.player == .music, let value = Self.run("tell application \"Music\" to player position")?.doubleValue {
            position = value
        } else {
            position = sameTrack ? current : 0
        }
        positionDate = .now
        player = update.player
        source = nil
        title = update.title
        artist = update.artist
        isPlaying = update.state == "Playing"
        duration = update.duration

        let key = "\(update.player.rawValue)|\(update.title)|\(update.artist)"
        guard key != trackKey else { return }
        trackKey = key
        loadArtwork(for: update.player, key: key)
    }

    private func apply(_ snapshot: MediaBridge.Snapshot) {
        if Player(rawValue: snapshot.bundleID) != nil {
            return
        }
        guard !snapshot.title.isEmpty else {
            if source != nil {
                source = nil
                title = ""
                artist = ""
                isPlaying = false
                artwork = nil
                trackKey = ""
            }
            return
        }
        if player != nil, isPlaying, !snapshot.isPlaying {
            return
        }
        if source?.bundleID == snapshot.bundleID, contradictsExpectation(snapshot.isPlaying) {
            return
        }
        let name = snapshot.app.isEmpty ? (snapshot.bundleID.isEmpty ? "Now Playing" : snapshot.bundleID) : snapshot.app
        player = nil
        source = Source(bundleID: snapshot.bundleID, name: name)
        title = snapshot.title
        artist = snapshot.artist
        isPlaying = snapshot.isPlaying
        duration = snapshot.duration
        position = snapshot.elapsed + (snapshot.isPlaying ? max(0, Date.now.timeIntervalSince(snapshot.timestamp)) : 0)
        positionDate = .now

        let key = "\(snapshot.bundleID)|\(snapshot.title)|\(snapshot.artist)"
        if let data = snapshot.artwork, key != trackKey || artwork == nil, let image = NSImage(data: data) {
            trackKey = key
            withAnimation(Motion.standard) {
                artwork = image
                accent = Self.averageColor(of: image) ?? Color(white: 0.85)
            }
        } else if key != trackKey {
            trackKey = key
            artwork = nil
            accent = Color(white: 0.85)
        }
    }

    private func loadArtwork(for player: Player, key: String) {
        Task {
            var image: NSImage?
            switch player {
            case .spotify:
                if let string = Self.run("tell application \"Spotify\" to artwork url of current track")?.stringValue,
                   let url = URL(string: string),
                   let (data, _) = try? await URLSession.shared.data(from: url) {
                    image = NSImage(data: data)
                }
            case .music:
                if let data = Self.run("tell application \"Music\" to get raw data of artwork 1 of current track")?.data {
                    image = NSImage(data: data)
                }
            }
            guard trackKey == key else { return }
            withAnimation(Motion.standard) {
                artwork = image
                accent = image.flatMap(Self.averageColor) ?? Color(white: 0.85)
            }
        }
    }

    private nonisolated static func parse(_ info: [AnyHashable: Any]?, player: Player) -> Update? {
        guard let info else { return nil }
        let title = info["Name"] as? String ?? ""
        let artist = info["Artist"] as? String ?? ""
        let state = info["Player State"] as? String ?? "Stopped"
        let duration: TimeInterval
        switch player {
        case .spotify: duration = (info["Duration"] as? Double ?? 0) / 1000
        case .music: duration = (info["Total Time"] as? Double ?? 0) / 1000
        }
        let position = info["Playback Position"] as? Double
        return Update(player: player, title: title, artist: artist, state: state, duration: duration, position: position)
    }

    private static func isRunning(_ player: Player) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: player.rawValue).isEmpty
    }

    @discardableResult
    private static func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        return NSAppleScript(source: source)?.executeAndReturnError(&error)
    }

    private static func averageColor(of image: NSImage) -> Color? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 4, bitsPerPixel: 32
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .medium
        image.draw(in: NSRect(x: 0, y: 0, width: 1, height: 1))
        NSGraphicsContext.restoreGraphicsState()
        guard let color = rep.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB) else { return nil }
        let boosted = NSColor(
            hue: color.hueComponent,
            saturation: min(1, color.saturationComponent * 1.4 + 0.15),
            brightness: max(0.75, color.brightnessComponent),
            alpha: 1
        )
        return Color(nsColor: boosted)
    }
}
