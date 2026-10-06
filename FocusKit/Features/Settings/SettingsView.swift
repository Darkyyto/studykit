import AVFoundation
import EventKit
import SwiftUI
import UserNotifications

struct SettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case profile, focus, notch, sound, transcription, updates, privacy

        var id: String { rawValue }

        var title: String {
            switch self {
            case .profile: "Profile"
            case .focus: "Focus"
            case .notch: "Notch"
            case .sound: "Sound"
            case .transcription: "Transcription"
            case .updates: "Updates"
            case .privacy: "Privacy & Data"
            }
        }

        var symbol: String {
            switch self {
            case .profile: "person.crop.circle.fill"
            case .focus: "circle.circle.fill"
            case .notch: "rectangle.topthird.inset.filled"
            case .sound: "speaker.wave.2.fill"
            case .transcription: "waveform"
            case .updates: "arrow.down.circle.fill"
            case .privacy: "hand.raised.fill"
            }
        }

        var tint: Color {
            switch self {
            case .profile: FocusMode.orbit.palette.deep
            case .focus: FocusMode.flight.palette.deep
            case .notch: Palette.ink
            case .sound: FocusMode.bloom.palette.deep
            case .transcription: FocusMode.tide.palette.deep
            case .updates: FocusMode.flight.palette.deep
            case .privacy: Palette.rest.deep
            }
        }
    }

    @State private var pane = Pane.profile
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(pane.title)
                        .font(.rounded(28, weight: .bold))
                        .displayTracking(28)
                        .foregroundStyle(Palette.ink)
                    Group {
                        switch pane {
                        case .profile: ProfilePane()
                        case .focus: FocusPane()
                        case .notch: NotchPane()
                        case .sound: SoundPane()
                        case .transcription: TranscriptionPane()
                        case .updates: UpdatesPane()
                        case .privacy: PrivacyPane()
                        }
                    }
                    .transition(.opacity.combined(with: .offset(y: 6)))
                }
                .id(pane)
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            .background(Palette.canvas)
            .animation(Motion.standard, value: pane)
        }
        .frame(width: 780, height: 560)
        .preferredColorScheme(.light)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Image("Logo")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 34, height: 34)
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                VStack(alignment: .leading, spacing: 0) {
                    Text("FocusKit")
                        .font(.rounded(15, weight: .bold))
                        .foregroundStyle(Palette.ink)
                    Text("Version \(Updater.currentVersion)")
                        .font(.rounded(11, weight: .medium))
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 16)

            ForEach(Pane.allCases) { item in
                Button {
                    withAnimation(Motion.quick) { pane = item }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(item.tint.gradient, in: .rect(cornerRadius: 7))
                        Text(item.title)
                            .font(.rounded(13.5, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 34)
                    .background {
                        if pane == item {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.white)
                                .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
                                .matchedGeometryEffect(id: "pane", in: selection)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.pressable)
            }
            Spacer()
        }
        .padding(12)
        .padding(.top, 20)
        .frame(width: 210)
        .background(Palette.canvas.opacity(0.4))
        .background(.thinMaterial)
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .background(.white, in: .rect(cornerRadius: 18))
        .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
    }
}

struct SettingsRow<Trailing: View>: View {
    let title: String
    var detail: String?
    var showsDivider = true
    @ViewBuilder let trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.rounded(14, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    if let detail {
                        Text(detail)
                            .font(.rounded(12, weight: .medium))
                            .foregroundStyle(Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                trailing
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            if showsDivider {
                Divider().padding(.leading, 16)
            }
        }
    }
}

private struct Footnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.rounded(12, weight: .medium))
            .foregroundStyle(Palette.inkTertiary)
            .padding(.horizontal, 6)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ProfilePane: View {
    @AppStorage(Preference.persona) private var persona = Persona.personal
    @AppStorage(Preference.name) private var name = ""
    @AppStorage(Preference.hasOnboarded) private var hasOnboarded = true
    @AppStorage(Preference.isReplayingOnboarding) private var isReplayingOnboarding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ForEach(Persona.allCases) { item in
                    let isSelected = persona == item
                    Button {
                        withAnimation(Motion.morph) { persona = item }
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(isSelected ? .white : FocusMode.orbit.palette.deep)
                                .frame(width: 40, height: 40)
                                .background(isSelected ? AnyShapeStyle(FocusMode.orbit.palette.deep.gradient) : AnyShapeStyle(FocusMode.orbit.palette.light), in: .rect(cornerRadius: 12))
                            Text(item.title)
                                .font(.rounded(15, weight: .bold))
                                .foregroundStyle(Palette.ink)
                            Text(item.pitch)
                                .font(.rounded(11.5, weight: .medium))
                                .foregroundStyle(Palette.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
                        .background(.white, in: .rect(cornerRadius: 18))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(FocusMode.orbit.palette.deep, lineWidth: 2)
                                .opacity(isSelected ? 1 : 0)
                        }
                        .contentShape(.rect(cornerRadius: 18))
                    }
                    .buttonStyle(.pressable)
                }
            }
            SettingsCard {
                SettingsRow(title: "Your name", detail: "Used in greetings.") {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }
                SettingsRow(title: "Setup", detail: "Walk through the welcome screens again.", showsDivider: false) {
                    Button("Replay Onboarding") {
                        isReplayingOnboarding = true
                        hasOnboarded = false
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                }
            }
        }
    }
}

