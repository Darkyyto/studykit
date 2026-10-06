import SwiftUI

struct SettingsView: View {
    @AppStorage(Preference.homeAirport) private var homeCode = Airport.fallback.code
    @AppStorage(Preference.transcriptionLocale) private var localeIdentifier = ""
    @AppStorage(Preference.showsMenuBarExtra) private var showsMenuBarExtra = true
    @State private var locales: [Locale] = []
    @AppStorage(Preference.persona) private var persona = Persona.personal
    @AppStorage(Preference.name) private var name = ""
    @AppStorage(Preference.hasOnboarded) private var hasOnboarded = true
    @AppStorage(Preference.isReplayingOnboarding) private var isReplayingOnboarding = false
    @AppStorage(Preference.sideNotch) private var sideNotch = IslandController.Presence.activity.rawValue
    @AppStorage(Preference.soundscapeVolume) private var soundscapeVolume = 0.55
    @Environment(Soundscape.self) private var soundscape
    @Environment(Updater.self) private var updater
    @State private var checksForUpdates = true

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image("Logo")
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 52, height: 52)
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FocusKit")
                            .font(.rounded(17, weight: .bold))
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") · Free and open source")
                            .font(.rounded(12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Toggle("Check for updates automatically", isOn: $checksForUpdates)
                    .onChange(of: checksForUpdates) { _, value in updater.checksAutomatically = value }
                LabeledContent(updateStatus) {
                    if let release = updater.available {
                        Button("Install \(release.version)…") { updater.presented = release }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Check Now") { Task { await updater.check(userInitiated: true) } }
                            .disabled(updater.state == .checking)
                    }
                }
                LabeledContent("Backups") {
                    Button("Show in Finder") {
                        try? FileManager.default.createDirectory(at: Backup.directory, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(Backup.directory)
                    }
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("An update replaces only the app. Your sessions, lectures and notes live in your library and stay where they are. A backup is saved before every update and once a day.")
                    .foregroundStyle(.secondary)
            }

            Section("Profile") {
                Picker("I use FocusKit as", selection: $persona) {
                    ForEach(Persona.allCases) { item in
                        Label(item.title, systemImage: item.symbol).tag(item)
                    }
                }
                TextField("Name", text: $name)
                LabeledContent("Onboarding") {
                    Button("Show Again") {
                        isReplayingOnboarding = true
                        hasOnboarded = false
                    }
                }
            }

            Section("Focus") {
                Picker("Home airport", selection: $homeCode) {
                    ForEach(Airport.catalog.sorted { $0.city < $1.city }) { airport in
                        Text(verbatim: "\(airport.city) (\(airport.code))").tag(airport.code)
                    }
                }
                Toggle("Show timer in the menu bar", isOn: $showsMenuBarExtra)
                Picker("Side notch", selection: $sideNotch) {
                    ForEach(IslandController.Presence.allCases) { item in
                        Text(item.title).tag(item.rawValue)
                    }
                }
            }

            Section {
                Toggle("Play a soundscape during sessions", isOn: Binding(
                    get: { soundscape.isEnabled },
                    set: { soundscape.isEnabled = $0 }
                ))
                LabeledContent("Volume") {
                    Slider(value: $soundscapeVolume, in: 0.1...1)
                        .frame(width: 180)
                        .onChange(of: soundscapeVolume) { soundscape.applyVolume() }
                }
                .disabled(!soundscape.isEnabled)
            } header: {
                Text("Sound")
            } footer: {
                Text("Generated live on this Mac: cabin hum for Flight, waves for Tide, deep space for Orbit, soft rain for Bloom and a breeze during breaks. The side notch also shows what is playing in Spotify or Music.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Language", selection: $localeIdentifier) {
                    Text("System (\(Locale.preferredSpeech.localizedName))").tag("")
                    ForEach(locales, id: \.identifier) { locale in
                        Text(locale.localizedName).tag(locale.identifier)
                    }
                }
            } header: {
                Text("Transcription")
            } footer: {
                Text("Speech is recognized on this Mac. macOS downloads each language model the first time you use it.")
                    .foregroundStyle(.secondary)
            }

            Section("Data") {
                LabeledContent("Library") {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Library.Location.standard.database])
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .task { locales = await Transcription.supportedLocales() }
        .onAppear { checksForUpdates = updater.checksAutomatically }
    }

    private var updateStatus: String {
        switch updater.state {
        case .checking: "Checking…"
        case .upToDate: "FocusKit is up to date"
        case .available(let release): "Version \(release.version) is available"
        case .downloading(let fraction): "Downloading… \(Int(fraction * 100))%"
        case .ready: "Downloaded and ready to install"
        case .failed(let message): message
        case .idle: "Version \(Updater.currentVersion)"
        }
    }
}
