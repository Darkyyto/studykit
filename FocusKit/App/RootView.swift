import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case focus, goals, recordings, journal

    var id: String { rawValue }

    func title(for persona: Persona) -> String {
        switch self {
        case .focus: "Focus"
        case .goals: persona.goalsTitle
        case .recordings: persona.recordingsTitle
        case .journal: "Journal"
        }
    }

    var symbol: String {
        switch self {
        case .focus: "circle.circle"
        case .goals: "flag"
        case .recordings: "waveform"
        case .journal: "chart.bar.xaxis"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .focus: "1"
        case .goals: "2"
        case .recordings: "3"
        case .journal: "4"
        }
    }
}

struct RootView: View {
    @AppStorage("section") private var section = AppSection.focus
    @State private var modal: Modal?
    @State private var isOnScreen = true
    @State private var hidesUpdateBanner = false
    @AppStorage(Preference.focusMode) private var mode = FocusMode.flight
    @Environment(FocusEngine.self) private var engine
    @AppStorage(Preference.hasOnboarded) private var hasOnboarded = false
    @State private var revealsChrome = false
    @Environment(Library.self) private var library
    @Environment(Updater.self) private var updater
    @Environment(VoiceRecorder.self) private var recorder
    @Environment(NoteEnhancer.self) private var enhancer
    @AppStorage(Preference.persona) private var persona = Persona.personal

    private var sessionIsOpen: Bool {
        engine.isActive || engine.phase.isComplete
    }

    private var isImmersive: Bool {
        section == .focus && (engine.isActive || engine.phase.isComplete)
    }

    private var showsChrome: Bool {
        !isImmersive || revealsChrome
    }

    private var backgroundPalette: ModePalette {
        if engine.isResting { return Palette.rest }
        return (engine.plan?.mode).flatMap { engine.isActive ? $0 : nil }?.palette ?? mode.palette
    }

    var body: some View {
        Group {
            if hasOnboarded {
                main
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            } else {
                OnboardingView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(Motion.morph, value: hasOnboarded)
        .onAppear {
            if !sessionIsOpen {
                recorder.finishSession(engine: engine, enhancer: enhancer, persona: persona)
            }
        }
        .onChange(of: sessionIsOpen) { _, open in
            if !open {
                recorder.finishSession(engine: engine, enhancer: enhancer, persona: persona)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppDelegate.openDocuments)) { notification in
            let urls = notification.userInfo?["urls"] as? [URL] ?? []
            guard let document = urls.lazy.compactMap({ PDFImport.open($0, into: library) }).first else { return }
            library.pendingDocumentID = document.id
            withAnimation(Motion.standard) { section = .focus }
        }
        .frame(minWidth: 920, minHeight: 640)
        .preferredColorScheme(.light)
    }

    private var main: some View {
        @Bindable var updater = updater
        return ZStack(alignment: .top) {
            AmbientBackground(palette: backgroundPalette, intensity: section == .focus ? 1 : 0.4)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                .id(section)
                .environment(\.chromeInset, showsChrome ? 72 : 44)

            if let release = updater.available, !hidesUpdateBanner, !isImmersive {
                UpdateBanner(release: release) {
                    updater.presented = release
                } close: {
                    withAnimation(Motion.standard) { hidesUpdateBanner = true }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 22)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            TabBar(selection: $section)
                .padding(.top, 12)
                .opacity(showsChrome ? 1 : 0)
                .offset(y: showsChrome ? 0 : -28)
                .allowsHitTesting(showsChrome)
        }
        .onContinuousHover { phase in
            guard isImmersive else { return }
            let reveal = if case .active(let point) = phase { point.y < 64 || (revealsChrome && point.y < 96) } else { false }
            if reveal != revealsChrome {
                withAnimation(Motion.standard) { revealsChrome = reveal }
            }
        }
        .animation(Motion.standard, value: section)
        .animation(Motion.standard, value: isImmersive)
        .animation(Motion.settle, value: updater.available?.version)
        .focusedSceneValue(\.section, $section)
        .card(item: $modal) { modal in
            switch modal {
            case .goal(let goal):
                GoalEditor(goal: goal)
            case .subject(let id):
                SubjectDetail(goalID: id)
                    .frame(width: 760, height: 620)
            case .recording(let recording):
                RecordingDetail(recording: recording)
                    .frame(width: 720, height: 600)
            }
        }
        .card(item: $updater.presented) { release in
            UpdateCard(release: release)
        }
        .environment(\.present, PresentAction { [binding = $modal] in binding.wrappedValue = $0 })
        .environment(\.isOnScreen, isOnScreen)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { notification in
            guard let window = notification.object as? NSWindow, window.title == "FocusKit" else { return }
            isOnScreen = window.occlusionState.contains(.visible) && !window.isMiniaturized
        }
        .onReceive(NotificationCenter.default.publisher(for: .showFocus)) { _ in
            withAnimation(Motion.standard) { section = .focus }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .focus: FocusScreen()
        case .goals: GoalsScreen()
        case .recordings: RecordingsScreen()
        case .journal: JournalScreen()
        }
    }
}

private struct TabBar: View {
    @Binding var selection: AppSection
    @Environment(FocusEngine.self) private var engine
    @Environment(Updater.self) private var updater

    private var isDownloading: Bool {
        if case .downloading = updater.state { return true }
        return false
    }
    @Environment(VoiceRecorder.self) private var recorder
    @AppStorage(Preference.persona) private var persona = Persona.personal
    @Namespace private var pill
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 2) {
                    ForEach(AppSection.allCases) { section in
                        tab(section)
                    }
                }
                .padding(4)
                .glassEffect(.regular, in: .capsule)
                .glassEffectID("tabs", in: glass)

                ProfileMenu()
                    .glassEffectID("profile", in: glass)

                if updater.available != nil || isDownloading {
                    UpdateChip()
                        .glassEffectID("update", in: glass)
                }

                if engine.isActive, selection != .focus {
                    liveTimer
                        .glassEffectID("timer", in: glass)
                }
            }
        }
        .animation(Motion.morph, value: engine.isActive && selection != .focus)
        .animation(Motion.morph, value: updater.state)
    }

    private func tab(_ section: AppSection) -> some View {
        let isSelected = selection == section
        return Button {
            withAnimation(Motion.quick) { selection = section }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: section.symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(section.title(for: persona))
                    .font(.rounded(13, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Palette.ink : Palette.inkSecondary)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background {
                if isSelected {
                    Capsule()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isLive(section) {
                    Circle()
                        .fill(section == .recordings ? Palette.record : engine.plan?.mode.palette.deep ?? Palette.ink)
                        .frame(width: 6, height: 6)
                        .offset(x: -6, y: 5)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.pressable)
        .help("\(section.title(for: persona)) (⌘\(String(section.shortcut.character)))")
    }

    private func isLive(_ section: AppSection) -> Bool {
        switch section {
        case .focus: engine.isActive && selection != .focus
        case .recordings: recorder.isActive && selection != .recordings
        case .goals, .journal: false
        }
    }

    private var liveTimer: some View {
        Button {
            withAnimation(Motion.quick) { selection = .focus }
        } label: {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 6) {
                    Image(systemName: engine.isResting ? "cup.and.saucer.fill" : engine.plan?.mode.symbol ?? "circle")
                        .font(.system(size: 11, weight: .semibold))
                    Text(engine.remaining(at: context.date).clock)
                        .font(.numeric(13))
                        .contentTransition(.numericText(countsDown: true))
                }
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 14)
                .frame(height: 40)
            }
        }
        .buttonStyle(.pressable)
        .glassEffect(.regular.tint(engine.plan?.mode.palette.mid.opacity(0.35)).interactive(), in: .capsule)
    }
}

