import EventKit
import AVFoundation
import FoundationModels
import SwiftUI
import UserNotifications

struct OnboardingView: View {
    @Environment(Library.self) private var library
    @AppStorage(Preference.persona) private var storedPersona = Persona.personal
    @AppStorage(Preference.name) private var storedName = ""
    @AppStorage(Preference.hasOnboarded) private var hasOnboarded = false
    @AppStorage(Preference.isReplayingOnboarding) private var isReplay = false
    @AppStorage(Preference.focusMode) private var storedMode = FocusMode.flight
    @AppStorage("rounds") private var storedRounds = 1
    @AppStorage("breakMinutes") private var storedBreak = 5

    @State private var step = Step.welcome
    @State private var direction: Edge = .trailing
    @State private var persona: Persona?
    @State private var name = ""
    @State private var picks: [String] = []
    @State private var custom = ""
    @State private var mode: FocusMode?
    @State private var rhythm: Persona.Rhythm?
    @FocusState private var fieldFocused: Bool

    enum Step: Int, CaseIterable {
        case welcome, persona, name, goals, mode, permissions, ready
    }

    private var palette: ModePalette {
        mode?.palette ?? (persona?.suggestedMode.palette ?? Palette.neutral)
    }

    var body: some View {
        ZStack {
            AmbientBackground(palette: palette, intensity: 0.9)

            VStack(spacing: 0) {
                content
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: direction).combined(with: .opacity),
                        removal: .move(edge: direction == .trailing ? .leading : .trailing).combined(with: .opacity)
                    ))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
                    .padding(.horizontal, 44)
                    .padding(.bottom, 32)
            }
            .padding(.top, 52)
        }
        .overlay(alignment: .topTrailing) {
            if isReplay {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .help("Close without changes")
                .padding(20)
            }
        }
        .animation(Motion.morph, value: step)
        .preferredColorScheme(.light)
        .onAppear {
            guard isReplay else { return }
            persona = storedPersona
            name = storedName
            mode = storedMode
        }
    }

    private func close() {
        isReplay = false
        withAnimation(Motion.morph) { hasOnboarded = true }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcome
        case .persona: personaStep
        case .name: nameStep
        case .goals: goalsStep
        case .mode: modeStep
        case .permissions: PermissionsStep()
        case .ready: readyStep
        }
    }

    private var welcome: some View {
        VStack(spacing: 34) {
            OrbitingModes()
                .frame(width: 260, height: 260)
            VStack(spacing: 12) {
                Text("FocusKit")
                    .font(.rounded(52, weight: .bold))
                    .displayTracking(52)
                    .foregroundStyle(Palette.ink)
                Text("A calmer way to study, work and think.\nLet's set it up around you.")
                    .font(.rounded(18, weight: .medium))
                    .foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var personaStep: some View {
        VStack(spacing: 30) {
            heading("What brings you here?", "FocusKit adapts its words, defaults and smart notes to you.")
            HStack(spacing: 16) {
                ForEach(Persona.allCases) { item in
                    PersonaCard(persona: item, isSelected: persona == item) {
                        withAnimation(Motion.standard) {
                            persona = item
                            picks = []
                            mode = nil
                            rhythm = nil
                        }
                    }
                }
            }
            .frame(maxWidth: 860)
        }
        .padding(.horizontal, 44)
    }

    private var nameStep: some View {
        VStack(spacing: 30) {
            heading("What should we call you?", "Used for greetings. It stays on this Mac.")
            TextField("Your first name", text: $name)
                .textFieldStyle(.plain)
                .font(.rounded(28, weight: .semibold))
                .multilineTextAlignment(.center)
                .focused($fieldFocused)
                .padding(.horizontal, 24)
                .frame(width: 420, height: 68)
                .glassEffect(.regular.interactive(), in: .capsule)
                .onSubmit(advance)
                .onAppear { fieldFocused = true }
        }
    }

    private var goalsStep: some View {
        let persona = persona ?? .personal
        return VStack(spacing: 28) {
            heading(
                persona == .student ? "What are you studying?" : persona == .professional ? "What are you working on?" : "What do you want to make time for?",
                "Pick a few \(persona.goalNoun)s to start with. You can add dates and targets later."
            )
            FlowLayout(spacing: 10) {
                ForEach(Array(Set(persona.suggestions + picks)).sorted(), id: \.self) { suggestion in
                    let isPicked = picks.contains(suggestion)
                    Button {
                        withAnimation(Motion.quick) {
                            if isPicked { picks.removeAll { $0 == suggestion } } else { picks.append(suggestion) }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isPicked ? "checkmark" : "plus")
                                .font(.system(size: 11, weight: .bold))
                                .contentTransition(.symbolEffect(.replace))
                            Text(suggestion)
                                .font(.rounded(15, weight: .semibold))
                        }
                        .foregroundStyle(isPicked ? .white : Palette.ink)
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .background(isPicked ? AnyShapeStyle(palette.deep) : AnyShapeStyle(.white.opacity(0.55)), in: .capsule)
                        .contentShape(.capsule)
                    }
                    .buttonStyle(.pressable)
                }
            }
            .frame(maxWidth: 700)

            HStack(spacing: 10) {
                TextField("Add your own", text: $custom)
                    .textFieldStyle(.plain)
                    .font(.rounded(15, weight: .medium))
                    .onSubmit(addCustom)
                Button("Add", action: addCustom)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.leading, 20)
            .padding(.trailing, 6)
            .frame(width: 380, height: 48)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .padding(.horizontal, 44)
    }

    private var modeStep: some View {
        let persona = persona ?? .personal
        let selectedMode = mode ?? persona.suggestedMode
        let selectedRhythm = rhythm ?? persona.rhythms[0]
        return VStack(spacing: 26) {
            heading("Pick your focus style", "Each mode tells the story of your session. You can switch any time.")
            HStack(spacing: 14) {
                ForEach(FocusMode.allCases) { item in
                    Button {
                        withAnimation(Motion.standard) { mode = item }
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            FocusScene(mode: item, progress: { _ in 0.62 }, isAnimated: item == selectedMode, insets: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
                                .frame(height: 110)
                                .background(item.palette.light)
                                .clipShape(.rect(cornerRadius: 18))
                                .allowsHitTesting(false)
                            HStack {
                                Text(item.title)
                                    .font(.rounded(15, weight: .bold))
                                    .foregroundStyle(Palette.ink)
                                Spacer()
                                if item == persona.suggestedMode {
                                    Text("Suggested")
                                        .font(.rounded(10, weight: .bold))
                                        .foregroundStyle(item.palette.deep)
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                        .padding(8)
                        .frame(width: 190)
                        .contentShape(.rect(cornerRadius: 24))
                    }
                    .buttonStyle(PressableStyle(scale: 0.97))
                    .glassEffect(item == selectedMode ? .regular.tint(item.palette.mid.opacity(0.25)).interactive() : .regular.interactive(), in: .rect(cornerRadius: 24))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(item.palette.deep.opacity(item == selectedMode ? 0.6 : 0), lineWidth: 2)
                    }
                }
            }

            HStack(spacing: 12) {
                ForEach(persona.rhythms, id: \.self) { item in
                    let isSelected = item == selectedRhythm
                    Button {
                        withAnimation(Motion.quick) { rhythm = item }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name)
                                .font(.rounded(15, weight: .bold))
                            Text(item.detail)
                                .font(.rounded(12, weight: .medium))
                                .opacity(0.75)
                        }
                        .foregroundStyle(isSelected ? .white : Palette.ink)
                        .padding(.horizontal, 18)
                        .frame(width: 210, height: 60, alignment: .leading)
                        .background(isSelected ? AnyShapeStyle(selectedMode.palette.deep) : AnyShapeStyle(.white.opacity(0.55)), in: .rect(cornerRadius: 20))
                        .contentShape(.rect(cornerRadius: 20))
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
        .padding(.horizontal, 44)
    }

    private var readyStep: some View {
        let persona = persona ?? .personal
        let first = name.trimmingCharacters(in: .whitespaces)
        return VStack(spacing: 26) {
            Image(systemName: "checkmark")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 96, height: 96)
                .background(palette.deep.gradient, in: .circle)
                .shadow(color: palette.deep.opacity(0.4), radius: 24, y: 10)
                .symbolEffect(.bounce, value: step)
            heading(first.isEmpty ? "You're all set" : "You're all set, \(first)", summary(for: persona))
        }
    }

    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.rounded(40, weight: .bold))
                .displayTracking(40)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.rounded(17, weight: .medium))
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
        }
    }

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button {
                    go(to: Step(rawValue: step.rawValue - 1) ?? .welcome, from: .leading)
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.rounded(14, weight: .semibold))
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
            }
            Spacer()
            StepDots(count: Step.allCases.count, current: step.rawValue, tint: palette.deep)
            Spacer()
            Button(action: advance) {
                Text(primaryTitle)
                    .font(.rounded(15, weight: .semibold))
                    .padding(.horizontal, 10)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(palette.deep)
            .keyboardShortcut(.defaultAction)
            .disabled(step == .persona && persona == nil)
        }
        .frame(maxWidth: 900)
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: "Get Started"
        case .name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Skip" : "Continue"
        case .goals: picks.isEmpty ? "Skip" : "Continue"
        case .ready: "Start Focusing"
        default: "Continue"
        }
    }

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else {
            finish()
            return
        }
        go(to: next, from: .trailing)
    }

    private func go(to target: Step, from edge: Edge) {
        direction = edge
        withAnimation(Motion.morph) { step = target }
    }

    private func addCustom() {
        let value = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !picks.contains(value) else { return }
        withAnimation(Motion.quick) {
            picks.append(value)
            custom = ""
        }
    }

    private func summary(for persona: Persona) -> String {
        let rhythm = rhythm ?? persona.rhythms[0]
        let mode = mode ?? persona.suggestedMode
        let goals = picks.isEmpty ? "" : " with \(picks.count) \(persona.goalNoun)\(picks.count == 1 ? "" : "s")"
        return "\(mode.title) mode, \(rhythm.name.lowercased()) rhythm\(goals). \(persona.promise)"
    }

    private func finish() {
        let persona = persona ?? .personal
        let rhythm = rhythm ?? persona.rhythms[0]
        let mode = mode ?? persona.suggestedMode
        storedPersona = persona
        storedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        storedMode = mode
        storedRounds = rhythm.rounds
        storedBreak = max(5, rhythm.breakMinutes)
        for item in FocusMode.allCases {
            UserDefaults.standard.set(rhythm.minutes, forKey: Preference.minutes(for: item))
        }
        let tints = Goal.Tint.allCases
        let existing = Set(library.goals.map(\.title))
        for (index, title) in picks.enumerated() where !existing.contains(title) {
            library.save(Goal(title: title, tint: tints[(index * 3) % tints.count], weeklyTargetMinutes: persona == .student ? 240 : 300))
        }
        isReplay = false
        withAnimation(Motion.morph) { hasOnboarded = true }
    }
}

