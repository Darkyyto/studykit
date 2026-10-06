import SwiftUI

struct MenuBarLabel: View {
    let engine: FocusEngine

    var body: some View {
        if engine.isActive {
            Label(engine.remaining(at: engine.now).clock, systemImage: symbol)
                .labelStyle(.titleAndIcon)
                .monospacedDigit()
        } else {
            Image(systemName: "waveform.path")
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
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if engine.isActive, let plan = engine.plan {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(spacing: 14) {
                        ProgressRing(
                            progress: engine.isResting ? engine.segmentProgress(at: context.date) : engine.focusProgress(at: context.date),
                            tint: engine.isResting ? Palette.rest.deep : plan.mode.palette.deep,
                            lineWidth: 5
                        )
                        .frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(engine.isResting ? "Break" : plan.mode.title)
                                .font(.rounded(12, weight: .semibold))
                                .foregroundStyle(Palette.inkSecondary)
                            Text(engine.remaining(at: context.date).clock)
                                .font(.numeric(30, weight: .bold))
                                .foregroundStyle(Palette.ink)
                                .contentTransition(.numericText(countsDown: true))
                        }
                    }
                }
                if !plan.intention.isEmpty {
                    Text(plan.intention)
                        .font(.rounded(13, weight: .medium))
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    Button(engine.isPaused ? "Resume" : "Pause") { engine.togglePause() }
                        .buttonStyle(.glass)
                    Spacer()
                    openButton
                }
                .buttonBorderShape(.capsule)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("This week")
                        .font(.rounded(12, weight: .semibold))
                        .foregroundStyle(Palette.inkSecondary)
                    Text(library.focusedTime(in: .currentWeek).compactDuration)
                        .font(.numeric(28, weight: .bold))
                        .foregroundStyle(Palette.ink)
                }
                HStack {
                    Spacer()
                    openButton
                }
                .buttonBorderShape(.capsule)
            }
        }
        .padding(18)
        .frame(width: 280)
        .preferredColorScheme(.light)
    }

    private var openButton: some View {
        Button("Open FocusKit") {
            openWindow(id: "main")
            NSApp.activate()
        }
        .buttonStyle(.glassProminent)
        .tint(engine.plan?.mode.palette.deep ?? Palette.ink)
    }
}