private struct UpdateChip: View {
    @Environment(Updater.self) private var updater

    var body: some View {
        Button {
            updater.presented = updater.pending
        } label: {
            HStack(spacing: 7) {
                switch updater.state {
                case .downloading(let fraction):
                    ProgressRing(progress: fraction, tint: FocusMode.flight.palette.deep, lineWidth: 2.5)
                        .frame(width: 14, height: 14)
                    Text("\(Int(fraction * 100))%")
                        .font(.numeric(13, weight: .semibold))
                        .contentTransition(.numericText())
                case .ready:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FocusMode.bloom.palette.deep)
                    Text("Ready to install")
                        .font(.rounded(13, weight: .semibold))
                default:
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FocusMode.flight.palette.deep)
                        .symbolEffect(.bounce, options: .repeat(2), value: updater.pending?.version)
                    Text("Update")
                        .font(.rounded(13, weight: .semibold))
                }
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .contentShape(.capsule)
        }
        .buttonStyle(.pressable)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

private struct ProfileMenu: View {
    @AppStorage(Preference.persona) private var persona = Persona.personal
    @AppStorage(Preference.hasOnboarded) private var hasOnboarded = true
    @AppStorage(Preference.isReplayingOnboarding) private var isReplayingOnboarding = false

    private var selection: Binding<Persona> {
        Binding(get: { persona }, set: { value in withAnimation(Motion.morph) { persona = value } })
    }

    var body: some View {
        Menu {
            Picker("Use FocusKit as", selection: selection) {
                ForEach(Persona.allCases) { item in
                    Label(item.title, systemImage: item.symbol).tag(item)
                }
            }
            .pickerStyle(.inline)

            Divider()

            Button("Replay Onboarding", systemImage: "arrow.counterclockwise") {
                isReplayingOnboarding = true
                withAnimation(Motion.morph) { hasOnboarded = false }
            }
            SettingsLink {
                Label("Settings…", systemImage: "gearshape")
            }
        } label: {
            Image(systemName: persona.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 40, height: 40)
                .contentShape(.circle)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .glassEffect(.regular.interactive(), in: .circle)
        .help("Using FocusKit as \(persona.title)")
    }
}

extension EnvironmentValues {
    @Entry var chromeInset: CGFloat = 72
}

private struct UpdateBanner: View {
    let release: Updater.Release
    let install: () -> Void
    let close: () -> Void
    @Environment(Updater.self) private var updater

    var body: some View {
        HStack(spacing: 14) {
            Image("Logo")
                .resizable()
                .interpolation(.high)
                .frame(width: 34, height: 34)
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            VStack(alignment: .leading, spacing: 1) {
                Text("FocusKit \(release.version) is available")
                    .font(.rounded(14, weight: .bold))
                    .foregroundStyle(Palette.ink)
                Text(subtitle)
                    .font(.rounded(12, weight: .medium))
                    .foregroundStyle(Palette.inkSecondary)
                    .contentTransition(.numericText())
            }
            Button(action: install) {
                Text(buttonTitle)
                    .font(.rounded(13, weight: .semibold))
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(FocusMode.flight.palette.deep)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(width: 26, height: 26)
                    .contentShape(.circle)
            }
            .buttonStyle(.pressable)
            .help("Later")
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
    }

    private var subtitle: String {
        switch updater.state {
        case .downloading(let fraction): "Downloading… \(Int(fraction * 100))%"
        case .ready: "Downloaded. Ready to install."
        default: "Your sessions and lectures stay as they are."
        }
    }

    private var buttonTitle: String {
        if case .ready = updater.state { return "Install" }
        if case .downloading = updater.state { return "Show" }
        return "Update"
    }
}