private struct PersonaCard: View {
    let persona: Persona
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    private var tint: Color {
        persona.suggestedMode.palette.deep
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: persona.symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(tint.gradient, in: .rect(cornerRadius: 18))
                    .shadow(color: tint.opacity(0.35), radius: 12, y: 6)
                    .symbolEffect(.bounce, value: isSelected)
                VStack(alignment: .leading, spacing: 6) {
                    Text(persona.title)
                        .font(.rounded(21, weight: .bold))
                        .foregroundStyle(Palette.ink)
                    Text(persona.pitch)
                        .font(.rounded(14, weight: .medium))
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    tag(persona.goalsTitle)
                    tag(persona.highlight)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
            .contentShape(.rect(cornerRadius: 30))
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .glassEffect(isSelected ? .regular.tint(tint.opacity(0.18)).interactive() : .regular.interactive(), in: .rect(cornerRadius: 30))
        .overlay {
            RoundedRectangle(cornerRadius: 30)
                .strokeBorder(tint.opacity(isSelected ? 0.7 : 0), lineWidth: 2)
        }
        .scaleEffect(isHovering && !isSelected ? 1.015 : 1)
        .animation(Motion.quick, value: isHovering)
        .onHover { isHovering = $0 }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.rounded(11, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(tint.opacity(0.12), in: .capsule)
    }
}

private struct OrbitingModes: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { context in
            let angle = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate * 0.25
            ZStack {
                Circle()
                    .stroke(Palette.ink.opacity(0.08), style: StrokeStyle(lineWidth: 1.5, dash: [2, 6]))
                    .padding(30)
                Image("Logo")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 112, height: 112)
                    .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
                ForEach(Array(FocusMode.allCases.enumerated()), id: \.element) { index, mode in
                    let theta = angle + Double(index) * .pi / 2
                    Image(systemName: mode.symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(mode.palette.deep.gradient, in: .circle)
                        .shadow(color: mode.palette.deep.opacity(0.35), radius: 10, y: 5)
                        .offset(x: cos(theta) * 100, y: sin(theta) * 100)
                }
            }
        }
    }
}

