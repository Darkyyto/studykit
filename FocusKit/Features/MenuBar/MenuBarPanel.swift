import SwiftUI

struct MenuBarLabel: View {
    let engine: FocusEngine
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if engine.isActive {
                Label(engine.remaining(at: engine.now).clock, systemImage: symbol)
                    .labelStyle(.titleAndIcon)
                    .monospacedDigit()
            } else {
                Image(systemName: "waveform.path")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppDelegate.openMainWindow)) { _ in
            openWindow(id: "main")
            NSApp.activate()
        }
    }

    private var symbol: String {
        if engine.isPaused { return "pause.circle" }
        if engine.isResting { return "cup.and.saucer" }
        return engine.plan?.mode.symbol ?? "circle.circle"
    }
}

struct MenuBarPanel: View {
    @Environment(FocusEngine.self) private var engine
    @Environment(Library.self) private var library
    @Environment(VoiceRecorder.self) private var recorder
    @Environment(NoteEnhancer.self) private var enhancer
    @Environment(Updater.self) private var updater
    @AppStorage(Preference.persona) private var persona = Persona.personal
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Preference.focusMode) private var mode = FocusMode.flight

    private var tint: Color {
        if recorder.isActive, !engine.isActive { return Palette.record }
        if engine.isResting { return Palette.rest.deep }
        return (engine.plan?.mode ?? mode).palette.deep
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 12)
            Group {
                if engine.isActive, let plan = engine.plan {
                    session(plan)
                } else if recorder.isActive {
                    recording
                } else {
                    idle
                }
            }
            .padding(.horizontal, 10)
            .transition(.opacity)
            separator
                .padding(.top, 12)
            menu
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
        }
        .frame(width: 290)
        .animation(Motion.standard, value: engine.isActive)
        .animation(Motion.standard, value: engine.isPaused)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image("Logo")
                .resizable()
                .frame(width: 30, height: 30)
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
            VStack(alignment: .leading, spacing: 0) {
                Text("FocusKit")
                    .font(.system(size: 13, weight: .semibold))
                Text(updater.available.map { _ in "Update available" } ?? "Version \(version)")
                    .font(.system(size: 11))
                    .foregroundStyle(updater.available == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
            }
            Spacer()
            if engine.isActive || recorder.isActive {
                Text(engine.isPaused ? "Paused" : engine.isResting ? "Break" : recorder.isActive && !engine.isActive ? "Recording" : "Focusing")
                    .font(.rounded(10.5, weight: .bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(tint.opacity(0.14), in: .capsule)
            }
        }
    }

    private var idle: some View {
        let stats = JournalStats(sessions: library.sessions)
        let today = library.focusedTime(in: Calendar.current.dateInterval(of: .day, for: .now))
        return VStack(spacing: 12) {
            HStack(spacing: 0) {
                stat("Today", today.compactDuration)
                Divider().frame(height: 26)
                stat("This week", stats.thisWeek.compactDuration)
                Divider().frame(height: 26)
                stat("Streak", stats.streak == 1 ? "1 day" : "\(stats.streak) days")
            }
            .padding(.vertical, 10)
            .background(.primary.opacity(0.05), in: .rect(cornerRadius: 12, style: .continuous))
            HStack(spacing: 2) {
                ForEach(FocusMode.allCases) { item in
                    ModeLauncher(mode: item, isCurrent: item == mode, size: 36) { engine.startQuick(item) }
                }
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.numeric(14, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func session(_ plan: FocusPlan) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let progress = engine.isResting ? engine.segmentProgress(at: context.date) : engine.focusProgress(at: context.date)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(tint.opacity(0.18), lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: progress)
                        Image(systemName: engine.isResting ? "cup.and.saucer.fill" : plan.mode.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    .frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(engine.remaining(at: context.date).clock)
                            .font(.numeric(28, weight: .bold))
                            .contentTransition(.numericText(countsDown: true))
                            .animation(Motion.quick, value: engine.remaining(at: context.date).clock)
                        Text(plan.intention.isEmpty ? subtitle(plan) : plan.intention)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 6) {
                    control(engine.isPaused ? "play.fill" : "pause.fill", engine.isPaused ? "Resume" : "Pause", prominent: true) {
                        engine.togglePause()
                    }
                    control("forward.end.fill", engine.isResting ? "Skip break" : "Skip round") {
                        engine.skip()
                    }
                    if recorder.isActive {
                        control("stop.fill", "Stop recording", tint: Palette.record) {
                            recorder.stopNow(engine: engine, enhancer: enhancer, persona: persona)
                        }
                    }
                }
            }
            .padding(12)
            .background(tint.opacity(0.1), in: .rect(cornerRadius: 14, style: .continuous))
        }
    }

    private func subtitle(_ plan: FocusPlan) -> String {
        let round = plan.rounds > 1 ? " · round \((engine.segment?.round ?? 0) + 1) of \(plan.rounds)" : ""
        return plan.mode.title + round
    }

    private var recording: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.record)
                .symbolEffect(.variableColor.iterative, options: .repeating)
                .frame(width: 40, height: 40)
                .background(Palette.record.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text("Recording")
                    .font(.system(size: 13, weight: .semibold))
                Text("Saved and transcribed when you stop")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            control("stop.fill", "Stop recording", tint: Palette.record) {
                recorder.stopNow(engine: engine, enhancer: enhancer, persona: persona)
            }
        }
        .padding(12)
        .background(Palette.record.opacity(0.08), in: .rect(cornerRadius: 14, style: .continuous))
    }

    private var separator: some View {
        Rectangle()
            .fill(.primary.opacity(0.1))
            .frame(height: 1)
            .padding(.horizontal, 14)
    }

    private var menu: some View {
        VStack(spacing: 0) {
            MenuRow(title: "Open FocusKit", shortcut: nil) { openMain() }
            SettingsLink {
                MenuRowLabel(title: "Settings…", shortcut: "⌘,")
            }
            .buttonStyle(MenuRowStyle())
            .simultaneousGesture(TapGesture().onEnded { NSApp.activate() })
            MenuRow(title: "Check for Updates…", shortcut: nil) {
                openMain()
                Task {
                    await updater.check(userInitiated: true)
                    if let release = updater.available {
                        updater.presented = release
                    }
                }
            }
            separator
                .padding(.horizontal, -6)
                .padding(.vertical, 5)
            MenuRow(title: "Restart FocusKit", shortcut: nil) { restart() }
            MenuRow(title: "Quit FocusKit", shortcut: "⌘Q") { NSApp.terminate(nil) }
        }
    }

    private func openMain() {
        openWindow(id: "main")
        NSApp.activate()
    }

    private func restart() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; open \"$2\"", "sh", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundleURL.path(percentEncoded: false)]
        try? process.run()
        NSApp.terminate(nil)
    }

    private func control(_ symbol: String, _ help: String, prominent: Bool = false, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(help, systemImage: symbol)
                .labelStyle(.iconOnly)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(prominent || tint != nil ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .contentTransition(.symbolEffect(.replace))
                .frame(maxWidth: prominent ? .infinity : 44)
                .frame(height: 30)
                .background(
                    prominent ? AnyShapeStyle(self.tint) : tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary.opacity(0.08)),
                    in: .capsule
                )
                .contentShape(.capsule)
        }
        .buttonStyle(.pressable)
        .help(help)
    }
}

private struct MenuRowLabel: View {
    let title: String
    let shortcut: String?

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
            Spacer()
            if let shortcut {
                Text(shortcut)
                    .font(.system(size: 12))
                    .opacity(0.5)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .contentShape(.rect)
    }
}

private struct MenuRow: View {
    let title: String
    let shortcut: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MenuRowLabel(title: title, shortcut: shortcut)
        }
        .buttonStyle(MenuRowStyle())
    }
}

private struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverRow(configuration: configuration)
    }

    private struct HoverRow: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(isHovering ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(configuration.isPressed ? 0.8 : (isHovering ? 1 : 0)))
                }
                .onHover { isHovering = $0 }
        }
    }
}
