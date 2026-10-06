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

    private(set) var player: Player?
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
    @ObservationIgnored private var hasQueried = false

    init() {
        let center = DistributedNotificationCenter.default()
        observers = [
            center.addObserver(forName: .init("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { [weak self] note in
                let update = Self.parse(note.userInfo, player: .spotify)
                MainActor.assumeIsolated { self?.apply(update) }
            },
            center.addObserver(forName: .init("com.apple.Music.playerInfo"), object: nil, queue: .main) { [weak self] note in
                let update = Self.parse(note.userInfo, player: .music)
                MainActor.assumeIsolated { self?.apply(update) }
            },
        ]
    }

    var hasTrack: Bool {
        player != nil && !title.isEmpty
    }

    func elapsed(at date: Date) -> TimeInterval {
        let value = position + (isPlaying ? date.timeIntervalSince(positionDate) : 0)
        return duration > 0 ? min(duration, value) : value
    }

    func refreshIfNeeded() {
        guard !hasQueried else { return }
        hasQueried = true
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
            apply(Update(
                player: candidate,
                title: parts[0],
                artist: parts[1],
                state: parts[2].lowercased().contains("play") ? "Playing" : "Paused",
                duration: candidate == .spotify ? rawDuration / 1000 : rawDuration,
                position: Double(parts[4].replacingOccurrences(of: ",", with: "."))
            ))
            return
        }
    }

    func togglePlayback() {
        command("playpause")
        isPlaying.toggle()
        position = elapsed(at: .now)
        positionDate = .now
    }

    func next() {
        command("next track")
    }

    func previous() {
        command("previous track")
    }

    func open() {
        guard let player, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.rawValue) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func command(_ verb: String) {
        guard let player, Self.isRunning(player) else { return }
        Self.run("tell application \"\(player.scriptName)\" to \(verb)")
    }

    private func apply(_ update: Update?) {
        guard let update else { return }
        if update.state == "Stopped" || update.title.isEmpty {
            if player == update.player {
                player = nil
                title = ""
                isPlaying = false
                artwork = nil
            }
            return
        }
        player = update.player
        title = update.title
        artist = update.artist
        isPlaying = update.state == "Playing"
        duration = update.duration
        if let value = update.position {
            position = value
        } else if update.player == .music, let value = Self.run("tell application \"Music\" to player position")?.doubleValue {
            position = value
        }
        positionDate = .now

        let key = "\(update.player.rawValue)|\(update.title)|\(update.artist)"
        guard key != trackKey else { return }
        trackKey = key
        loadArtwork(for: update.player, key: key)
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
