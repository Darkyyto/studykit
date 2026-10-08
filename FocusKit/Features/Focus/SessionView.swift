import SwiftUI

struct SessionView: View {
    @Environment(FocusEngine.self) private var engine
    @Environment(Library.self) private var library
    @Environment(VoiceRecorder.self) private var recorder
    @Environment(NoteEnhancer.self) private var enhancer
    @Environment(Soundscape.self) private var soundscape
    @Environment(\.chromeInset) private var chromeInset
    @AppStorage(Preference.transcriptionLocale) private var localeIdentifier = ""
    @AppStorage(Preference.persona) private var persona = Persona.personal
    @State private var showsCompanion = false
    @State private var expandsCompanion = false
    @AppStorage("companionWidth") private var companionWidth = 330.0
    @State private var showsReader = true
    @State private var companion = Companion.notes
    @State private var confirmsEnd = false
    @State private var showsCompletion = false
    @Namespace private var controls

    var body: some View {
        if let plan = engine.plan {
            let panelWidth: CGFloat = hasPanel(plan) && !expandsCompanion ? CGFloat(companionWidth) + 22 : 0
            ZStack(alignment: .bottom) {
                if let document = readerDocument(plan) {
                    ReaderStage(
                        document: document,
                        url: library.url(for: document),
                        plan: plan,
                        canTakeNotes: plan.kind.companions.contains(.notes),
                        showScene: { withAnimation(Motion.morph) { showsReader = false } },
                        end: { withAnimation(Motion.settle) { confirmsEnd = true } },
                        quoted: {
                            if plan.kind.companions.contains(.notes) {
                                showsCompanion = true
                                companion = .notes
                            }
                        }
                    )
                    .padding(.trailing, panelWidth - (panelWidth > 0 ? 16 : 0))
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    stage(plan)
                        .padding(.trailing, panelWidth)
                        .ignoresSafeArea()
                        .transition(.opacity)

                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        console(plan, at: context.date)
                    }
                    .padding(.bottom, 40)
                    .padding(.trailing, panelWidth)
                    .opacity(engine.phase.isComplete ? 0 : 1)
                }

                if hasPanel(plan) {
                    HStack(alignment: .top) {
                        Spacer()
                        CompanionPanel(kind: plan.kind, tint: plan.mode.palette.deep, selection: $companion, width: $companionWidth, isExpanded: $expandsCompanion) {
                            withAnimation(Motion.morph) {
                                showsCompanion = false
                                expandsCompanion = false
                            }
                        }
                    }
                    .padding(.leading, expandsCompanion ? 16 : 0)
                    .padding(.top, chromeInset)
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                if case .complete(let session) = engine.phase, showsCompletion {
                    CompletionCard(session: session, stopRecording: recordingStopper(for: plan))
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }

                if confirmsEnd {
                    EndSessionPrompt(plan: plan, focused: engine.focused(at: engine.now)) {
                        withAnimation(Motion.settle) { confirmsEnd = false }
                    } end: {
                        withAnimation(Motion.settle) { confirmsEnd = false }
                        engine.stop()
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.9)).combined(with: .offset(y: 20)),
                        removal: .opacity.combined(with: .scale(scale: 0.96))
                    ))
                    .zIndex(1)
                }
            }
            .animation(Motion.settle, value: engine.phase.isComplete)
            .animation(Motion.settle, value: confirmsEnd)
            .animation(Motion.settle, value: showsCompletion)
            .animation(Motion.morph, value: hasPanel(plan))
            .animation(Motion.morph, value: expandsCompanion)
            .animation(Motion.morph, value: showsReader)
            .background {
                Button("") {
                    withAnimation(Motion.morph) { showsCompanion.toggle() }
                }
                .keyboardShortcut("\\", modifiers: .command)
                .hidden()
            }
            .onAppear { prepare(plan) }
            .onChange(of: showsCompanion) { _, shows in
                if !shows { expandsCompanion = false }
            }
            .onChange(of: engine.phase.isComplete) { _, isComplete in
                guard isComplete else { return }
                showsCompletion = true
            }
        }
    }

    private func readerDocument(_ plan: FocusPlan) -> StudyDocument? {
        guard showsReader, !engine.isResting, !engine.phase.isComplete, let id = plan.documentID else { return nil }
        return library.documents.first { $0.id == id }
    }

    private func hasPanel(_ plan: FocusPlan) -> Bool {
        showsCompanion && !engine.phase.isComplete && !engine.isResting && !CompanionPanel.tabs(for: plan.kind).isEmpty
    }

    private func recordingStopper(for plan: FocusPlan) -> (() -> Void)? {
        guard plan.kind.recordsAudio, recorder.recordedThisSession else { return nil }
        return { recorder.finishSession(engine: engine, enhancer: enhancer, persona: persona) }
    }

    private func prepare(_ plan: FocusPlan) {
        companion = CompanionPanel.tabs(for: plan.kind).first ?? .notes
        showsCompanion = plan.kind.recordsAudio
        if plan.kind.recordsAudio, !recorder.isActive, !recorder.ownedBySession, engine.isActive {
            Task {
                await recorder.startForSession(
                    locale: .speech(localeIdentifier),
                    goalID: plan.goalID,
                    vocabulary: library.activeGoals.map(\.title),
                    noun: plan.kind == .lecture ? "Lecture" : "Meeting",
                    name: plan.intention
                )
            }
        }
        showsCompletion = engine.phase.isComplete
    }

    @ViewBuilder
    private func stage(_ plan: FocusPlan) -> some View {
        ZStack {
            if engine.isResting {
                if plan.kind.usesRecallBreaks {
                    RecallBreak(cards: library.flashcards(for: plan.goalID))
                        .padding(.bottom, 250)
                        .transition(.opacity)
                } else {
                    BreatheScene()
                        .transition(.opacity)
                }
            } else if plan.mode == .flight {
                let route = FlightRoute.resolve(plan.route)
                FlightMapScene(
                    origin: route.origin,
                    destination: route.destination,
                    progressAt: { engine.focusProgress(at: $0) },
                    isPaused: engine.isPaused,
                    isArrived: engine.phase.isComplete,
                    tick: engine.now
                )
                .transition(.opacity)
            } else {
                FocusScene(
                    mode: plan.mode,
                    progress: { engine.focusProgress(at: $0) },
                    route: plan.route,
                    variant: plan.variant,
                    isPaused: engine.isPaused,
                    insets: EdgeInsets(top: chromeInset + 24, leading: 60, bottom: 330, trailing: 60)
                )
                .overlay {
                    BottomFade(start: 0.52)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.8), value: engine.isResting)
    }

    private func console(_ plan: FocusPlan, at date: Date) -> some View {
        let remaining = engine.remaining(at: date)
        let tint = engine.isResting ? Palette.rest.deep : plan.mode.palette.deep

        return VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(caption(plan))
                    .font(.rounded(13, weight: .semibold))
                    .foregroundStyle(tint)
                    .contentTransition(.interpolate)
                Text(remaining.clock)
                    .font(.numeric(76, weight: .bold))
                    .displayTracking(76)
                    .foregroundStyle(Palette.ink.opacity(engine.isPaused ? 0.4 : 1))
                    .contentTransition(.numericText(countsDown: true))
                    .animation(Motion.quick, value: Int(remaining))
                Text(detail(plan, at: date))
                    .font(.rounded(14, weight: .medium))
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }

            if plan.rounds > 1 {
                RoundDots(total: plan.rounds, current: engine.segment?.round ?? 0, tint: plan.mode.palette.deep)
            }

            toolbar(plan, tint: tint)
        }
        .padding(.horizontal, 40)
    }

    private func toolbar(_ plan: FocusPlan, tint: Color) -> some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(Motion.morph) { engine.togglePause() }
            } label: {
                Image(systemName: engine.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
                    .background(tint, in: .circle)
            }
            .buttonStyle(.pressable)
            .keyboardShortcut(.space, modifiers: [])
            .help(engine.isPaused ? "Resume (Space)" : "Pause (Space)")

            divider

            toolbarButton("forward.end.fill", help: engine.isResting ? "Skip break" : "Finish this round now") {
                withAnimation(Motion.morph) { engine.skip() }
            }
            toolbarButton(soundscape.isEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill", help: soundscape.isEnabled ? "Mute soundscape" : "Play soundscape", isOn: soundscape.isEnabled, tint: tint) {
                soundscape.isEnabled.toggle()
            }
            if !CompanionPanel.tabs(for: plan.kind).isEmpty, !engine.isResting {
                toolbarButton("square.and.pencil", help: "Notes and tools (⌘\\)", isOn: showsCompanion, tint: tint) {
                    withAnimation(Motion.morph) { showsCompanion.toggle() }
                }
            }
            if plan.documentID != nil, !engine.isResting {
                toolbarButton("doc.text", help: "Back to the PDF") {
                    withAnimation(Motion.morph) { showsReader = true }
                }
            }

            divider

            toolbarButton("stop.fill", help: "End session") {
                withAnimation(Motion.settle) { confirmsEnd = true }
            }
        }
        .padding(5)
        .glassEffect(.regular, in: .capsule)
        .animation(Motion.standard, value: showsCompanion)
    }

    private var divider: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(width: 1, height: 22)
            .padding(.horizontal, 4)
    }

    private func toolbarButton(_ symbol: String, help: String, isOn: Bool = false, tint: Color = Palette.ink, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isOn ? tint : Palette.inkSecondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 40, height: 40)
                .background(isOn ? tint.opacity(0.12) : .clear, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.pressable)
        .help(help)
    }

    private func caption(_ plan: FocusPlan) -> String {
        let round = (engine.segment?.round ?? 0) + 1
        let prefix = plan.rounds > 1 ? "Round \(round) of \(plan.rounds) · " : ""
        if engine.isResting { return "Break · next round \(round + 1) of \(plan.rounds)" }
        if engine.isPaused { return prefix + "Paused" }
        return prefix + plan.mode.title
    }

    private func detail(_ plan: FocusPlan, at date: Date) -> String {
        if engine.isResting { return "Stand up, stretch, look far away." }
        if !plan.intention.isEmpty { return plan.intention }
        let progress = engine.focusProgress(at: date)
        switch plan.mode {
        case .flight:
            let route = FlightRoute.resolve(plan.route)
            let distance = Int(route.origin.distance(to: route.destination) * (1 - progress))
            return "\(distance.formatted()) km to \(route.destination.city)"
        case .orbit:
            return "\(Int(progress * 100))% of the orbit"
        case .bloom:
            return ["Seed", "Sprouting", "Growing", "Budding", "Blooming"][min(4, Int(progress * 5))]
        case .tide:
            return "Tide at \(Int(progress * 100))%"
        }
    }
}

private struct RoundDots: View {
    let total: Int
    let current: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? tint : tint.opacity(0.2))
                    .frame(width: index == current ? 22 : 8, height: 8)
            }
        }
        .animation(Motion.standard, value: current)
    }
}
