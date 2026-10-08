import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class LockScreen {
    enum Style: String, CaseIterable, Identifiable {
        case glass
        case clear

        var id: String { rawValue }
        var title: String { self == .glass ? "Glass" : "Clear" }
    }

    static let enabledKey = "lockScreenWidgets"
    static let greetingKey = "lockScreenGreeting"
    static let batteryKey = "lockScreenBattery"
    static let audioKey = "lockScreenAudio"
    static let sessionKey = "lockScreenSession"
    static let calendarKey = "lockScreenCalendar"
    static let musicKey = "lockScreenMusic"
    static let styleKey = "lockScreenStyle"
    static let previewNotification = Notification.Name("FocusKitLockScreenPreview")

    static func isOn(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    private(set) var isShowing = false

    @ObservationIgnored private let bridge = SkyLightBridge()
    @ObservationIgnored private var window: NSPanel?
    @ObservationIgnored private var space: UInt64 = 0
    @ObservationIgnored private var watchdog: Timer?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    var isAvailable: Bool {
        bridge != nil
    }

    nonisolated static var isSupported: Bool {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else { return false }
        let names: [String] = ["SLSMainConnectionID", "SLSSpaceCreate", "SLSSpaceSetAbsoluteLevel", "SLSShowSpaces", "SLSSpaceAddWindowsAndRemoveFromSpaces"]
        return names.allSatisfy { dlsym(handle, $0) != nil }
    }

    func start(content: some View) {
        guard let bridge, window == nil, let screen = NSScreen.screens.first else { return }
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let hosting = NSHostingView(rootView: content.environment(\.colorScheme, .dark).environment(\.appearsActive, true))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.alphaValue = 0
        window = panel
        space = bridge.makeSpace()

        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.show() } }
        })
        observers.append(distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.hide() } }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.hideUnlessLocked() } }
        })
        observers.append(NotificationCenter.default.addObserver(forName: Self.previewNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.preview() } }
        })
    }

    private func show(force: Bool = false) {
        guard let window, let bridge, force || Self.isOn(Self.enabledKey) else { return }
        if let screen = NSScreen.screens.first, window.frame != screen.frame {
            window.setFrame(screen.frame, display: true)
        }
        window.orderFrontRegardless()
        bridge.add(window, to: space)
        isShowing = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.45
            window.animator().alphaValue = 1
        }
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideUnlessLocked() }
        }
    }

    private func hide() {
        previewTask?.cancel()
        previewTask = nil
        watchdog?.invalidate()
        watchdog = nil
        isShowing = false
        window?.alphaValue = 0
        window?.orderOut(nil)
    }

    private func hideUnlessLocked() {
        guard previewTask == nil, !Self.isLocked else { return }
        hide()
    }

    func preview() {
        guard isAvailable else { return }
        previewTask?.cancel()
        show(force: true)
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, let self else { return }
            self.previewTask = nil
            if !Self.isLocked { self.hide() }
        }
    }

    static var isLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}

@MainActor
private final class SkyLightBridge {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, CFDictionary?) -> UInt64
    private typealias SpaceSetLevel = @convention(c) (Int32, UInt64, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindows = @convention(c) (Int32, UInt64, CFArray, Int32) -> Int32

    private let connection: Int32
    private let spaceCreate: SpaceCreate
    private let setLevel: SpaceSetLevel
    private let showSpaces: ShowSpaces
    private let addWindows: AddWindows

    init?() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let main = dlsym(handle, "SLSMainConnectionID"),
              let create = dlsym(handle, "SLSSpaceCreate"),
              let level = dlsym(handle, "SLSSpaceSetAbsoluteLevel"),
              let show = dlsym(handle, "SLSShowSpaces"),
              let add = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces") else { return nil }
        connection = unsafeBitCast(main, to: MainConnection.self)()
        spaceCreate = unsafeBitCast(create, to: SpaceCreate.self)
        setLevel = unsafeBitCast(level, to: SpaceSetLevel.self)
        showSpaces = unsafeBitCast(show, to: ShowSpaces.self)
        addWindows = unsafeBitCast(add, to: AddWindows.self)
    }

    func makeSpace() -> UInt64 {
        let space = spaceCreate(connection, 1, nil)
        _ = setLevel(connection, space, 400)
        _ = showSpaces(connection, [NSNumber(value: space)] as CFArray)
        return space
    }

    func add(_ window: NSWindow, to space: UInt64) {
        guard space != 0, window.windowNumber > 0 else { return }
        _ = addWindows(connection, space, [NSNumber(value: window.windowNumber)] as CFArray, 7)
    }
}
