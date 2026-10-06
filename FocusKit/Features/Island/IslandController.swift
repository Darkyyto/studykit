import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class IslandController {
    enum Presence: String, CaseIterable, Identifiable {
        case activity
        case always
        case off

        var id: String { rawValue }

        var title: String {
            switch self {
            case .activity: "When something is happening"
            case .always: "Always"
            case .off: "Off"
            }
        }
    }

    enum Shape: Equatable {
        case hidden
        case compact
        case peek
        case expanded
    }

    enum Section: Hashable {
        case session
        case music
        case launcher

        var height: CGFloat {
            switch self {
            case .session: 252
            case .music: 132
            case .launcher: 196
            }
        }
    }

    struct Announcement: Equatable {
        let text: String
        let symbol: String
        let tint: Color
    }

    private(set) var shape: Shape = .hidden
    private(set) var announcement: Announcement?

    @ObservationIgnored let engine: FocusEngine
    @ObservationIgnored let recorder: VoiceRecorder
    @ObservationIgnored let nowPlaying: NowPlaying
    @ObservationIgnored private var panel: NotchPanel?
    @ObservationIgnored private var mouseMonitor: Any?
    @ObservationIgnored private var exitWatcher: Timer?
    @ObservationIgnored private var outsideSince: Date?
    @ObservationIgnored private var hoverIntent: Task<Void, Never>?
    @ObservationIgnored private var announcementTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    static let canvas = CGSize(width: 260, height: 520)
    static let expandedWidth: CGFloat = 216
    static let peekSize = CGSize(width: 200, height: 64)
    static let compactSize = CGSize(width: 32, height: 92)
    static let idleSize = CGSize(width: 5, height: 48)
    static let fillet: CGFloat = 10

    init(engine: FocusEngine, recorder: VoiceRecorder, library: Library, nowPlaying: NowPlaying, soundscape: Soundscape) {
        self.engine = engine
        self.recorder = recorder
        self.nowPlaying = nowPlaying

        let content = IslandView(controller: self)
            .environment(engine)
            .environment(recorder)
            .environment(library)
            .environment(nowPlaying)
            .environment(soundscape)
        panel = NotchPanel(content: content, size: Self.canvas)

        let center = NotificationCenter.default
        let refreshers: [Notification.Name] = [
            NSApplication.didBecomeActiveNotification,
            NSApplication.didResignActiveNotification,
            NSApplication.didHideNotification,
            NSApplication.didUnhideNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            UserDefaults.didChangeNotification,
        ]
        observers = refreshers.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        observers.append(center.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.install() }
        })
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        })
    }

    var isBusy: Bool {
        engine.isActive || engine.phase.isComplete || recorder.isActive
    }

    var hasActivity: Bool {
        isBusy || nowPlaying.isPlaying
    }

    var sections: [Section] {
        var sections: [Section] = []
        if isBusy { sections.append(.session) }
        if nowPlaying.hasTrack { sections.append(.music) }
        return sections.isEmpty ? [.launcher] : sections
    }

    var size: CGSize {
        switch shape {
        case .hidden: CGSize(width: 0, height: Self.idleSize.height)
        case .compact: hasActivity ? Self.compactSize : Self.idleSize
        case .peek: Self.peekSize
        case .expanded:
            CGSize(
                width: Self.expandedWidth,
                height: 28 + sections.reduce(0) { $0 + $1.height } + CGFloat(max(0, sections.count - 1)) * 17
            )
        }
    }

    private var presence: Presence {
        Presence(rawValue: UserDefaults.standard.string(forKey: Preference.sideNotch) ?? "") ?? .activity
    }

    private var appIsInFront: Bool {
        NSApp.isActive && NSApp.windows.contains { !($0 is NSPanel) && $0.isVisible && !$0.isMiniaturized }
    }

    private var restingShape: Shape {
        if presence == .off || appIsInFront { return .hidden }
        switch presence {
        case .always: return .compact
        default: return hasActivity ? .compact : .hidden
        }
    }

    func refresh() {
        guard shape == .hidden || shape == .compact else { return }
        transition(to: restingShape)
    }

    func announce(_ text: String, symbol: String, tint: Color) {
        guard presence != .off, !appIsInFront else { return }
        announcementTask?.cancel()
        announcement = Announcement(text: text, symbol: symbol, tint: tint)
        if shape != .expanded { transition(to: .peek) }
        announcementTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.8))
            guard !Task.isCancelled, let self else { return }
            if self.shape == .peek { self.transition(to: self.restingShape) }
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { self.announcement = nil }
        }
    }

    func openApp() {
        NSApp.unhide(nil)
        for window in NSApp.windows where !(window is NSPanel) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate()
        transition(to: .hidden)
    }

    private func install() {
        guard let panel else { return }
        reposition()
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func reposition() {
        guard let panel, let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        panel.setFrame(CGRect(
            x: screen.frame.maxX - Self.canvas.width,
            y: screen.visibleFrame.midY - Self.canvas.height / 2 + screen.visibleFrame.height * 0.12,
            width: Self.canvas.width,
            height: Self.canvas.height
        ), display: true)
    }

    private func pointerMoved() {
        guard shape == .compact || shape == .peek, let panel else {
            hoverIntent?.cancel()
            hoverIntent = nil
            return
        }
        let height = max(size.height, Self.compactSize.height)
        let band = CGRect(x: panel.frame.maxX - 8, y: panel.frame.midY - height / 2 - 12, width: 8, height: height + 24)
        guard band.contains(NSEvent.mouseLocation) else {
            hoverIntent?.cancel()
            hoverIntent = nil
            return
        }
        guard hoverIntent == nil else { return }
        hoverIntent = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self else { return }
            self.hoverIntent = nil
            if self.shape == .compact || self.shape == .peek {
                self.nowPlaying.refreshIfNeeded()
                self.transition(to: .expanded)
            }
        }
    }

    private func transition(to target: Shape) {
        guard target != shape else { return }
        let opening = target == .expanded || target == .peek
        withAnimation(opening ? .spring(response: 0.42, dampingFraction: 0.8) : .spring(response: 0.34, dampingFraction: 1)) {
            shape = target
        }
        panel?.ignoresMouseEvents = target != .expanded
        exitWatcher?.invalidate()
        exitWatcher = nil
        outsideSince = nil
        guard target == .expanded else { return }
        exitWatcher = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkExit() }
        }
    }

    private func checkExit() {
        guard let panel else { return }
        let size = size
        let area = CGRect(
            x: panel.frame.maxX - size.width - 14,
            y: panel.frame.midY - size.height / 2 - 14,
            width: size.width + 14,
            height: size.height + 28
        )
        if area.contains(NSEvent.mouseLocation) {
            outsideSince = nil
            return
        }
        let since = outsideSince ?? .now
        outsideSince = since
        if Date.now.timeIntervalSince(since) > 0.28 {
            transition(to: restingShape)
        }
    }
}

private final class NotchPanel: NSPanel {
    init(content: some View, size: CGSize) {
        super.init(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.isOpaque = false
        contentView = hosting
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
