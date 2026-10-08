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
        case hud
        case expanded
    }

    enum Tab: Hashable {
        case home
        case music
        case calendar
        case tray
        case clipboard
    }

    struct Announcement: Hashable {
        let title: String
        let detail: String
        let symbol: String
        let tint: Color
    }

    private(set) var shape: Shape = .hidden
    private(set) var isPreviewing = false
    private(set) var announcement: Announcement?
    private(set) var notch = CGSize(width: 0, height: 32)
    var tab = Tab.home

    @ObservationIgnored let engine: FocusEngine
    @ObservationIgnored let recorder: VoiceRecorder
    @ObservationIgnored let nowPlaying: NowPlaying
    @ObservationIgnored private var panel: NotchPanel?
    @ObservationIgnored private var pointerWatcher: Timer?
    @ObservationIgnored private var exitWatcher: Timer?
    @ObservationIgnored private var outsideSince: Date?
    @ObservationIgnored private var hoverIntent: Task<Void, Never>?
    @ObservationIgnored private var announcementTask: Task<Void, Never>?
    @ObservationIgnored private var hudTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var refreshPending = false
    @ObservationIgnored private var isInstalled = false

    static let offsetKey = "notchOffset"
    static let heightKey = "notchHeightAdjustment"
    static let previewNotification = Notification.Name("FocusKitNotchPreview")
    static let hapticsKey = "notchHaptics"

    static func tap() {
        guard UserDefaults.standard.object(forKey: hapticsKey) as? Bool ?? true else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
    @ObservationIgnored private var restingDragCount = NSPasteboard(name: .drag).changeCount
    @ObservationIgnored private var wasPressed = false

    static let canvas = CGSize(width: 760, height: 340)
    static let expandedSize = CGSize(width: 540, height: 178)
    static let wing: CGFloat = 54
    static let wideWing: CGFloat = 80

    var wing: CGFloat {
        showsHours ? Self.wideWing : Self.wing
    }

    private var showsHours: Bool {
        if recorder.isActive, case .recording(let since) = recorder.state {
            return Date.now.timeIntervalSince(since) >= 3600
        }
        return engine.isActive && engine.remaining(at: engine.now) > 3599
    }
    var fillet: CGFloat {
        switch shape {
        case .hidden: max(4, (notch.height * 0.2).rounded())
        case .compact, .hud, .peek: max(6, (notch.height * 0.32).rounded())
        case .expanded: 16
        }
    }

    let calendar = CalendarStore()
    let tray = FileTray()
    let devices = DeviceWatcher()
    let lockScreen = LockScreen()
    let clipboard = ClipboardHistory()
    @ObservationIgnored private let library: Library
    let systemHUD = SystemHUD()
    static let hudWing: CGFloat = 136
    static let peekWing: CGFloat = 64
    static let peekLine: CGFloat = 30

    init(engine: FocusEngine, recorder: VoiceRecorder, library: Library, nowPlaying: NowPlaying, soundscape: Soundscape, enhancer: NoteEnhancer) {
        self.engine = engine
        self.recorder = recorder
        self.nowPlaying = nowPlaying
        self.library = library

        let content = IslandView(controller: self, calendar: calendar, tray: tray, devices: devices, clipboard: clipboard, systemHUD: systemHUD)
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
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            }
        }
        observers.append(center.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.install() }
        })
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        })
        observers.append(DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                MainActor.assumeIsolated { self?.unlocked() }
            }
        })
        observers.append(center.addObserver(forName: Self.previewNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.preview() }
            }
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
        let base = CGSize(width: hasHardwareNotch ? notch.width : 180, height: notch.height)
        switch shape {
        case .hidden: return base
        case .compact: return hasActivity ? CGSize(width: base.width + wing * 2, height: base.height) : base
        case .peek: return CGSize(width: max(base.width, 160) + Self.peekWing * 2, height: base.height + Self.peekLine)
        case .hud: return CGSize(width: max(base.width, 160) + Self.hudWing * 2, height: base.height)
        case .expanded: return CGSize(width: Self.expandedSize.width, height: base.height + Self.expandedSize.height + (tab == .calendar ? 24 : 0))
        }
    }

    var bottomRadius: CGFloat {
        switch shape {
        case .hidden, .compact: (notch.height * 0.3).rounded()
        case .peek: 18
        case .hud: (notch.height * 0.4).rounded()
        case .expanded: 30
        }
    }

    var isVisible: Bool {
        switch shape {
        case .hidden: false
        case .compact: hasActivity || isPreviewing
        case .peek, .hud, .expanded: true
        }
    }

    private var presence: Presence {
        Presence(rawValue: UserDefaults.standard.string(forKey: Preference.sideNotch) ?? "") ?? .activity
    }

    private var appIsInFront: Bool {
        NSApp.isActive && NSApp.windows.contains { !($0 is NSPanel) && $0.isVisible && !$0.isMiniaturized }
    }

    private var restingShape: Shape {
        if isPreviewing { return .compact }
        if presence == .off || appIsInFront { return .hidden }
        switch presence {
        case .always: return .compact
        default: return hasActivity ? .compact : .hidden
        }
    }

    private func scheduleRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshPending = false
                self.refresh()
            }
        }
    }

    func refresh() {
        guard isInstalled else { return }
        reposition()
        clipboard.syncWithPreference()
        guard shape == .hidden || shape == .compact else { return }
        transition(to: restingShape)
    }

    func showSystemHUD() {
        guard presence != .off, shape != .expanded else { return }
        hudTask?.cancel()
        if shape != .hud {
            transition(to: .hud)
        }
        hudTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled, let self, self.shape == .hud else { return }
            self.transition(to: self.restingShape)
        }
    }

    func announce(_ title: String, detail: String, symbol: String, tint: Color, fromSystem: Bool = false) {
        guard presence != .off, fromSystem || !appIsInFront, shape != .hud else { return }
        announcementTask?.cancel()
        announcement = Announcement(title: title, detail: detail, symbol: symbol, tint: tint)
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
        isInstalled = true
        systemHUD.start()
        devices.start()
        clipboard.start()
        lockScreen.start(content: LockScreenView(lockScreen: lockScreen, calendar: calendar)
            .environment(engine)
            .environment(library)
            .environment(nowPlaying))
        reposition()
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        pointerWatcher = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }
        pointerWatcher?.tolerance = 0.02
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

    private func unlocked() {
        guard isInstalled, LockScreen.isOn(LockScreen.notchKey) else { return }
        announce("Unlocked", detail: "", symbol: "lock.open.fill", tint: Color(hex: 0x34C759), fromSystem: true)
    }

    func preview() {
        guard isInstalled else { return }
        previewTask?.cancel()
        isPreviewing = true
        reposition()
        if shape == .hidden { transition(to: .compact) }
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, let self else { return }
            self.isPreviewing = false
            self.refresh()
        }
    }

    private func reposition() {
        guard let panel, let screen else { return }
        let defaults = UserDefaults.standard
        let offset = defaults.double(forKey: Self.offsetKey)
        let adjustment = defaults.double(forKey: Self.heightKey)
        let scale = max(1, screen.backingScaleFactor)
        var center = screen.frame.midX
        let measured: CGSize
        if screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let shift = abs(left.minX - screen.frame.minX) < 1 ? 0 : screen.frame.minX
            center = (left.maxX + right.minX) / 2 + shift
            measured = CGSize(width: max(0, right.minX - left.maxX), height: max(16, screen.safeAreaInsets.top + adjustment))
        } else {
            measured = CGSize(width: 0, height: max(24, screen.frame.maxY - screen.visibleFrame.maxY))
        }
        if measured != notch {
            notch = measured
        }
        let x = ((center + offset - Self.canvas.width / 2) * scale).rounded() / scale
        let frame = CGRect(x: x, y: screen.frame.maxY - Self.canvas.height, width: Self.canvas.width, height: Self.canvas.height)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
    }

    private func isDraggingFiles() -> Bool {
        let pressed = NSEvent.pressedMouseButtons & 1 != 0
        defer { wasPressed = pressed }
        guard pressed else {
            if wasPressed { restingDragCount = NSPasteboard(name: .drag).changeCount }
            return false
        }
        let board = NSPasteboard(name: .drag)
        return board.changeCount != restingDragCount
            && board.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    private func pointerMoved() {
        let draggingFiles = isDraggingFiles()
        guard presence != .off, shape != .expanded, let screen else {
            hoverIntent?.cancel()
            hoverIntent = nil
            return
        }
        let dropping = draggingFiles && FileTray.isEnabled
        let width = dropping ? Self.expandedSize.width : max(size.width, max(notch.width, 180)) + 40
        let depth = dropping ? notch.height + 90 : notch.height + 6
        let midX = panel?.frame.midX ?? screen.frame.midX
        let band = CGRect(x: midX - width / 2, y: screen.frame.maxY - depth, width: width, height: depth)
        guard band.contains(NSEvent.mouseLocation) else {
            hoverIntent?.cancel()
            hoverIntent = nil
            return
        }
        guard hoverIntent == nil else { return }
        hoverIntent = Task { [weak self] in
            if !dropping {
                try? await Task.sleep(for: .milliseconds(140))
            }
            guard !Task.isCancelled, let self else { return }
            self.hoverIntent = nil
            if self.shape != .expanded {
                if dropping {
                    self.tab = .tray
                }
                self.nowPlaying.refreshIfNeeded()
                self.transition(to: .expanded)
                Self.tap()
            }
        }
    }

    private func transition(to target: Shape) {
        guard target != shape else { return }
        let opening = target == .expanded || target == .peek || target == .hud
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
        if area.contains(NSEvent.mouseLocation) || NSEvent.pressedMouseButtons & 1 != 0 {
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