private struct FocusPane: View {
    @AppStorage(Preference.homeAirport) private var homeCode = Airport.fallback.code
    @AppStorage(Preference.showsMenuBarExtra) private var showsMenuBarExtra = true
    @AppStorage("rounds") private var rounds = 1
    @AppStorage("breakMinutes") private var breakMinutes = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsCard {
                SettingsRow(title: "Home airport", detail: "Where Flight sessions take off.") {
                    Picker("Home airport", selection: $homeCode) {
                        ForEach(Airport.catalog.sorted { $0.city < $1.city }) { airport in
                            Text(verbatim: "\(airport.city) · \(airport.code)").tag(airport.code)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsRow(title: "Rounds", detail: "How many focus blocks a session has by default.") {
                    Stepper("\(rounds)", value: $rounds, in: 1...8)
                        .font(.numeric(14, weight: .semibold))
                        .fixedSize()
                }
                SettingsRow(title: "Break", detail: "Time between rounds.") {
                    Stepper("\(breakMinutes) min", value: $breakMinutes, in: 5...30, step: 5)
                        .font(.numeric(14, weight: .semibold))
                        .fixedSize()
                }
                SettingsRow(title: "Timer in the menu bar", detail: "Shows the time left while a session runs.", showsDivider: false) {
                    Toggle("", isOn: $showsMenuBarExtra)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
        }
    }
}

private struct NotchPane: View {
    @AppStorage(Preference.sideNotch) private var presence = IslandController.Presence.activity.rawValue
    @State private var calendarAccess = EKEventStore.authorizationStatus(for: .event)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ForEach(IslandController.Presence.allCases) { item in
                    let isSelected = presence == item.rawValue
                    Button {
                        withAnimation(Motion.quick) { presence = item.rawValue }
                    } label: {
                        VStack(spacing: 12) {
                            ZStack(alignment: .top) {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(LinearGradient(colors: [FocusMode.flight.palette.light, FocusMode.orbit.palette.light], startPoint: .topLeading, endPoint: .bottomTrailing))
                                UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6)
                                    .fill(.black)
                                    .frame(width: width(for: item), height: 12)
                                    .opacity(item == .off ? 0.15 : 1)
                            }
                            .frame(height: 70)
                            Text(item.title)
                                .font(.rounded(12.5, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                                .multilineTextAlignment(.center)
                                .frame(height: 32)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(.white, in: .rect(cornerRadius: 16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(FocusMode.flight.palette.deep, lineWidth: 2)
                                .opacity(isSelected ? 1 : 0)
                        }
                        .contentShape(.rect(cornerRadius: 16))
                    }
                    .buttonStyle(.pressable)
                }
            }
            Footnote(text: "Move the pointer to the top of the screen to open the notch: your session, music, and the day ahead.")
            SettingsCard {
                SettingsRow(title: "Calendar", detail: calendarAccess == .fullAccess ? "Connected. Events from all your calendars appear in the notch." : "Show your classes and meetings in the notch.", showsDivider: false) {
                    switch calendarAccess {
                    case .fullAccess:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(FocusMode.bloom.palette.deep)
                    case .notDetermined:
                        Button("Connect") {
                            Task {
                                _ = try? await EKEventStore().requestFullAccessToEvents()
                                calendarAccess = EKEventStore.authorizationStatus(for: .event)
                            }
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.capsule)
                    default:
                        Button("Open Settings") { Privacy.open("Privacy_Calendars") }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.capsule)
                    }
                }
            }
        }
    }

    private func width(for item: IslandController.Presence) -> CGFloat {
        switch item {
        case .always: 70
        case .activity: 46
        case .off: 34
        }
    }
}

private struct SoundPane: View {
    @AppStorage(Preference.soundscapeVolume) private var volume = 0.55
    @Environment(Soundscape.self) private var soundscape

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsCard {
                SettingsRow(title: "Soundscape", detail: "Play a sound generated live during sessions.") {
                    Toggle("", isOn: Binding(get: { soundscape.isEnabled }, set: { soundscape.isEnabled = $0 }))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsRow(title: "Volume", showsDivider: false) {
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.fill")
                            .foregroundStyle(Palette.inkTertiary)
                        Slider(value: $volume, in: 0.1...1)
                            .frame(width: 180)
                            .onChange(of: volume) { soundscape.applyVolume() }
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundStyle(Palette.inkTertiary)
                    }
                    .disabled(!soundscape.isEnabled)
                }
            }
            Footnote(text: "Cabin hum for Flight, waves for Tide, deep space for Orbit, soft rain for Bloom and a light breeze during breaks.")
        }
    }
}

