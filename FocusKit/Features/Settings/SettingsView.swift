import AVFoundation
import EventKit
import SwiftUI
import UserNotifications

struct SettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case profile, focus, notch, lockScreen, sound, transcription, updates, privacy

        static var visible: [Pane] {
            allCases.filter { $0 != .lockScreen || LockScreen.isSupported }
        }

        var id: String { rawValue }

        var title: String {
            switch self {
            case .profile: "Profile"
            case .focus: "Focus"
            case .notch: "Notch"
            case .lockScreen: "Lock Screen"
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
            case .lockScreen: "lock.fill"
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
            case .notch: Color(hex: 0x3A3A3C)
            case .lockScreen: FocusMode.tide.palette.deep
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
                    HStack(spacing: 10) {
                        Image(systemName: pane.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(pane.tint.gradient, in: .rect(cornerRadius: 8, style: .continuous))
                        Text(pane.title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Palette.ink)
                    }
                    Group {
                        switch pane {
                        case .profile: ProfilePane()
                        case .focus: FocusPane()
                        case .notch: NotchPane()
                        case .lockScreen: LockScreenPane()
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
        .onAppear { clearFocus(in: NSApp.keyWindow) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            clearFocus(in: notification.object as? NSWindow)
        }
        .onChange(of: pane) { clearFocus(in: NSApp.keyWindow) }
    }

    private func clearFocus(in window: NSWindow?) {
        guard let window, window.title.localizedStandardContains("Settings") else { return }
        DispatchQueue.main.async {
            if window.firstResponder is NSText {
                window.makeFirstResponder(nil)
            }
        }
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
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Palette.ink)
                    Text("Version \(Updater.currentVersion)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 16)

            ForEach(Pane.visible) { item in
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
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 34)
                    .background {
                        if pane == item {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Palette.surface)
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
        .background(Palette.surface, in: .rect(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        }
    }
}

struct SettingsRow<Trailing: View>: View {
    let title: String
    var detail: String?
    var showsDivider = true
    var symbol: String?
    var tint: Color = Color(hex: 0x8E8E93)
    @ViewBuilder let trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(tint.gradient, in: .rect(cornerRadius: 7, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                trailing
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            if showsDivider {
                Divider()
                    .padding(.leading, symbol == nil ? 14 : 52)
            }
        }
    }
}

private struct Footnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
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
    @AppStorage(Appearance.key) private var appearance = Appearance.system

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
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Palette.ink)
                            Text(item.pitch)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Palette.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
                        .background(Palette.surface, in: .rect(cornerRadius: 18))
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
            HStack(spacing: 10) {
                ForEach(Appearance.allCases) { item in
                    let isSelected = appearance == item
                    Button {
                        withAnimation(Motion.standard) { appearance = item }
                        item.apply()
                    } label: {
                        VStack(spacing: 10) {
                            AppearancePreview(appearance: item)
                                .frame(height: 64)
                            Text(item.title)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(Palette.surface, in: .rect(cornerRadius: 16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(FocusMode.flight.palette.deep, lineWidth: 2)
                                .opacity(isSelected ? 1 : 0)
                        }
                        .contentShape(.rect(cornerRadius: 16))
                    }
                    .buttonStyle(.pressable)
                    .help(item == .system ? "Follow your Mac's appearance" : "Always \(item.title.lowercased())")
                }
            }
            SettingsCard {
                SettingsRow(title: "Your name", detail: "Used in greetings.", symbol: "person.fill", tint: FocusMode.orbit.palette.deep) {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)

                }
                SettingsRow(title: "Setup", detail: "Walk through the welcome screens again.", showsDivider: false, symbol: "arrow.counterclockwise", tint: Color(hex: 0x8E8E93)) {
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

private struct AppearancePreview: View {
    let appearance: Appearance

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                switch appearance {
                case .light: window(dark: false)
                case .dark: window(dark: true)
                case .system:
                    window(dark: false)
                    window(dark: true)
                        .mask(alignment: .trailing) {
                            Rectangle().frame(width: proxy.size.width / 2)
                        }
                }
            }
        }
        .clipShape(.rect(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        }
    }

    private func window(dark: Bool) -> some View {
        let background = dark ? Color(hex: 0x161618) : Color(hex: 0xF6F4F1)
        let card = dark ? Color(hex: 0x2A2A2F) : .white
        let line = dark ? Color(hex: 0x4A4A52) : Color(hex: 0xDAD8DE)
        return ZStack(alignment: .topLeading) {
            background
            LinearGradient(colors: [FocusMode.flight.palette.mid.opacity(dark ? 0.25 : 0.45), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 5) {
                Capsule().fill(FocusMode.flight.palette.deep).frame(width: 26, height: 5)
                RoundedRectangle(cornerRadius: 4)
                    .fill(card)
                    .frame(height: 26)
                    .overlay(alignment: .leading) {
                        VStack(alignment: .leading, spacing: 3) {
                            Capsule().fill(line).frame(width: 30, height: 3)
                            Capsule().fill(line).frame(width: 18, height: 3)
                        }
                        .padding(.leading, 6)
                    }
            }
            .padding(9)
        }
    }
}

private struct LockScreenPane: View {
    @AppStorage(LockScreen.enabledKey) private var enabled = true
    @AppStorage(LockScreen.greetingKey) private var greeting = true
    @AppStorage(LockScreen.sessionKey) private var session = true
    @AppStorage(LockScreen.batteryKey) private var battery = true
    @AppStorage(LockScreen.audioKey) private var audio = true
    @AppStorage(LockScreen.calendarKey) private var calendar = true
    @AppStorage(LockScreen.musicKey) private var music = true
    @AppStorage(LockScreen.styleKey) private var style = LockScreen.Style.glass

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard {
                SettingsRow(title: "Lock Screen widgets", detail: "A greeting, your session and what matters right now, on top of the lock screen.", symbol: "lock.fill", tint: FocusMode.tide.palette.deep) {
                    Toggle("", isOn: $enabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsRow(title: "Preview", detail: "Show the widgets for a few seconds without locking your Mac.", showsDivider: false, symbol: "eye.fill", tint: Color(hex: 0x0A84FF)) {
                    Button("Preview") {
                        NotificationCenter.default.post(name: LockScreen.previewNotification, object: nil)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                }
            }
            if enabled {
                SettingsCard {
                    row("Greeting", detail: "A friendly face with how long you focused today.", symbol: "face.smiling.inverse", tint: Color(hex: 0xFF9F0A), isOn: $greeting)
                    row("Focus session", detail: "Time left and progress while a session runs.", symbol: "timer", tint: FocusMode.orbit.palette.deep, isOn: $session)
                    row("Battery", detail: "Charge level and charging.", symbol: "bolt.fill", tint: Color(hex: 0x34C759), isOn: $battery)
                    row("AirPods and headphones", detail: "What's connected right now.", symbol: "headphones", tint: Color(hex: 0x0A84FF), isOn: $audio)
                    row("Next event", detail: "The next thing in your calendar today.", symbol: "calendar", tint: Color(hex: 0xFF453A), isOn: $calendar)
                    row("Now Playing", detail: "The song playing in Spotify or Music.", symbol: "play.fill", tint: Color(hex: 0xFF2D55), isOn: $music, last: true)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                HStack(spacing: 10) {
                    ForEach(LockScreen.Style.allCases) { item in
                        let isSelected = style == item
                        Button {
                            withAnimation(Motion.quick) { style = item }
                        } label: {
                            VStack(spacing: 10) {
                                ZStack {
                                    LinearGradient(colors: [Color(hex: 0x3A4A7A), Color(hex: 0x8A6A9A)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    Capsule()
                                        .fill(.white.opacity(item == .glass ? 0.32 : 0.1))
                                        .overlay(Capsule().strokeBorder(.white.opacity(item == .glass ? 0.35 : 0.5), lineWidth: 1))
                                        .frame(width: 120, height: 26)
                                }
                                .frame(height: 64)
                                .clipShape(.rect(cornerRadius: 10))
                                Text(item.title)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(Palette.ink)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity)
                            .background(Palette.surface, in: .rect(cornerRadius: 16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(FocusMode.tide.palette.deep, lineWidth: 2)
                                    .opacity(isSelected ? 1 : 0)
                            }
                            .contentShape(.rect(cornerRadius: 16))
                        }
                        .buttonStyle(.pressable)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Footnote(text: "The widgets never take clicks, so the password field always works. They disappear the moment you unlock.")
        }
        .animation(Motion.standard, value: enabled)
    }

    private func row(_ title: String, detail: String, symbol: String, tint: Color, isOn: Binding<Bool>, last: Bool = false) -> some View {
        SettingsRow(title: title, detail: detail, showsDivider: !last, symbol: symbol, tint: tint) {
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

private struct FocusPane: View {
    @AppStorage(Preference.homeAirport) private var homeCode = Airport.fallback.code
    @AppStorage(Preference.showsMenuBarExtra) private var showsMenuBarExtra = true
    @AppStorage(Preference.keepsRunning) private var keepsRunning = true
    @AppStorage("rounds") private var rounds = 1
    @AppStorage("breakMinutes") private var breakMinutes = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsCard {
                SettingsRow(title: "Home airport", detail: "Where Flight sessions take off.", symbol: "airplane", tint: FocusMode.flight.palette.deep) {
                    Picker("Home airport", selection: $homeCode) {
                        ForEach(Airport.catalog.sorted { $0.city < $1.city }) { airport in
                            Text(verbatim: "\(airport.city) · \(airport.code)").tag(airport.code)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsRow(title: "Rounds", detail: "How many focus blocks a session has by default.", symbol: "repeat", tint: FocusMode.orbit.palette.deep) {
                    Stepper("\(rounds)", value: $rounds, in: 1...8)
                        .font(.numeric(14, weight: .semibold))
                        .fixedSize()
                }
                SettingsRow(title: "Break", detail: "Time between rounds.", symbol: "cup.and.saucer.fill", tint: Palette.rest.deep) {
                    Stepper("\(breakMinutes) min", value: $breakMinutes, in: 5...30, step: 5)
                        .font(.numeric(14, weight: .semibold))
                        .fixedSize()
                }
                SettingsRow(title: "Timer in the menu bar", detail: "Shows the time left while a session runs.", symbol: "menubar.rectangle", tint: Color(hex: 0x8E8E93)) {
                    Toggle("", isOn: $showsMenuBarExtra)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsRow(title: "Keep running in the background", detail: "Closing the window leaves FocusKit in the menu bar and the notch, out of the Dock.", showsDivider: false, symbol: "moon.fill", tint: Color(hex: 0x5E5CE6)) {
                    Toggle("", isOn: $keepsRunning)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
        }
    }
}

private struct NotchPane: View {
    @AppStorage(Preference.sideNotch) private var presence = IslandController.Presence.activity.rawValue
    @AppStorage(SystemHUD.enabledKey) private var showsIndicators = true
    @AppStorage(SystemHUD.replaceKey) private var replacesIndicators = false
    @AppStorage(FileTray.enabledKey) private var showsTray = true
    @AppStorage(ClipboardHistory.enabledKey) private var keepsClipboard = false
    @AppStorage(SystemHUD.automaticBrightnessKey) private var showsAutomaticBrightness = false
    @AppStorage(IslandController.offsetKey) private var notchOffset = 0.0
    @AppStorage(DeviceWatcher.audioKey) private var noticesAudio = true
    @AppStorage(DeviceWatcher.capsLockKey) private var noticesCapsLock = true
    @AppStorage(DeviceWatcher.batteryKey) private var noticesBattery = true
    @AppStorage(IslandController.heightKey) private var notchHeight = 0.0
    private let hasNotch = NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }
    @Environment(SystemHUD.self) private var systemHUD
    @State private var hasAccessibility = SystemHUD.hasAccessibility
    @State private var calendarAccess = EKEventStore.authorizationStatus(for: .event)

    private func alignmentStepper(value: Binding<Double>) -> some View {
        HStack(spacing: 10) {
            Text(value.wrappedValue == 0 ? "0 pt" : "\(value.wrappedValue > 0 ? "+" : "")\(value.wrappedValue.formatted(.number.precision(.fractionLength(1)))) pt")
                .font(.numeric(13, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)
            Stepper("", value: value, in: -6...6, step: 0.5)
                .labelsHidden()
                .onChange(of: value.wrappedValue) {
                    NotificationCenter.default.post(name: IslandController.previewNotification, object: nil)
                }
        }
    }

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
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                                .multilineTextAlignment(.center)
                                .frame(height: 32)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(Palette.surface, in: .rect(cornerRadius: 16))
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
            if hasNotch {
                SettingsCard {
                    SettingsRow(title: "Horizontal position", detail: "Nudge the notch so its edges line up with your Mac's camera housing.", symbol: "arrow.left.and.right", tint: Color(hex: 0x8E8E93)) {
                        alignmentStepper(value: $notchOffset)
                    }
                    SettingsRow(title: "Height", detail: "Make the notch a little taller or shorter.", showsDivider: notchOffset == 0 && notchHeight == 0 ? false : true, symbol: "arrow.up.and.down", tint: Color(hex: 0x8E8E93)) {
                        alignmentStepper(value: $notchHeight)
                    }
                    if notchOffset != 0 || notchHeight != 0 {
                        SettingsRow(title: "Alignment", detail: "Go back to the size and position macOS reports.", showsDivider: false, symbol: "arrow.uturn.backward", tint: Color(hex: 0x8E8E93)) {
                            Button("Reset") {
                                notchOffset = 0
                                notchHeight = 0
                                NotificationCenter.default.post(name: IslandController.previewNotification, object: nil)
                            }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.capsule)
                        }
                    }
                }
            }
            SettingsCard {
                SettingsRow(title: "Volume, brightness and charging", detail: "Show them in the notch when they change.", symbol: "speaker.wave.2.fill", tint: Color(hex: 0xFF9F0A)) {
                    Toggle("", isOn: $showsIndicators)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .onChange(of: showsIndicators) { systemHUD.updateKeyTap() }
                }
                SettingsRow(title: "Automatic brightness changes", detail: "Also show when your Mac adjusts the brightness to the light around you.", symbol: "sun.max.fill", tint: Color(hex: 0xF5B800)) {
                    Toggle("", isOn: $showsAutomaticBrightness)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(!showsIndicators)
                }
                SettingsRow(title: "Replace the macOS indicators", detail: replacesIndicators && !hasAccessibility ? "Allow FocusKit under Accessibility so it can handle the volume and brightness keys." : "The keys go through FocusKit and only the notch appears.", showsDivider: replacesIndicators && !hasAccessibility, symbol: "switch.2", tint: Color(hex: 0x8E8E93)) {
                    Toggle("", isOn: $replacesIndicators)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(!showsIndicators)
                        .onChange(of: replacesIndicators) { _, on in
                            systemHUD.updateKeyTap(prompt: on)
                            hasAccessibility = SystemHUD.hasAccessibility
                        }
                }
                if replacesIndicators, !hasAccessibility {
                    SettingsRow(title: "Accessibility", detail: "Turn on FocusKit in the list, then come back.", showsDivider: false, symbol: "accessibility", tint: Color(hex: 0x0A84FF)) {
                        Button("Open Settings") { Privacy.open("Privacy_Accessibility") }
                            .buttonStyle(.glassProminent)
                            .buttonBorderShape(.capsule)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                hasAccessibility = SystemHUD.hasAccessibility
                systemHUD.updateKeyTap()
            }
            SettingsCard {
                SettingsRow(title: "AirPods and speakers", detail: "Show when headphones or a Bluetooth speaker connect or disconnect.", symbol: "airpodspro", tint: Color(hex: 0x0A84FF)) {
                    Toggle("", isOn: $noticesAudio)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsRow(title: "Caps Lock", detail: "Show when Caps Lock turns on or off.", symbol: "capslock.fill", tint: Color(hex: 0x34C759)) {
                    Toggle("", isOn: $noticesCapsLock)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsRow(title: "Low battery", detail: "Show a reminder at 20% and 10% while on battery.", showsDivider: false, symbol: "battery.25percent", tint: Color(hex: 0xFF453A)) {
                    Toggle("", isOn: $noticesBattery)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
            SettingsCard {
                SettingsRow(title: "File tray", detail: "Drag files onto the notch to keep them close, then drag them out, share or AirDrop them.", symbol: "tray.fill", tint: FocusMode.tide.palette.deep) {
                    Toggle("", isOn: $showsTray)
                        .toggleStyle(.switch)
                        .labelsHidden()
                    SettingsRow(title: "Clipboard history", detail: "Keep the last 40 things you copy in the notch. Passwords are never kept, and the history is cleared when FocusKit quits.", showsDivider: false, symbol: "list.clipboard", tint: Color(hex: 0x8E8E93)) {
                    Toggle("", isOn: $keepsClipboard)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
            }
            SettingsCard {
                SettingsRow(title: "Calendar", detail: calendarAccess == .fullAccess ? "Connected. Events from all your calendars appear in the notch." : "Show your classes and meetings in the notch.", showsDivider: false, symbol: "calendar", tint: Color(hex: 0xFF453A)) {
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
        .animation(Motion.standard, value: replacesIndicators)
        .animation(Motion.standard, value: hasAccessibility)
        .animation(Motion.standard, value: showsIndicators)
        .animation(Motion.standard, value: notchOffset != 0 || notchHeight != 0)
        .animation(Motion.standard, value: calendarAccess)
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
                SettingsRow(title: "Soundscape", detail: "Play a sound generated live during sessions.", symbol: "leaf.fill", tint: FocusMode.bloom.palette.deep) {
                    Toggle("", isOn: Binding(get: { soundscape.isEnabled }, set: { soundscape.isEnabled = $0 }))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsRow(title: "Volume", showsDivider: false, symbol: "speaker.wave.2.fill", tint: Color(hex: 0x8E8E93)) {
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
                SettingsRow(title: "Language", detail: "The language spoken in your lectures and meetings.", symbol: "globe", tint: Color(hex: 0x0A84FF)) {
                    Picker("Language", selection: $localeIdentifier) {
                        Text("System (\(Locale.preferredSpeech.localizedName))").tag("")
                        ForEach(locales, id: \.identifier) { locale in
                            Text(locale.localizedName).tag(locale.identifier)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsRow(title: "Speech model", detail: failure ?? (installed == true ? "Downloaded. Transcription works offline." : "Downloaded once, then everything runs on this Mac."), showsDivider: false, symbol: "waveform", tint: FocusMode.tide.palette.deep) {
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
        .animation(Motion.standard, value: installing)
        .animation(Motion.standard, value: installed)
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
                SettingsRow(title: "FocusKit \(Updater.currentVersion)", detail: status, symbol: "arrow.down.circle.fill", tint: FocusMode.flight.palette.deep) {
                    if case .downloading(let fraction) = updater.state {
                        ProgressView(value: fraction)
                            .progressViewStyle(.linear)
                            .frame(width: 140)
                    } else if updater.needsAppManagement {
                        Button("Open App Management") { Privacy.open("Privacy_AppBundles") }
                            .buttonStyle(.glassProminent)
                            .buttonBorderShape(.capsule)
                    } else if case .ready(let url) = updater.state {
                        Button(url.pathExtension == "app" ? "Restart and Update" : "Install and Quit") { updater.openInstaller(url) }
                            .buttonStyle(.glassProminent)
                            .buttonBorderShape(.capsule)
                    } else if let release = updater.available {
                        Button("Download \(release.version)") { updater.install(release) }
                            .buttonStyle(.glassProminent)
                            .buttonBorderShape(.capsule)
                    } else {
                        Button("Check Now") { Task { await updater.check(userInitiated: true) } }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.capsule)
                            .disabled(updater.state == .checking)
                    }
                }
                SettingsRow(title: "Check automatically", detail: "Every time FocusKit opens.", symbol: "arrow.triangle.2.circlepath", tint: Color(hex: 0x34C759)) {
                    Toggle("", isOn: $checksAutomatically)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .onChange(of: checksAutomatically) { _, value in updater.checksAutomatically = value }
                }
                SettingsRow(title: "Backups", detail: "Saved before every update and once a day.", showsDivider: false, symbol: "externaldrive.fill", tint: Color(hex: 0x8E8E93)) {
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
        .animation(Motion.standard, value: updater.state)
        .onAppear { checksAutomatically = updater.checksAutomatically }
    }

    private var status: String {
        switch updater.state {
        case .checking: "Checking…"
        case .upToDate: "You have the latest version."
        case .available(let release): "Version \(release.version) is available."
        case .downloading(let fraction): "Downloading… \(Int(fraction * 100))%"
        case .ready(let url) where updater.needsAppManagement: url.pathExtension == "app" ? "Turn on FocusKit under App Management, then come back." : "Downloaded."
        case .ready(let url): url.pathExtension == "app" ? "Ready. FocusKit restarts with the new version." : "Downloaded. FocusKit quits, then drag it onto Applications and choose Replace."
        case .failed(let message): message
        case .idle: "Free for personal use."
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
                SettingsRow(title: "App updates", detail: "Lets FocusKit replace itself when you install an update.", symbol: "arrow.down.app.fill", tint: Color(hex: 0x0A84FF)) {
                    Button("Open Settings") { Privacy.open("Privacy_AppBundles") }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                }
                SettingsRow(title: "Music control", detail: "Spotify and Music, from the notch.", showsDivider: false, symbol: "music.note", tint: Color(hex: 0xFF2D55)) {
                    Button("Open Settings") { Privacy.open("Privacy_Automation") }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                }
            }
            SettingsCard {
                SettingsRow(title: "Library", detail: "Sessions, lectures, notes and PDFs, stored only on this Mac.", showsDivider: false, symbol: "books.vertical.fill", tint: Color(hex: 0xFF9F0A)) {
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
