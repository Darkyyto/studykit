import SwiftUI

@main
struct FocusKitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var library: Library
    @State private var engine: FocusEngine
    @State private var recorder: VoiceRecorder
    @State private var enhancer: NoteEnhancer
    @State private var island: IslandController
    @State private var nowPlaying: NowPlaying
    @State private var soundscape: Soundscape
    @State private var updater = Updater()
    @AppStorage(Preference.showsMenuBarExtra) private var showsMenuBarExtra = true
    @AppStorage(Preference.mainWindowOpen) private var mainWindowOpen = true

    init() {
        SandboxMigration.importDefaults()
        let library = Library()
        let engine = FocusEngine(library: library)
        let recorder = VoiceRecorder(library: library)
        let nowPlaying = NowPlaying()
        let soundscape = Soundscape()
        _library = State(initialValue: library)
        let enhancer = NoteEnhancer(library: library)
        _enhancer = State(initialValue: enhancer)
        _engine = State(initialValue: engine)
        _recorder = State(initialValue: recorder)
        _nowPlaying = State(initialValue: nowPlaying)
        _soundscape = State(initialValue: soundscape)
        _island = State(initialValue: IslandController(engine: engine, recorder: recorder, library: library, nowPlaying: nowPlaying, soundscape: soundscape, enhancer: enhancer))
    }

    var body: some Scene {
        Window("FocusKit", id: "main") {
            RootView()
                .environment(library)
                .environment(engine)
                .environment(recorder)
                .environment(enhancer)
                .environment(nowPlaying)
                .environment(soundscape)
                .environment(updater)
                .task {
                    Backup.onLaunch()
                    updater.checkOnLaunch()
                    enhancer.resumePending(for: Persona(rawValue: UserDefaults.standard.string(forKey: Preference.persona) ?? "") ?? .personal)
                    delegate.beforeTerminate = { [engine, recorder] in
                        if engine.isActive {
                            engine.stop()
                        }
                        guard recorder.isActive else { return }
                        if let recording = await recorder.stop() {
                            engine.attachRecording(recording.id)
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    library.flush()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1120, height: 760)
        .commands { AppCommands(engine: engine) }

        MenuBarExtra(isInserted: Binding(get: { showsMenuBarExtra || !mainWindowOpen }, set: { showsMenuBarExtra = $0 })) {
            MenuBarPanel()
                .environment(library)
                .environment(engine)
                .environment(recorder)
                .environment(enhancer)
                .environment(updater)
        } label: {
            MenuBarLabel(engine: engine)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(soundscape)
                .environment(updater)
                .environment(island.systemHUD)
        }
        .windowResizability(.contentSize)
    }
}

enum Preference {
    static let persona = "persona"
    static let name = "name"
    static let hasOnboarded = "hasOnboarded"
    static let isReplayingOnboarding = "isReplayingOnboarding"
    static let sideNotch = "sideNotch"
    static let soundscape = "soundscape"
    static let soundscapeVolume = "soundscapeVolume"
    static let focusMode = "focusMode"
    static let homeAirport = "homeAirport"
    static let transcriptionLocale = "transcriptionLocale"
    static let showsMenuBarExtra = "showsMenuBarExtra"
    static let keepsRunning = "keepsRunningInBackground"
    static let mainWindowOpen = "mainWindowOpen"

    static func minutes(for mode: FocusMode) -> String {
        "minutes.\(mode.rawValue)"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let openDocuments = Notification.Name("FocusKitOpenDocuments")
    static let openMainWindow = Notification.Name("FocusKitOpenMainWindow")

    private static var keepsRunning: Bool {
        UserDefaults.standard.object(forKey: Preference.keepsRunning) as? Bool ?? true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: Preference.mainWindowOpen)
        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            let isMain = (note.object as? NSWindow)?.identifier?.rawValue.hasPrefix("main") == true
            MainActor.assumeIsolated { if isMain { AppDelegate.mainWindowClosed() } }
        }
        center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            let isMain = (note.object as? NSWindow)?.identifier?.rawValue.hasPrefix("main") == true
            MainActor.assumeIsolated {
                guard isMain else { return }
                UserDefaults.standard.set(true, forKey: Preference.mainWindowOpen)
                if NSApp.activationPolicy() != .regular {
                    NSApp.setActivationPolicy(.regular)
                }
            }
        }
    }

    private static func mainWindowClosed() {
        UserDefaults.standard.set(false, forKey: Preference.mainWindowOpen)
        guard keepsRunning else { return }
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !Self.keepsRunning
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NotificationCenter.default.post(name: Self.openMainWindow, object: nil)
        }
        return true
    }

    var beforeTerminate: (@MainActor () async -> Void)?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let beforeTerminate else { return .terminateNow }
        Task { @MainActor in
            await beforeTerminate()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        NotificationCenter.default.post(name: Self.openDocuments, object: nil, userInfo: ["urls": urls])
    }
}