private struct StepDots: View {
    let count: Int
    let current: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? tint : Palette.ink.opacity(0.15))
                    .frame(width: index == current ? 22 : 7, height: 7)
            }
        }
        .animation(Motion.standard, value: current)
    }
}

struct PermissionsStep: View {
    enum Status: Equatable {
        case needed
        case working
        case granted
        case blocked(String)
    }

    @State private var notifications = Status.needed
    @State private var microphone = Status.needed
    @State private var speech = Status.needed
    @State private var calendar = Status.needed
    @State private var music = Status.needed
    @AppStorage(Preference.homeAirport) private var homeCode = Airport.fallback.code
    @AppStorage(Preference.transcriptionLocale) private var localeIdentifier = ""

    private var allGranted: Bool {
        [notifications, microphone, speech, calendar, music].allSatisfy { $0 == .granted }
    }

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 10) {
                Text("A few last things")
                    .font(.rounded(40, weight: .bold))
                    .displayTracking(40)
                    .foregroundStyle(Palette.ink)
                Text("Everything stays on this Mac. Allow what you need now, or later in Settings.")
                    .font(.rounded(17, weight: .medium))
                    .foregroundStyle(Palette.inkSecondary)
            }

            Button {
                Task { await allowAll() }
            } label: {
                Label(allGranted ? "All set" : "Allow All", systemImage: allGranted ? "checkmark" : "hand.raised.fill")
                    .font(.rounded(14, weight: .semibold))
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(FocusMode.flight.palette.deep)
            .disabled(allGranted)

            ScrollView {
                VStack(spacing: 8) {
                    row("bell.badge.fill", Palette.rest.deep, "Notifications", "When a break starts or a session ends.", notifications, requestNotifications)
                    row("mic.fill", Palette.record, "Microphone", "To record lectures and meetings.", microphone, requestMicrophone)
                    row("waveform", FocusMode.tide.palette.deep, "Transcription", "Downloads \(Locale.speech(localeIdentifier).localizedName) so your first lecture starts right away.", speech, installSpeech)
                    row("calendar", FocusMode.flight.palette.deep, "Calendar", "Your classes and meetings in the notch.", calendar, requestCalendar)
                    row("music.note", FocusMode.bloom.palette.deep, "Music control", "Play, pause and skip Spotify or Music from the notch.", music, requestMusic)
                    intelligenceRow
                    airportRow
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.never)
            .frame(width: 580)
            .frame(maxHeight: 430)
        }
        .task { await refresh() }
    }

    private func row(_ symbol: String, _ tint: Color, _ title: String, _ detail: String, _ status: Status, _ action: @escaping () async -> Void) -> some View {
        HStack(spacing: 14) {
            icon(symbol, tint: tint)
            text(title, status.blockedMessage ?? detail)
            Spacer()
            switch status {
            case .granted:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(FocusMode.bloom.palette.deep)
                    .transition(.scale.combined(with: .opacity))
            case .working:
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 60)
            case .needed:
                Button("Allow") { Task { await action() } }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(tint)
            case .blocked:
                Button("Settings") { openPrivacySettings() }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .animation(Motion.settle, value: status)
    }

    private func allowAll() async {
        if notifications == .needed { await requestNotifications() }
        if microphone == .needed { await requestMicrophone() }
        if calendar == .needed { await requestCalendar() }
        if music == .needed { await requestMusic() }
        if speech == .needed { await installSpeech() }
    }

    private func refresh() async {
        let center = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notifications = switch center {
        case .authorized, .provisional, .ephemeral: .granted
        case .denied: .blocked("Notifications are off for FocusKit.")
        default: .needed
        }
        microphone = switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .blocked("Microphone access is off for FocusKit.")
        default: .needed
        }
        calendar = switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .needed
        default: .blocked("Calendar access is off for FocusKit.")
        }
        if speech != .working {
            speech = await Transcription.isInstalled(Locale.speech(localeIdentifier)) ? .granted : .needed
        }
        if music == .needed {
            music = await MusicPermission.status(asking: false)
        }
    }

    private func requestNotifications() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await refresh()
    }

    private func requestMicrophone() async {
        _ = await AVAudioApplication.requestRecordPermission()
        await refresh()
    }

    private func requestCalendar() async {
        _ = try? await EKEventStore().requestFullAccessToEvents()
        await refresh()
    }

    private func requestMusic() async {
        music = .working
        music = await MusicPermission.status(asking: true)
    }

    private func installSpeech() async {
        speech = .working
        do {
            try await Transcription.install(Locale.speech(localeIdentifier))
            speech = .granted
        } catch {
            speech = .blocked(error.localizedDescription)
        }
    }

    private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }

    private var intelligenceRow: some View {
        let available = SystemLanguageModel.default.availability == .available
        return HStack(spacing: 14) {
            icon("apple.intelligence", tint: FocusMode.orbit.palette.deep)
            text("Apple Intelligence", available ? "Ready. Notes and flashcards are written on device." : "Turn it on in System Settings to get smart notes.")
            Spacer()
            Image(systemName: available ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.system(size: 22))
                .foregroundStyle(available ? FocusMode.bloom.palette.deep : Palette.inkTertiary)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private var airportRow: some View {
        HStack(spacing: 14) {
            icon("airplane.departure", tint: FocusMode.flight.palette.deep)
            text("Home airport", "Where your Flight sessions take off.")
            Spacer()
            Picker("Home airport", selection: $homeCode) {
                ForEach(Airport.catalog.sorted { $0.city < $1.city }) { airport in
                    Text(verbatim: "\(airport.city) · \(airport.code)").tag(airport.code)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func icon(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(tint.gradient, in: .rect(cornerRadius: 12))
    }

    private func text(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.rounded(15, weight: .bold))
                .foregroundStyle(Palette.ink)
            Text(detail)
                .font(.rounded(13, weight: .medium))
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(2)
        }
    }
}

private extension PermissionsStep.Status {
    var blockedMessage: String? {
        if case .blocked(let message) = self { return message }
        return nil
    }
}

enum MusicPermission {
    static func status(asking: Bool) async -> PermissionsStep.Status {
        let results = await Task.detached(priority: .userInitiated) {
            ["com.spotify.client", "com.apple.Music"].map { bundle -> OSStatus in
                let target = NSAppleEventDescriptor(bundleIdentifier: bundle)
                return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, asking)
            }
        }.value
        if results.contains(noErr) { return .granted }
        if results.contains(OSStatus(errAEEventNotPermitted)) { return .blocked("Music control is off for FocusKit.") }
        if asking, results.allSatisfy({ $0 == OSStatus(procNotFound) }) {
            return .blocked("Open Spotify or Music once, then allow it here.")
        }
        return .needed
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: min(width, proposal.width ?? width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = ([index], size.width, size.height)
            } else {
                current = (current.indices + [index], needed, max(current.height, size.height))
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
