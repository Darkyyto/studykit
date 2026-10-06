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

    enum Tab: Hashable {
        case home
        case calendar
    }

    struct Announcement: Equatable {
        let text: String
        let symbol: String
        let tint: Color
    }

    private(set) var shape: Shape = .hidden
    private(set) var announcement: Announcement?
    private(set) var notch = CGSize(width: 0, height: 32)
    var tab = Tab.home

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

    static let canvas = CGSize(width: 760, height: 340)
    static let expandedSize = CGSize(width: 640, height: 252)
    static let wing: CGFloat = 70
    static let fillet: CGFloat = 8

    let calendar = CalendarStore()

    init(engine: FocusEngine, recorder: VoiceRecorder, library: Library, nowPlaying: NowPlaying, soundscape: Soundscape, enhancer: NoteEnhancer) {
        self.engine = engine
        self.recorder = recorder
        self.nowPlaying = nowPlaying

        let content = IslandView(controller: self, calendar: calendar)
            .environment(engine)
            .environment(recorder)
            .environment(library)
            .environment(nowPlaying)
            .environment(soundscape)
            .environment(enhancer)
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

    var hasHardwareNotch: Bool {
        notch.width > 0
    }

    var size: CGSize {
        let base = CGSize(width: max(notch.width, 180), height: notch.height)
        switch shape {
        case .hidden: return base
        case .compact: return CGSize(width: base.width + Self.wing * 2, height: base.height)
        case .peek: return CGSize(width: base.width + 200, height: base.height + 40)
        case .expanded: return CGSize(width: Self.expandedSize.width, height: base.height + Self.expandedSize.height)
        }
    }

    var bottomRadius: CGFloat {
        switch shape {
        case .hidden, .compact: min(12, notch.height / 2)
        case .peek: 20
        case .expanded: 30
        }
    }

    var isVisible: Bool {
        shape != .hidden || hasHardwareNotch
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

    private var screen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    private func reposition() {
        guard let panel, let screen else { return }
        if screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notch = CGSize(width: screen.frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
        } else {
            notch = CGSize(width: 0, height: max(24, screen.frame.maxY - screen.visibleFrame.maxY))
        }
        panel.setFrame(CGRect(
            x: screen.frame.midX - Self.canvas.width / 2,
            y: screen.frame.maxY - Self.canvas.height,
            width: Self.canvas.width,
            height: Self.canvas.height
        ), display: true)
    }

    private func pointerMoved() {
        guard presence != .off, shape != .expanded, let screen else {
            hoverIntent?.cancel()
            hoverIntent = nil
            return
        }
        let width = max(size.width, max(notch.width, 180))
        let band = CGRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - notch.height - 4, width: width, height: notch.height + 4)
        guard band.contains(NSEvent.mouseLocation) else {
            hoverIntent?.cancel()
            hoverIntent = nil
            return
        }
        guard hoverIntent == nil else { return }
        hoverIntent = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled, let self else { return }
            self.hoverIntent = nil
            if self.shape != .expanded {
                self.nowPlaying.refreshIfNeeded()
                self.transition(to: .expanded)
            }
        }
    }

    private func transition(to target: Shape) {
        guard target != shape else { return }
        let opening = target == .expanded || target == .peek
        withAnimation(opening ? .spring(response: 0.44, dampingFraction: 0.78) : .spring(response: 0.36, dampingFraction: 0.95)) {
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
            x: panel.frame.midX - size.width / 2 - 16,
            y: panel.frame.maxY - size.height - 16,
            width: size.width + 32,
            height: size.height + 16
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
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
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
