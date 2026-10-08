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

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 14) {
                    if showsGreeting {
                        greeting(at: context.date)
                    }
                    HStack(spacing: 12) {
                        if showsSession, engine.isActive, let plan = engine.plan {
                            session(plan, at: context.date)
                        }
                        if showsBattery, let battery = DeviceWatcher.batteryState() {
                            batteryWidget(battery)
                        }
                        if showsAudio, let device = DeviceWatcher.bluetoothOutputs().values.sorted().first {
                            audioWidget(device)
                        }
                        if showsCalendar, calendar.access == .granted, let event = calendar.upcoming.first {
                            eventWidget(event, at: context.date)
                        }
                        if showsMusic, nowPlaying.hasTrack {
                            musicWidget
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, proxy.size.height * 0.36)
                .frame(maxHeight: .infinity, alignment: .top)
                .opacity(lockScreen.isShowing ? 1 : 0)
                .scaleEffect(lockScreen.isShowing ? 1 : 0.96)
                .animation(.spring(response: 0.6, dampingFraction: 0.9), value: lockScreen.isShowing)
            }
        }
        .foregroundStyle(.white)
        .onChange(of: lockScreen.isShowing) { _, showing in
            if showing { calendar.refresh() }
        }
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
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
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
            Smiley(palette: mode.palette, asleep: asleep)
                .frame(width: 50, height: 50)
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
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
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

struct Smiley: View {
    let palette: ModePalette
    let asleep: Bool

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: 0xFFD27A), Color(hex: 0xFF9F5A)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay {
                        Circle()
                            .fill(RadialGradient(colors: [.white.opacity(0.55), .clear], center: UnitPoint(x: 0.3, y: 0.25), startRadius: 0, endRadius: side * 0.5))
                    }
                    .shadow(color: Color(hex: 0xFF9F5A).opacity(0.45), radius: side * 0.18, y: side * 0.06)
                HStack(spacing: side * 0.42) {
                    Ellipse().fill(Color(hex: 0xFF6F8A).opacity(0.45))
                    Ellipse().fill(Color(hex: 0xFF6F8A).opacity(0.45))
                }
                .frame(width: side * 0.78, height: side * 0.1)
                .offset(y: side * 0.1)
                eyes(side: side)
                    .offset(y: -side * 0.06)
                Smile()
                    .stroke(Color(hex: 0x4A2A12), style: StrokeStyle(lineWidth: side * 0.06, lineCap: .round))
                    .frame(width: side * (asleep ? 0.18 : 0.34), height: side * (asleep ? 0.06 : 0.14))
                    .offset(y: side * 0.2)
            }
            .frame(width: side, height: side)
            .keyframeAnimator(initialValue: 0.0, repeating: true) { content, bob in
                content.offset(y: bob * side * 0.03)
            } keyframes: { _ in
                CubicKeyframe(1, duration: 1.6)
                CubicKeyframe(0, duration: 1.6)
            }
        }
    }

    @ViewBuilder
    private func eyes(side: CGFloat) -> some View {
        if asleep {
            HStack(spacing: side * 0.22) {
                ClosedEye().stroke(Color(hex: 0x4A2A12), style: StrokeStyle(lineWidth: side * 0.05, lineCap: .round))
                ClosedEye().stroke(Color(hex: 0x4A2A12), style: StrokeStyle(lineWidth: side * 0.05, lineCap: .round))
            }
            .frame(width: side * 0.46, height: side * 0.07)
        } else {
            HStack(spacing: side * 0.22) {
                Capsule().fill(Color(hex: 0x4A2A12))
                Capsule().fill(Color(hex: 0x4A2A12))
            }
            .frame(width: side * 0.3, height: side * 0.18)
            .keyframeAnimator(initialValue: 1.0, repeating: true) { content, scale in
                content.scaleEffect(x: 1, y: scale)
            } keyframes: { _ in
                LinearKeyframe(1, duration: 3.6)
                CubicKeyframe(0.1, duration: 0.08)
                CubicKeyframe(1, duration: 0.12)
            }
        }
    }
}

private struct Smile: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY * 2 - rect.minY))
        return path
    }
}

private struct ClosedEye: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}
