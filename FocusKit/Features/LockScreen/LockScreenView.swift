import SwiftUI

struct LockScreenView: View {
    let lockScreen: LockScreen
    let calendar: CalendarStore
    @Environment(FocusEngine.self) private var engine
    @Environment(Library.self) private var library
    @Environment(NowPlaying.self) private var nowPlaying
    @AppStorage(Preference.name) private var name = ""
    @AppStorage(Preference.focusMode) private var mode = FocusMode.flight
    @AppStorage(LockScreen.greetingKey) private var showsGreeting = true
    @AppStorage(LockScreen.batteryKey) private var showsBattery = true
    @AppStorage(LockScreen.audioKey) private var showsAudio = true
    @AppStorage(LockScreen.sessionKey) private var showsSession = true
    @AppStorage(LockScreen.calendarKey) private var showsCalendar = true
    @AppStorage(LockScreen.musicKey) private var showsMusic = true
    @AppStorage(LockScreen.styleKey) private var style = LockScreen.Style.glass
    @AppStorage(LockScreen.enabledKey) private var showsWidgets = true
    @AppStorage(LockScreen.notchKey) private var showsLockInNotch = true

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                if lockScreen.isShowing {
                    widgets
                        .frame(maxWidth: .infinity)
                        .padding(.top, proxy.size.height * 0.36)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.spring(response: 0.6, dampingFraction: 0.9), value: lockScreen.isShowing)
            .overlay(alignment: .top) {
                if showsLockInNotch, let notch = Self.notch {
                    LockedNotch(notch: notch, isShowing: lockScreen.isShowing)
                }
            }
        }
        .foregroundStyle(.white)
        .onChange(of: lockScreen.isShowing) { _, showing in
            if showing { calendar.refresh() }
        }
    }

    private var widgets: some View {
        VStack(spacing: 14) {
            if showsWidgets, showsGreeting {
                TimelineView(.everyMinute) { context in
                    greeting(at: context.date)
                }
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                HStack(spacing: 12) {
                    if showsWidgets, showsSession, engine.isActive, let plan = engine.plan {
                        TimelineView(.periodic(from: .now, by: 1)) { tick in
                            session(plan, at: tick.date)
                        }
                    }
                    if showsWidgets, showsBattery, let battery = DeviceWatcher.batteryState() {
                        batteryWidget(battery)
                    }
                    if showsWidgets, showsAudio, let device = DeviceWatcher.bluetoothOutputs().values.sorted().first {
                        audioWidget(device)
                    }
                    if showsWidgets, showsCalendar, calendar.access == .granted, let event = calendar.upcoming.first {
                        eventWidget(event, at: context.date)
                    }
                    if showsWidgets, showsMusic, nowPlaying.hasTrack {
                        musicWidget
                    }
                }
            }
        }
    }

    private static var notch: CGSize? {
        guard let screen = NSScreen.screens.first, screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return nil }
        return CGSize(width: right.minX - left.maxX, height: screen.safeAreaInsets.top)
    }

    private var glass: Glass {
        style == .glass ? .regular : .clear
    }

    private func card<Content: View>(width: CGFloat? = nil, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            content()
        }
        .padding(.horizontal, 16)
        .frame(width: width, height: 72)
        .glassEffect(glass, in: .rect(cornerRadius: 24, style: .continuous))
    }

    private func label(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.rounded(15, weight: .bold))
                .lineLimit(1)
            Text(detail)
                .font(.rounded(12, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
    }

    private func greeting(at date: Date) -> some View {
        let hour = Calendar.current.component(.hour, from: date)
        let asleep = hour >= 23 || hour < 6
        let part = hour < 5 ? "Good night" : hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        let today = library.focusedTime(in: Calendar.current.dateInterval(of: .day, for: date))
        let detail: String
        if engine.isActive {
            detail = "You're in the middle of a session"
        } else if asleep {
            detail = today > 0 ? "\(today.compactDuration) focused today. Sleep well" : "Time to rest"
        } else {
            detail = today > 0 ? "\(today.compactDuration) focused today" : "Ready when you are"
        }
        return HStack(spacing: 14) {
            Mascot(palette: mode.palette, mood: engine.isActive ? .focused : asleep ? .asleep : .awake)
                .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? part : "\(part), \(name)")
                    .font(.rounded(18, weight: .bold))
                Text(detail)
                    .font(.rounded(13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .lineLimit(1)
        }
        .padding(.leading, 12)
        .padding(.trailing, 22)
        .frame(height: 74)
        .glassEffect(glass, in: .capsule)
    }

    private func session(_ plan: FocusPlan, at date: Date) -> some View {
        let tint = engine.isResting ? Palette.rest.mid : plan.mode.palette.mid
        let progress = engine.isResting ? engine.segmentProgress(at: date) : engine.focusProgress(at: date)
        return card {
            ZStack {
                Circle().stroke(.white.opacity(0.2), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: engine.isResting ? "cup.and.saucer.fill" : plan.mode.symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 40, height: 40)
            label(engine.remaining(at: date).clock, engine.isPaused ? "Paused" : engine.isResting ? "Break" : plan.mode.title)
                .monospacedDigit()
        }
    }

    private func batteryWidget(_ battery: (level: Int, charging: Bool)) -> some View {
        let tint: Color = battery.charging ? Color(hex: 0x34C759) : battery.level <= 20 ? Palette.record : .white
        return card {
            ZStack {
                Circle().stroke(.white.opacity(0.2), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: Double(battery.level) / 100)
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: battery.charging ? "bolt.fill" : "battery.100percent")
                    .font(.system(size: battery.charging ? 13 : 11, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 40, height: 40)
            label("\(battery.level)%", battery.charging ? "Charging" : "Battery")
        }
    }

    private func audioWidget(_ device: String) -> some View {
        card {
            Image(systemName: DeviceWatcher.symbol(for: device))
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.14), in: .circle)
            label(DeviceWatcher.shortName(device), "Connected")
        }
    }

    private func eventWidget(_ event: CalendarStore.Event, at date: Date) -> some View {
        let minutes = Int(event.start.timeIntervalSince(date) / 60)
        let when = event.start <= date ? "Now" : minutes < 60 ? "In \(max(1, minutes)) min" : event.start.formatted(date: .omitted, time: .shortened)
        return card(width: 230) {
            VStack(spacing: 0) {
                Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.rounded(9, weight: .bold))
                    .foregroundStyle(Palette.record)
                Text(date.formatted(.dateTime.day()))
                    .font(.numeric(18, weight: .bold))
            }
            .frame(width: 40, height: 40)
            .background(.white.opacity(0.14), in: .rect(cornerRadius: 11, style: .continuous))
            label(event.title, when)
            Spacer(minLength: 0)
        }
    }

    private var musicWidget: some View {
        card(width: 250) {
            Group {
                if let artwork = nowPlaying.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    nowPlaying.accent.opacity(0.4)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.system(size: 16, weight: .semibold))
                        }
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(.rect(cornerRadius: 10, style: .continuous))
            label(nowPlaying.title, nowPlaying.artist)
            Spacer(minLength: 0)
        }
    }
}

private struct LockedNotch: View {
    let notch: CGSize
    let isShowing: Bool
    private let wing: CGFloat = 40

    var body: some View {
        UnevenRoundedRectangle(bottomLeadingRadius: notch.height * 0.4, bottomTrailingRadius: notch.height * 0.4, style: .continuous)
            .fill(.black)
            .frame(width: notch.width + (isShowing ? wing * 2 : 0), height: notch.height)
            .overlay(alignment: .leading) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: wing)
                    .opacity(isShowing ? 1 : 0)
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: isShowing)
    }
}
