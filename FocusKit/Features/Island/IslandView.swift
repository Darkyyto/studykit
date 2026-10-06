import SwiftUI

struct IslandView: View {
    let controller: IslandController
    let calendar: CalendarStore
    let systemHUD: SystemHUD
    @Environment(FocusEngine.self) private var engine
    @Environment(VoiceRecorder.self) private var recorder
    @Environment(Library.self) private var library
    @Environment(NowPlaying.self) private var nowPlaying
    @Environment(Soundscape.self) private var soundscape
    @Environment(NoteEnhancer.self) private var enhancer
    @AppStorage(Preference.persona) private var persona = Persona.personal
    @AppStorage(Preference.focusMode) private var mode = FocusMode.flight
    @AppStorage(Preference.name) private var name = ""
    @AppStorage(Preference.homeAirport) private var homeCode = Airport.fallback.code
    @AppStorage("rounds") private var rounds = 1
    @AppStorage("breakMinutes") private var breakMinutes = 5
    @Namespace private var tabs

    private var soundscapeKind: Soundscape.Kind? {
        guard engine.isActive, !engine.isPaused, let plan = engine.plan else { return nil }
        return engine.isResting ? .breeze : Soundscape.Kind(mode: plan.mode)
    }

    var body: some View {
        let size = controller.size
        let radius = controller.bottomRadius
        let fillet = controller.fillet
        ZStack(alignment: .top) {
            Color.clear
            TopNotch(fillet: fillet, radius: radius)
                .fill(.black)
                .frame(width: size.width + fillet * 2, height: size.height)
                .overlay(alignment: .top) {
                    content
                        .frame(width: size.width, height: size.height, alignment: .top)
                        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius))
                }
                .shadow(color: .black.opacity(controller.shape == .expanded ? 0.35 : 0), radius: 20, y: 8)
                .opacity(controller.isVisible ? 1 : 0)
        }
        .frame(width: IslandController.canvas.width, height: IslandController.canvas.height)
        .environment(\.colorScheme, .dark)
        .onChange(of: engine.segmentIndex) { _, _ in announceSegment() }
        .onChange(of: engine.phase.isComplete) { _, done in
            if done { controller.announce("Complete", detail: completionText, symbol: "checkmark", tint: tint) }
            controller.refresh()
        }
        .onChange(of: engine.isActive) { _, _ in controller.refresh() }
        .onChange(of: recorder.isActive) { _, active in
            controller.refresh()
            if active { controller.announce("Recording", detail: "Listening", symbol: "waveform", tint: Palette.record) }
        }
        .onChange(of: nowPlaying.title) { _, title in
            guard !title.isEmpty, nowPlaying.isPlaying, !controller.isBusy else { return }
            controller.announce(title, detail: nowPlaying.artist, symbol: "music.note", tint: nowPlaying.accent)
        }
        .onChange(of: nowPlaying.isPlaying) { _, _ in controller.refresh() }
        .onChange(of: soundscapeKind, initial: true) { _, kind in soundscape.sync(kind: kind) }
        .onChange(of: soundscape.isEnabled) { _, _ in soundscape.sync(kind: soundscapeKind) }
        .onChange(of: systemHUD.event) { _, event in
            if event != nil { controller.showSystemHUD() }
        }
        .task(id: controller.tab) {
            if controller.tab == .calendar { await calendar.prepare() }
        }
        .onChange(of: controller.shape) { _, shape in
            if shape == .expanded { calendar.refresh() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch controller.shape {
        case .expanded:
            expanded
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top)).animation(.spring(response: 0.4, dampingFraction: 0.85).delay(0.05)),
                    removal: .opacity.animation(.easeOut(duration: 0.12))
                ))
        case .peek:
            peek
                .transition(.blurReplace.animation(.easeOut(duration: 0.18)))
        case .compact:
            compact
                .transition(.blurReplace.animation(.easeOut(duration: 0.18)))
        case .hud:
            hud
                .transition(.blurReplace.animation(.easeOut(duration: 0.16)))
        case .hidden:
            Color.clear
        }
    }

    private var expanded: some View {
        VStack(spacing: 0) {
            header
                .frame(height: controller.notch.height)
            Group {
                switch controller.tab {
                case .home: home
                case .music: musicTab
                case .calendar: calendarTab
                }
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(y: 6)),
                removal: .opacity
            ))
            .id(controller.tab)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 14)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.9), value: controller.tab)
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                tabButton(.home, symbol: "house.fill", help: "Home")
                tabButton(.music, symbol: "music.note", help: "Music")
                tabButton(.calendar, symbol: "calendar", help: "Calendar")
            }
            .padding(3)
            .background(.white.opacity(0.06), in: .capsule)
            .padding(.leading, 16)
            Spacer(minLength: max(controller.notch.width, 100))
            HStack(spacing: 10) {
                Text(Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.rounded(11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                iconButton("arrow.up.forward.app", help: "Open FocusKit", size: 24) { controller.openApp() }
            }
            .padding(.trailing, 16)
        }
    }

    private func tabButton(_ tab: IslandController.Tab, symbol: String, help: String) -> some View {
        let isSelected = controller.tab == tab
        return Button {
            controller.tab = tab
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.45))
                .frame(width: 30, height: 20)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(.white.opacity(0.16))
                            .matchedGeometryEffect(id: "tab", in: tabs)
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.pressable)
        .help(help)
    }

    private var home: some View {
        HStack(spacing: 10) {
            Group {
                if controller.isBusy {
                    sessionCard
                } else {
                    todayCard
                }
            }
            .frame(width: 270)

            Group {
                if nowPlaying.hasTrack {
                    musicCard
                } else {
                    agendaCard
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    private var todayCard: some View {
        let stats = JournalStats(sessions: library.sessions)
        let week = stats.lastSevenDays.map { $0.minutes.values.reduce(0, +) }
        let today = (week.last ?? 0) * 60
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(greeting)
                        .font(.rounded(11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                    Text(today > 0 ? today.compactDuration : "0 min")
                        .font(.numeric(25, weight: .bold))
                        .foregroundStyle(.white)
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                        Text(stats.streak > 0 ? "\(stats.streak) day streak" : "Focused today")
                    }
                    .font(.rounded(10.5, weight: .semibold))
                    .foregroundStyle(stats.streak > 0 ? Palette.rest.mid : .white.opacity(0.4))
                }
                Spacer(minLength: 0)
                WeekBars(minutes: week, tint: mode.palette.mid)
                    .frame(width: 74, height: 44)
                    .padding(.top, 4)
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                ForEach(FocusMode.allCases) { item in
                    ModeLauncher(mode: item, isCurrent: item == mode) { start(item) }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RadialGradient(colors: [mode.palette.deep.opacity(0.4), .clear], center: .topTrailing, startRadius: 0, endRadius: 240)
                .animation(.easeInOut(duration: 0.5), value: mode)
        }
        .notchCard()
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let part = hour < 5 ? "Good night" : hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        return name.isEmpty ? part : "\(part), \(name)"
    }

    private var sessionCard: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 8) {
                Label(caption, systemImage: symbol)
                    .font(.rounded(11, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(.black.opacity(0.35), in: .capsule)
                Spacer(minLength: 0)
                HStack(alignment: .center, spacing: 8) {
                    Text(time(at: context.date))
                        .font(.numeric(30, weight: .bold))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(countsDown: !recorder.isActive))
                        .animation(Motion.quick, value: time(at: context.date))
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                    Spacer(minLength: 0)
                    sessionControls
                }
                ProgressLine(value: sessionProgress(at: context.date), tint: .white)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                ZStack {
                    thumbnail
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.25), location: 0),
                            .init(color: .clear, location: 0.35),
                            .init(color: .black.opacity(0.7), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .notchCard()
        }
    }

    @ViewBuilder
    private var sessionControls: some View {
        HStack(spacing: 6) {
            if engine.isActive {
                iconButton("forward.end.fill", help: engine.isResting ? "Skip break" : "Skip round", size: 28) { engine.skip() }
                iconButton(engine.isPaused ? "play.fill" : "pause.fill", help: engine.isPaused ? "Resume" : "Pause", size: 34, highlighted: true) {
                    withAnimation(Motion.morph) { engine.togglePause() }
                }
                iconButton(soundscape.isEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill", help: soundscape.isEnabled ? "Mute soundscape" : "Play soundscape", size: 28) {
                    soundscape.isEnabled.toggle()
                }
            } else if recorder.isActive {
                iconButton("stop.fill", help: "Stop and save the recording", size: 34, highlighted: true) {
                    recorder.stopNow(engine: engine, enhancer: enhancer, persona: persona)
                }
            } else {
                iconButton("checkmark", help: "See summary", size: 34, highlighted: true) { controller.openApp() }
            }
        }
    }

    private var musicCard: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    artwork(size: 46, radius: 10)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(nowPlaying.title)
                            .font(.rounded(13, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(nowPlaying.artist)
                            .font(.rounded(11.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Equalizer(tint: nowPlaying.accent, isPlaying: nowPlaying.isPlaying)
                        .frame(width: 14, height: 14)
                }
                Spacer(minLength: 6)
                if nowPlaying.duration > 0 {
                    ProgressLine(value: nowPlaying.elapsed(at: context.date) / nowPlaying.duration, tint: .white.opacity(0.9))
                }
                Spacer(minLength: 6)
                playbackControls(small: 28, large: 34)
                    .frame(maxWidth: .infinity)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { ArtworkBackdrop(artwork: nowPlaying.artwork, accent: nowPlaying.accent) }
            .notchCard()
        }
    }

    private var agendaCard: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(context.date.formatted(date: .omitted, time: .shortened))
                        .font(.numeric(22, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        controller.tab = .calendar
                    } label: {
                        HStack(spacing: 3) {
                            Text(context.date.formatted(.dateTime.weekday(.wide)))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .font(.rounded(11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.pressable)
                    .help("Calendar")
                }
                switch calendar.access {
                case .granted:
                    if let next = calendar.upcoming.first {
                        NextEvent(event: next, now: context.date)
                        if calendar.upcoming.count > 1 {
                            let then = calendar.upcoming[1]
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(then.color)
                                    .frame(width: 5, height: 5)
                                Text(then.title)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(then.start.formatted(date: .omitted, time: .shortened))
                                    .font(.numeric(11, weight: .semibold))
                            }
                            .font(.rounded(11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.horizontal, 4)
                        }
                        Spacer(minLength: 0)
                    } else {
                        Spacer(minLength: 0)
                        HStack(spacing: 8) {
                            Image(systemName: Calendar.current.component(.hour, from: context.date) < 18 ? "sun.max.fill" : "moon.stars.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Palette.rest.mid)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Nothing else today")
                                    .font(.rounded(12.5, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text("Your calendar is clear")
                                    .font(.rounded(11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                        }
                        Spacer(minLength: 0)
                    }
                case .unknown:
                    connectCalendar(showsSymbol: false)
                case .denied:
                    deniedCalendar
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .notchCard()
        }
    }

    @ViewBuilder
    private var musicTab: some View {
        if nowPlaying.hasTrack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 18) {
                    artwork(size: 128, radius: 20)
                        .shadow(color: nowPlaying.accent.opacity(0.5), radius: 18, y: 8)
                        .scaleEffect(nowPlaying.isPlaying ? 1 : 0.94)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: nowPlaying.isPlaying)

                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 6) {
                            Equalizer(tint: nowPlaying.accent, isPlaying: nowPlaying.isPlaying)
                                .frame(width: 12, height: 11)
                            Text(nowPlaying.isPlaying ? "Playing on \(nowPlaying.player?.scriptName ?? "")" : "Paused")
                                .font(.rounded(10.5, weight: .bold))
                                .foregroundStyle(.white.opacity(0.7))
                            Spacer(minLength: 0)
                        }
                        Spacer(minLength: 6)
                        Text(nowPlaying.title)
                            .font(.rounded(19, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(nowPlaying.artist)
                            .font(.rounded(13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if nowPlaying.duration > 0 {
                            VStack(spacing: 4) {
                                ProgressLine(value: nowPlaying.elapsed(at: context.date) / nowPlaying.duration, tint: .white, height: 4)
                                HStack {
                                    Text(nowPlaying.elapsed(at: context.date).clock)
                                    Spacer()
                                    Text("-" + max(0, nowPlaying.duration - nowPlaying.elapsed(at: context.date)).clock)
                                }
                                .font(.numeric(10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        Spacer(minLength: 6)
                        playbackControls(small: 32, large: 42)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { ArtworkBackdrop(artwork: nowPlaying.artwork, accent: nowPlaying.accent) }
                .notchCard()
            }
        } else {
            HStack(spacing: 10) {
                ForEach([NowPlaying.Player.spotify, .music], id: \.self) { player in
                    PlayerLauncher(player: player) { nowPlaying.play(in: player) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func artwork(size: CGFloat, radius: CGFloat) -> some View {
        Button {
            nowPlaying.open()
        } label: {
            Group {
                if let artwork = nowPlaying.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        nowPlaying.accent.opacity(0.3)
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.3, weight: .semibold))
                            .foregroundStyle(nowPlaying.accent)
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
            }
        }
        .buttonStyle(.pressable)
        .help("Open \(nowPlaying.player?.scriptName ?? "player")")
    }

    private func playbackControls(small: CGFloat, large: CGFloat) -> some View {
        HStack(spacing: small * 0.5) {
            iconButton("backward.fill", help: "Previous", size: small) { nowPlaying.previous() }
            iconButton(nowPlaying.isPlaying ? "pause.fill" : "play.fill", help: nowPlaying.isPlaying ? "Pause" : "Play", size: large, highlighted: true) {
                nowPlaying.togglePlayback()
            }
            iconButton("forward.fill", help: "Next", size: small) { nowPlaying.next() }
        }
    }

    private var tint: Color {
        if recorder.isActive { return Palette.record }
        if engine.isResting { return Palette.rest.mid }
        return (engine.plan?.mode ?? mode).palette.mid
    }

    private var symbol: String {
        if recorder.isActive { return "waveform" }
        if engine.isResting { return "cup.and.saucer.fill" }
        if engine.phase.isComplete { return "checkmark" }
        return engine.plan?.mode.symbol ?? mode.symbol
    }

    @ViewBuilder
    private var hud: some View {
        if let event = systemHUD.event {
            HStack(spacing: 0) {
                HStack(spacing: 9) {
                    Image(systemName: hudSymbol(event))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 22)
                    Text(hudTitle(event))
                        .font(.rounded(13.5, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: IslandController.hudWing, alignment: .leading)
                .padding(.leading, 16)
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.16))
                            Capsule()
                                .fill(LinearGradient(colors: hudColors(event), startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(6, proxy.size.width * event.value))
                                .animation(.spring(response: 0.3, dampingFraction: 0.9), value: event.value)
                        }
                    }
                    .frame(height: 6)
                    Text("\(Int((event.value * 100).rounded()))")
                        .font(.numeric(13, weight: .bold))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(value: event.value))
                        .animation(Motion.quick, value: event.value)
                        .frame(width: 28, alignment: .trailing)
                }
                .frame(width: IslandController.hudWing - 10)
                .padding(.trailing, 16)
            }
            .frame(height: controller.notch.height)
        }
    }

    private func hudSymbol(_ event: SystemHUD.Event) -> String {
        switch event.kind {
        case .volume:
            if event.isMuted || event.value == 0 { return "speaker.slash.fill" }
            return event.value < 0.34 ? "speaker.wave.1.fill" : event.value < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        case .brightness:
            return event.value < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .battery:
            return event.isCharging ? "battery.100percent.bolt" : "battery.75percent"
        }
    }

    private func hudTitle(_ event: SystemHUD.Event) -> String {
        switch event.kind {
        case .volume: event.isMuted ? "Muted" : "Volume"
        case .brightness: "Brightness"
        case .battery: event.isCharging ? "Charging" : "On battery"
        }
    }

    private func hudColors(_ event: SystemHUD.Event) -> [Color] {
        switch event.kind {
        case .volume: [Color(hex: 0x34C759), Color(hex: 0xB8E04A)]
        case .brightness: [Color(hex: 0xFFC94A), Color(hex: 0xFFF2B0)]
        case .battery: event.value < 0.2 ? [Color(hex: 0xFF5A4E), Color(hex: 0xFF8F70)] : [Color(hex: 0x34C759), Color(hex: 0x7BE495)]
        }
    }

    private var compact: some View {
        HStack(spacing: 0) {
            leftWing
                .frame(width: IslandController.wing, alignment: .leading)
                .padding(.leading, 14)
            Spacer(minLength: 0)
            rightWing
                .frame(width: IslandController.wing, alignment: .trailing)
                .padding(.trailing, 14)
        }
        .frame(height: controller.notch.height)
    }

    @ViewBuilder
    private var leftWing: some View {
        if controller.isBusy {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.14), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: recorder.isActive ? 1 : engine.focusProgress(at: context.date))
                        .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: engine.focusProgress(at: context.date))
                    Image(systemName: symbol)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(tint)
                }
                .frame(width: 18, height: 18)
            }
        } else if nowPlaying.hasTrack {
            Group {
                if let artwork = nowPlaying.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    nowPlaying.accent.opacity(0.4)
                }
            }
            .frame(width: 20, height: 20)
            .clipShape(.rect(cornerRadius: 5))
        }
    }

    @ViewBuilder
    private var rightWing: some View {
        if controller.isBusy {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(time(at: context.date))
                    .font(.numeric(13, weight: .bold))
                    .foregroundStyle(tint)
                    .contentTransition(.numericText(countsDown: !recorder.isActive))
                    .animation(Motion.quick, value: time(at: context.date))
                    .fixedSize()
            }
        } else if nowPlaying.hasTrack {
            Equalizer(tint: nowPlaying.accent, isPlaying: nowPlaying.isPlaying)
                .frame(width: 14, height: 14)
        }
    }

    @ViewBuilder
    private var peek: some View {
        if let announcement = controller.announcement {
            let isMusic = announcement.symbol == "music.note"
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    if isMusic {
                        artworkThumbnail
                            .frame(width: 22, height: 22)
                            .clipShape(.rect(cornerRadius: 6, style: .continuous))
                        Equalizer(tint: announcement.tint, isPlaying: nowPlaying.isPlaying)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: announcement.symbol)
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(announcement.tint)
                            .frame(width: 22, height: 22)
                            .background(announcement.tint.opacity(0.2), in: .circle)
                            .symbolEffect(.bounce, value: announcement.title)
                        Text(announcement.title)
                            .font(.rounded(13, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                }
                .frame(width: IslandController.hudWing, alignment: .leading)
                .padding(.leading, 14)
                Spacer(minLength: 0)
                Group {
                    if isMusic {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(announcement.title)
                                .font(.rounded(12, weight: .bold))
                                .foregroundStyle(.white)
                            Text(announcement.detail)
                                .font(.rounded(10.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        .lineLimit(1)
                    } else {
                        Text(announcement.detail)
                            .font(.rounded(13, weight: .semibold))
                            .foregroundStyle(announcement.tint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(width: IslandController.hudWing, alignment: .trailing)
                .padding(.trailing, 14)
            }
            .frame(height: controller.notch.height)
        }
    }

    @ViewBuilder
    private var artworkThumbnail: some View {
        if let artwork = nowPlaying.artwork {
            Image(nsImage: artwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            nowPlaying.accent.opacity(0.4)
        }
    }

    private func connectCalendar(showsSymbol: Bool) -> some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            if showsSymbol {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Text("See your classes and meetings here")
                .font(.rounded(12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
            Button("Connect Calendar") { Task { await calendar.prepare() } }
                .buttonStyle(.plain)
                .font(.rounded(12, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(.white, in: .capsule)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var deniedCalendar: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            Text("FocusKit can't see your calendar.")
                .font(.rounded(12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            Button("Open Privacy Settings") { calendar.openSettings() }
                .buttonStyle(.plain)
                .font(.rounded(12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(.white.opacity(0.14), in: .capsule)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var calendarTab: some View {
        HStack(alignment: .top, spacing: 10) {
            MonthGrid(calendar: calendar)
                .padding(10)
                .frame(width: 244)
                .frame(maxHeight: .infinity, alignment: .top)
                .notchCard()
            dayAgenda
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .notchCard()
        }
    }

    private var dayAgenda: some View {
        let system = Calendar.current
        let day = calendar.selected
        let isToday = system.isDateInToday(day)
        let events = calendar.access == .granted ? calendar.events(on: day) : []
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text("\(system.component(.day, from: day))")
                    .font(.numeric(30, weight: .bold))
                    .foregroundStyle(isToday ? Color.accentColor : .white)
                    .contentTransition(.numericText())
                VStack(alignment: .leading, spacing: 0) {
                    Text(isToday ? "Today" : day.formatted(.dateTime.weekday(.wide)))
                        .font(.rounded(13, weight: .bold))
                        .foregroundStyle(.white)
                    Text(events.isEmpty ? day.formatted(.dateTime.month(.wide)) : "\(events.count) \(events.count == 1 ? "event" : "events")")
                        .font(.rounded(11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 0)
                if !isToday {
                    Button("Today") { calendar.select(.now) }
                        .buttonStyle(.plain)
                        .font(.rounded(11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .background(.white.opacity(0.12), in: .capsule)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
                Button {
                    calendar.openCalendar()
                } label: {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 22, height: 22)
                        .background(.white.opacity(0.1), in: .circle)
                }
                .buttonStyle(.pressable)
                .help("Open Calendar")
            }
            switch calendar.access {
            case .granted:
                if events.isEmpty {
                    Spacer(minLength: 0)
                    VStack(spacing: 6) {
                        Image(systemName: "sun.horizon.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Palette.rest.mid)
                        Text("Nothing scheduled")
                            .font(.rounded(12.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .frame(maxWidth: .infinity)
                    Spacer(minLength: 0)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(events) { event in
                                EventRow(event: event)
                                    .transition(.opacity.combined(with: .offset(y: 4)))
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
            case .unknown:
                connectCalendar(showsSymbol: true)
            case .denied:
                deniedCalendar
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: calendar.selected)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if recorder.isActive {
            Waveform(levels: Array(recorder.levels.suffix(18)))
                .padding(10)
                .background(Palette.record.opacity(0.14))
        } else if engine.isResting {
            BreatheScene(insets: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                .background(Palette.rest.light)
        } else if let plan = engine.plan {
            FocusScene(
                mode: plan.mode,
                progress: { engine.focusProgress(at: $0) },
                route: plan.route,
                variant: plan.variant,
                isPaused: engine.isPaused,
                isAnimated: controller.shape == .expanded,
                insets: EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
            )
            .background(plan.mode.palette.light)
        }
    }

    private func iconButton(_ symbol: String, help: String, size: CGFloat = 30, highlighted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(highlighted ? .black : .white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size, height: size)
                .background(highlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.14)), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.pressable)
        .help(help)
    }

    private func sessionProgress(at date: Date) -> Double {
        if recorder.isActive { return 1 }
        return engine.isResting ? engine.segmentProgress(at: date) : engine.focusProgress(at: date)
    }

    private var caption: String {
        if recorder.isActive { return "Recording" }
        guard let plan = engine.plan else { return "FocusKit" }
        if engine.phase.isComplete { return "Session complete" }
        if engine.isResting { return "Break" }
        if engine.isPaused { return "Paused" }
        let label = plan.kind.title
        return plan.rounds > 1 ? "\(label) · \((engine.segment?.round ?? 0) + 1)/\(plan.rounds)" : label
    }

    private var completionText: String {
        guard let plan = engine.plan else { return "Session complete" }
        switch plan.mode {
        case .flight: return "Landed in \(plan.route.flatMap { Airport.named($0.destination)?.city } ?? "your destination")"
        case .orbit: return "Orbit complete"
        case .bloom: return "In full bloom"
        case .tide: return "High tide"
        }
    }

    private func announceSegment() {
        guard engine.isActive, let plan = engine.plan, engine.segmentIndex > 0 else { return }
        if engine.isResting {
            controller.announce("Break", detail: "\(Int((plan.breakDuration / 60).rounded())) min", symbol: "cup.and.saucer.fill", tint: Palette.rest.mid)
        } else {
            controller.announce("Round \((engine.segment?.round ?? 0) + 1)", detail: "of \(plan.rounds)", symbol: plan.mode.symbol, tint: plan.mode.palette.mid)
        }
    }

    private func time(at date: Date) -> String {
        if recorder.isActive, case .recording(let since) = recorder.state {
            return date.timeIntervalSince(since).clock
        }
        return engine.remaining(at: date).clock
    }

    private func start(_ item: FocusMode) {
        mode = item
        let minutes = UserDefaults.standard.integer(forKey: Preference.minutes(for: item))
        let duration = TimeInterval((minutes > 0 ? minutes : item.suggestedMinutes) * 60)
        let origin = Airport.named(homeCode) ?? .fallback
        let destination = origin.routes(closestTo: duration)[0]
        engine.start(FocusPlan(
            mode: item,
            intention: "",
            goalID: nil,
            focusDuration: duration,
            rounds: rounds,
            breakDuration: rounds > 1 ? TimeInterval(breakMinutes * 60) : 0,
            route: item == .flight ? Session.Route(origin: origin.code, destination: destination.code) : nil
        ))
    }
}

private struct ProgressLine: View {
    let value: Double
    let tint: Color
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule()
                    .fill(tint)
                    .frame(width: max(3, proxy.size.width * min(1, max(0, value))))
                    .animation(.linear(duration: 1), value: value)
            }
        }
        .frame(height: height)
    }
}

private struct Equalizer: View {
    let tint: Color
    let isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPlaying || reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    let phase = t * (2.6 + Double(index) * 0.9) + Double(index) * 1.7
                    Capsule()
                        .fill(tint)
                        .frame(width: 2.5, height: 4 + 12 * (0.5 + 0.5 * sin(phase)) * (0.6 + 0.4 * sin(phase * 0.37)))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .animation(.easeOut(duration: 0.08), value: Int(t * 12))
        }
    }
}

private struct MonthGrid: View {
    let calendar: CalendarStore

    var body: some View {
        let system = Calendar.current
        VStack(spacing: 2) {
            HStack {
                Text(calendar.month.formatted(.dateTime.month(.wide)))
                    .font(.rounded(13, weight: .bold))
                    .foregroundStyle(.white)
                + Text(" " + calendar.month.formatted(.dateTime.year()))
                    .font(.rounded(11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                chevron("chevron.left") { calendar.showMonth(offset: -1) }
                chevron("chevron.right") { calendar.showMonth(offset: 1) }
            }
            .padding(.bottom, 2)
            HStack(spacing: 0) {
                ForEach(Array(calendar.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.rounded(9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(calendar.days, id: \.self) { day in
                    DayCell(
                        day: system.component(.day, from: day),
                        colors: inMonthColors(for: day, system: system),
                        inMonth: system.isDate(day, equalTo: calendar.month, toGranularity: .month),
                        isToday: system.isDateInToday(day),
                        isSelected: system.isDate(day, inSameDayAs: calendar.selected),
                        isWeekend: system.isDateInWeekend(day)
                    ) {
                        calendar.select(day)
                    }
                }
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.9), value: calendar.month)
    }

    private func inMonthColors(for day: Date, system: Calendar) -> [Color] {
        guard system.isDate(day, equalTo: calendar.month, toGranularity: .month) else { return [] }
        var colors: [Color] = []
        for event in calendar.events(on: day) where !colors.contains(event.color) {
            colors.append(event.color)
            if colors.count == 3 { break }
        }
        return colors
    }

    private func chevron(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 20, height: 20)
                .background(.white.opacity(0.08), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.pressable)
    }
}

private struct DayCell: View {
    let day: Int
    let colors: [Color]
    let inMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let isWeekend: Bool
    let select: () -> Void
    @State private var isHovering = false

    private var numberColor: Color {
        if isToday { return .white }
        if !inMonth { return .white.opacity(0.2) }
        return .white.opacity(isWeekend ? 0.6 : 0.92)
    }

    var body: some View {
        Button(action: select) {
            VStack(spacing: 2) {
                Text("\(day)")
                    .font(.rounded(11, weight: isToday || isSelected ? .bold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(numberColor)
                HStack(spacing: 2) {
                    ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                        Circle()
                            .fill(isToday ? .white : color)
                            .frame(width: 3.5, height: 3.5)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(background)
            }
            .overlay {
                if isSelected, !isToday {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(.white.opacity(0.22), lineWidth: 1)
                }
            }
            .contentShape(.rect(cornerRadius: 7))
        }
        .buttonStyle(.pressable)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .animation(.spring(response: 0.3, dampingFraction: 1), value: isSelected)
    }

    private var background: AnyShapeStyle {
        if isToday { return AnyShapeStyle(Color.accentColor.gradient) }
        if isSelected { return AnyShapeStyle(.white.opacity(0.14)) }
        if isHovering, inMonth { return AnyShapeStyle(.white.opacity(0.07)) }
        return AnyShapeStyle(.clear)
    }
}

private struct EventRow: View {
    let event: CalendarStore.Event

    var body: some View {
        let isNow = event.start <= .now && event.end > .now
        let isPast = event.end < .now
        HStack(alignment: .center, spacing: 9) {
            VStack(alignment: .trailing, spacing: 1) {
                if event.isAllDay {
                    Text("All day")
                } else {
                    Text(event.start.formatted(date: .omitted, time: .shortened))
                    Text(event.end.formatted(date: .omitted, time: .shortened))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .font(.numeric(10.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
            .frame(width: 42, alignment: .trailing)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(event.color)
                .frame(width: 3)
                .padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.rounded(12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.rounded(10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if isNow {
                Text("Now")
                    .font(.rounded(9.5, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6)
                    .frame(height: 16)
                    .background(event.color, in: .capsule)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 38)
        .background(event.color.opacity(isNow ? 0.24 : 0.1), in: .rect(cornerRadius: 10, style: .continuous))
        .opacity(isPast ? 0.5 : 1)
    }
}

private struct NextEvent: View {
    let event: CalendarStore.Event
    let now: Date

    private var when: String {
        if event.start <= now { return "Now · until \(event.end.formatted(date: .omitted, time: .shortened))" }
        let minutes = Int(event.start.timeIntervalSince(now) / 60)
        if minutes < 1 { return "Starting" }
        if minutes < 60 { return "In \(minutes) min" }
        return "At \(event.start.formatted(date: .omitted, time: .shortened))"
    }

    var body: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 2)
                .fill(event.color)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(when)
                    .font(.rounded(10.5, weight: .bold))
                    .foregroundStyle(event.color)
                Text(event.title)
                    .font(.rounded(13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.rounded(10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(event.color.opacity(0.14), in: .rect(cornerRadius: 12, style: .continuous))
    }
}

private struct WeekBars: View {
    let minutes: [Double]
    let tint: Color

    var body: some View {
        let peak = max(minutes.max() ?? 0, 30)
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(minutes.enumerated()), id: \.offset) { index, value in
                let isToday = index == minutes.count - 1
                Capsule()
                    .fill(isToday ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(.white.opacity(value > 0 ? 0.3 : 0.1)))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(4, 44 * value / peak))
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .help("Last 7 days")
    }
}

private struct ModeLauncher: View {
    let mode: FocusMode
    let isCurrent: Bool
    let start: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: start) {
            VStack(spacing: 5) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background {
                        Circle()
                            .fill(LinearGradient(colors: [mode.palette.mid, mode.palette.deep], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(isCurrent ? 0.7 : 0.15), lineWidth: isCurrent ? 1.5 : 0.5)
                    }
                    .shadow(color: mode.palette.deep.opacity(isHovering ? 0.7 : 0.35), radius: isHovering ? 10 : 5, y: 2)
                    .scaleEffect(isHovering ? 1.08 : 1)
                Text(mode.title)
                    .font(.rounded(10, weight: .semibold))
                    .foregroundStyle(.white.opacity(isCurrent || isHovering ? 0.95 : 0.55))
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .onHover { hovering in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) { isHovering = hovering }
        }
        .help("Start \(mode.title)")
    }
}

private struct PlayerLauncher: View {
    let player: NowPlaying.Player
    let play: () -> Void
    @State private var isHovering = false

    private var icon: NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.rawValue).map { NSWorkspace.shared.icon(forFile: $0.path(percentEncoded: false)) }
    }

    var body: some View {
        let installed = icon != nil
        Button(action: play) {
            VStack(spacing: 8) {
                Group {
                    if let icon {
                        Image(nsImage: icon)
                            .resizable()
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .frame(width: 52, height: 52)
                .scaleEffect(isHovering ? 1.06 : 1)
                VStack(spacing: 1) {
                    Text(player.scriptName)
                        .font(.rounded(13, weight: .bold))
                        .foregroundStyle(.white)
                    Text(installed ? "Play" : "Not installed")
                        .font(.rounded(11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white.opacity(isHovering ? 0.05 : 0))
            .notchCard()
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .disabled(!installed)
        .onHover { hovering in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { isHovering = hovering }
        }
    }
}

private struct ArtworkBackdrop: View {
    let artwork: NSImage?
    let accent: Color

    var body: some View {
        ZStack {
            accent.opacity(0.22)
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(1.5)
                    .blur(radius: 30)
                    .opacity(0.6)
            }
            LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
        }
        .allowsHitTesting(false)
    }
}

private extension View {
    func notchCard() -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return background(.white.opacity(0.06))
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
            }
    }
}

private struct TopNotch: Shape {
    var fillet: CGFloat
    var radius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(fillet, radius) }
        set {
            fillet = newValue.first
            radius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let left = rect.minX + fillet
        let right = rect.maxX - fillet
        let r = min(radius, rect.height / 2, (right - left) / 2)
        let f = min(fillet, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: left, y: rect.minY + f),
            control1: CGPoint(x: rect.minX + f * 0.62, y: rect.minY),
            control2: CGPoint(x: left, y: rect.minY + f * 0.38)
        )
        path.addLine(to: CGPoint(x: left, y: rect.maxY - r))
        path.addCurve(
            to: CGPoint(x: left + r, y: rect.maxY),
            control1: CGPoint(x: left, y: rect.maxY - r * 0.38),
            control2: CGPoint(x: left + r * 0.38, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: right - r, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: right, y: rect.maxY - r),
            control1: CGPoint(x: right - r * 0.38, y: rect.maxY),
            control2: CGPoint(x: right, y: rect.maxY - r * 0.38)
        )
        path.addLine(to: CGPoint(x: right, y: rect.minY + f))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control1: CGPoint(x: right, y: rect.minY + f * 0.38),
            control2: CGPoint(x: rect.maxX - f * 0.62, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