private struct TranscriptionPane: View {
    @AppStorage(Preference.transcriptionLocale) private var localeIdentifier = ""
    @State private var locales: [Locale] = []
    @State private var installed: Bool?
    @State private var installing = false
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsCard {
                SettingsRow(title: "Language", detail: "The language spoken in your lectures and meetings.") {
                    Picker("Language", selection: $localeIdentifier) {
                        Text("System (\(Locale.preferredSpeech.localizedName))").tag("")
                        ForEach(locales, id: \.identifier) { locale in
                            Text(locale.localizedName).tag(locale.identifier)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsRow(title: "Speech model", detail: failure ?? (installed == true ? "Downloaded. Transcription works offline." : "Downloaded once, then everything runs on this Mac."), showsDivider: false) {
                    if installing {
                        ProgressView().controlSize(.small)
                    } else if installed == true {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(FocusMode.bloom.palette.deep)
                    } else if installed == false {
                        Button("Download") { Task { await install() } }
                            .buttonStyle(.glassProminent)
                            .buttonBorderShape(.capsule)
                    }
                }
            }
            Footnote(text: "After each lecture FocusKit listens to the whole recording again with a more accurate model, then fixes words that were hard to hear.")
        }
        .task(id: localeIdentifier) {
            if locales.isEmpty { locales = await Transcription.supportedLocales() }
            failure = nil
            installed = await Transcription.isInstalled(.speech(localeIdentifier))
        }
    }

    private func install() async {
        installing = true
        defer { installing = false }
        do {
            try await Transcription.install(.speech(localeIdentifier))
            installed = true
        } catch {
            failure = error.localizedDescription
        }
    }
}

private struct UpdatesPane: View {
    @Environment(Updater.self) private var updater
    @State private var checksAutomatically = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsCard {
                SettingsRow(title: "FocusKit \(Updater.currentVersion)", detail: status) {
                    if let release = updater.available {
                        Button("Install \(release.version)…") { updater.presented = release }
                            .buttonStyle(.glassProminent)
                            .buttonBorderShape(.capsule)
                    } else {
                        Button("Check Now") { Task { await updater.check(userInitiated: true) } }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.capsule)
                            .disabled(updater.state == .checking)
                    }
                }
                SettingsRow(title: "Check automatically", detail: "Every time FocusKit opens.") {
                    Toggle("", isOn: $checksAutomatically)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .onChange(of: checksAutomatically) { _, value in updater.checksAutomatically = value }
                }
                SettingsRow(title: "Backups", detail: "Saved before every update and once a day.", showsDivider: false) {
                    Button("Show in Finder") {
                        try? FileManager.default.createDirectory(at: Backup.directory, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(Backup.directory)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                }
            }
            Footnote(text: "An update replaces only the app. Sessions, lectures and notes stay in your library.")
        }
        .onAppear { checksAutomatically = updater.checksAutomatically }
    }

    private var status: String {
        switch updater.state {
        case .checking: "Checking…"
        case .upToDate: "You have the latest version."
        case .available(let release): "Version \(release.version) is available."
        case .downloading(let fraction): "Downloading… \(Int(fraction * 100))%"
        case .ready: "Downloaded and ready to install."
        case .failed(let message): message
        case .idle: "Free and open source."
        }
    }
}

private struct PrivacyPane: View {
    @State private var microphone = AVAudioApplication.shared.recordPermission
    @State private var notifications: UNAuthorizationStatus = .notDetermined
    @State private var calendar = EKEventStore.authorizationStatus(for: .event)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsCard {
                permission("Microphone", granted: microphone == .granted, pane: "Privacy_Microphone")
                permission("Notifications", granted: notifications == .authorized || notifications == .provisional, pane: "Notifications")
                permission("Calendar", granted: calendar == .fullAccess, pane: "Privacy_Calendars")
                SettingsRow(title: "Music control", detail: "Spotify and Music, from the notch.", showsDivider: false) {
                    Button("Open Settings") { Privacy.open("Privacy_Automation") }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                }
            }
            SettingsCard {
                SettingsRow(title: "Library", detail: "Sessions, lectures, notes and PDFs, stored only on this Mac.", showsDivider: false) {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Library.Location.standard.database])
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                }
            }
            Footnote(text: "No account, no analytics, no server. Transcription and notes run on device.")
        }
        .task {
            notifications = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        }
    }

    private func permission(_ title: String, granted: Bool, pane: String) -> some View {
        SettingsRow(title: title, detail: granted ? "Allowed" : "Not allowed yet") {
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(FocusMode.bloom.palette.deep)
            } else {
                Button("Open Settings") { Privacy.open(pane) }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
            }
        }
    }
}

enum Privacy {
    static func open(_ anchor: String) {
        let base = anchor == "Notifications" ? "x-apple.systempreferences:com.apple.Notifications-Settings.extension" : "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        if let url = URL(string: base) {
            NSWorkspace.shared.open(url)
        }
    }
}
