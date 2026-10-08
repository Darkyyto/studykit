import SwiftUI

struct MenuBarLabel: View {
    var body: some View {
        Image(systemName: "waveform.path")
    }
}

struct MenuBarMenu: View {
    @Environment(Updater.self) private var updater
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("FocusKit \(Updater.currentVersion)")
        Divider()
        Button("Open FocusKit") {
            openMain()
        }
        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",")
        Button("Check for Updates…") {
            openMain()
            Task {
                await updater.check(userInitiated: true)
                if let release = updater.available {
                    updater.presented = release
                }
            }
        }
        Divider()
        Button("Quit FocusKit") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func openMain() {
        openWindow(id: "main")
        NSApp.activate()
    }
}
