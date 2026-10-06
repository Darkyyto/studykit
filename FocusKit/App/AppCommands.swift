import SwiftUI

struct AppCommands: Commands {
    let engine: FocusEngine
    @FocusedValue(\.section) private var section
    @AppStorage(Preference.persona) private var persona = Persona.personal

    var body: some Commands {
        CommandMenu("Focus") {
            Button(engine.isPaused ? "Resume" : "Pause") {
                engine.togglePause()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(!engine.isActive)

            Button(engine.isResting ? "Skip Break" : "Skip Round") {
                engine.skip()
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(!engine.isActive)

            Divider()

            Button("End Session") {
                engine.stop()
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(!engine.isActive)
        }

        CommandGroup(after: .sidebar) {
            ForEach(AppSection.allCases) { item in
                Button(item.title(for: persona)) {
                    section?.wrappedValue = item
                }
                .keyboardShortcut(item.shortcut, modifiers: .command)
            }
            Divider()
            Picker("Use FocusKit As", selection: $persona) {
                ForEach(Persona.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            Divider()
        }
    }
}

extension FocusedValues {
    @Entry var section: Binding<AppSection>?
}
