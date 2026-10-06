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
    @Environment(VoiceRecorder.self) private var recorder
    @Environment(NoteEnhancer.self) private var enhancer
    @AppStorage(Preference.persona) private var persona = Persona.personal
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Preference.focusMode) private var mode = FocusMode.flight

    private var tint: Color {
        if engine.isResting { return Palette.rest.mid }
        return (engine.plan?.mode ?? mode).palette.mid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if engine.isActive, let plan = engine.plan {
                session(plan)
            } else {
                idle
            }
            if recorder.isActive, !engine.isActive {
                Button {
                    recorder.stopNow(engine: engine, enhancer: enhancer, persona: persona)
                } label: {
                    Label("Stop recording", systemImage: "stop.fill")
                        .font(.rounded(13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(Palette.record, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(18)
        .frame(width: 300)
        .background {
            ZStack {
                Color.black
                RadialGradient(colors: [tint.opacity(0.28), .clear], center: .topLeading, startRadius: 0, endRadius: 260)
            }
            .ignoresSafeArea()
        }
        .environment(\.colorScheme, .dark)
        .animation(Motion.standard, value: engine.isPaused)
    }

    private func session(_ plan: FocusPlan) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.12), lineWidth: 5)
                        Circle()
                            .trim(from: 0, to: engine.isResting ? engine.segmentProgress(at: context.date) : engine.focusProgress(at: context.date))
                            .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: engine.focusProgress(at: context.date))
                        Image(systemName: engine.isResting ? "cup.and.saucer.fill" : plan.mode.symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    .frame(width: 58, height: 58)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 6) {
                            Text(engine.isPaused ? "Paused" : engine.isResting ? "Break" : plan.kind.title)
                            if recorder.isActive {
                                Circle().fill(Palette.record).frame(width: 6, height: 6)
                                Text("Recording")
                                    .foregroundStyle(Palette.record)
                            }
                        }
                        .font(.rounded(12, weight: .semibold))
                        .foregroundStyle(tint)
                        Text(engine.remaining(at: context.date).clock)
                            .font(.numeric(34, weight: .bold))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText(countsDown: true))
                            .animation(Motion.quick, value: engine.remaining(at: context.date).clock)
                    }
                }
            }
            if !plan.intention.isEmpty {
                Text(plan.intention)
                    .font(.rounded(13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
            }
            HStack(spacing: 8) {
                control(engine.isPaused ? "play.fill" : "pause.fill", engine.isPaused ? "Resume" : "Pause") {
                    engine.togglePause()
                }
                control("forward.end.fill", engine.isResting ? "Skip break" : "Skip round") {
                    engine.skip()
                }
                Spacer()
                openButton
            }
        }
    }

    private var idle: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("This week")
                        .font(.rounded(12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                    Text(library.focusedTime(in: .currentWeek).compactDuration)
                        .font(.numeric(30, weight: .bold))
                        .foregroundStyle(.white)
                }
                Spacer()
                Image("Logo")
                    .resizable()
                    .frame(width: 34, height: 34)
            }
            HStack {
                Spacer()
                openButton
            }
        }
    }

    private func control(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.12), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.pressable)
        .help(help)
    }

    private var openButton: some View {
        Button {
            openWindow(id: "main")
            NSApp.activate()
        } label: {
            Text("Open FocusKit")
                .font(.rounded(13, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(.white, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.pressable)
    }
}
