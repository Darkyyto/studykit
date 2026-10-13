import AppKit

@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private static var shared: StatusMenu?

    private let updater: Updater
    private let item: NSStatusItem
    private let menu = NSMenu()

    static func install(updater: Updater) {
        guard shared == nil else { return }
        shared = StatusMenu(updater: updater)
    }

    private init(updater: Updater) {
        self.updater = updater
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        let image = NSImage(systemSymbolName: "waveform.path", accessibilityDescription: "FocusKit")
        image?.isTemplate = true
        item.button?.image = image
        item.autosaveName = "FocusKitStatusItem"
        build()
        item.menu = menu
        syncVisibility()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncVisibility() }
        }
    }

    private func syncVisibility() {
        let visible = UserDefaults.standard.object(forKey: Preference.showsMenuBarExtra) as? Bool ?? true
        if item.isVisible != visible {
            item.isVisible = visible
        }
    }

    private func build() {
        menu.autoenablesItems = false
        menu.delegate = self
        let title = NSMenuItem(title: "FocusKit \(Updater.currentVersion)", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        menu.addItem(entry("Open FocusKit", #selector(openMain)))
        menu.addItem(entry("Settings…", #selector(openSettings), key: ","))
        menu.addItem(entry("Check for Updates…", #selector(checkForUpdates)))
        menu.addItem(.separator())
        menu.addItem(entry("Quit FocusKit", #selector(quit), key: "q"))
    }

    private func entry(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        return entry
    }

    @objc private func openMain() {
        NotificationCenter.default.post(name: AppDelegate.openMainWindow, object: nil)
    }

    @objc private func openSettings() {
        NotificationCenter.default.post(name: AppDelegate.openSettingsWindow, object: nil)
    }

    @objc private func checkForUpdates() {
        openMain()
        Task {
            await updater.check(userInitiated: true)
            if let release = updater.available {
                updater.presented = release
            }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
