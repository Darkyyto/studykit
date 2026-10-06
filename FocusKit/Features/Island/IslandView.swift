import SwiftUI

struct IslandView: View {
    let controller: IslandController
    let calendar: CalendarStore
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
                .shadow(color: .black.opacity(controller.shape == .expanded ? 0.3 : 0), radius: 16, y: 6)
                .opacity(controller.isVisible ? 1 : 0)
        }
        .frame(width: IslandController.canvas.width, height: IslandController.canvas.height)
        .environment(\.colorScheme, .dark)
        .onChange(of: engine.segmentIndex) { _, _ in announceSegment() }
        .onChange(of: engine.phase.isComplete) { _, done in
            if done { controller.announce(completionText, symbol: "checkmark", tint: tint) }
            controller.refresh()
        }
        .onChange(of: engine.isActive) { _, _ in controller.refresh() }
        .onChange(of: recorder.isActive) { _, active in
            controller.refresh()
            if active { controller.announce("Recording", symbol: "waveform", tint: Palette.record) }
        }
        .onChange(of: nowPlaying.title) { _, title in
            guard !title.isEmpty, nowPlaying.isPlaying, !controller.isBusy else { return }
            controller.announce(title, symbol: "music.note", tint: nowPlaying.accent)
        }
        .onChange(of: nowPlaying.isPlaying) { _, _ in controller.refresh() }
        .onChange(of: soundscapeKind, initial: true) { _, kind in soundscape.sync(kind: kind) }
        .onChange(of: soundscape.isEnabled) { _, _ in soundscape.sync(kind: soundscapeKind) }
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
                .transition(.blurReplace.animation(.easeOut(duration: 0.2).delay(0.05)))
        case .compact:
            compact
                .transition(.blurReplace.animation(.easeOut(duration: 0.18)))
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
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 12)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.9), value: controller.tab)
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                tabButton(.home, symbol: "house.fill", help: "Home")
                tabButton(.music, symbol: "music.note", help: "Music")
                tabButton(.calendar, symbol: "calendar", help: "Calendar")
            }
            .padding(.leading, 14)
            Spacer(minLength: max(controller.notch.width, 100))
            HStack(spacing: 10) {
                Text(Date.now.formatted(.dateTime.weekday(.abbreviated).day()))
                    .font(.rounded(11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                iconButton("arrow.up.forward.app", help: "Open FocusKit", size: 22) { controller.openApp() }
            }
            .padding(.trailing, 14)
        }
    }

    private func tabButton(_ tab: IslandController.Tab, symbol: String, help: String) -> some View {
        let isSelected = controller.tab == tab
        return Button {
            controller.tab = tab
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.45))
                .frame(width: 30, height: 22)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(.white.opacity(0.14))
                            .matchedGeometryEffect(id: "tab", in: tabs)
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.pressable)
        .help(help)
    }

    private var home: some View {
        HStack(alignment: .top, spacing: 8) {
            Group {
                if controller.isBusy {
                    sessionSection
                } else {
                    launcherSection
                }
            }
            .frame(width: 236)
            .frame(maxHeight: .infinity)
            .padding(10)
            .background(.white.opacity(0.06), in: .rect(cornerRadius: 16))

            Group {
                if nowPlaying.hasTrack {
                    musicSection
                } else {
                    agendaSection
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(10)
            .background(.white.opacity(0.06), in: .rect(cornerRadius: 16))
        }
    }

    @ViewBuilder
    private var musicTab: some View {
        if nowPlaying.hasTrack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 16) {
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
                                        .font(.system(size: 30, weight: .semibold))
                                        .foregroundStyle(nowPlaying.accent)
                                }
                            }
                        }
                        .frame(width: 112, height: 112)
                        .clipShape(.rect(cornerRadius: 16))
                        .shadow(color: nowPlaying.accent.opacity(0.45), radius: 16, y: 6)
                        .scaleEffect(nowPlaying.isPlaying ? 1 : 0.92)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: nowPlaying.isPlaying)
                    }
                    .buttonStyle(.pressable)
                    .help("Open \(nowPlaying.player?.scriptName ?? "player")")

                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Equalizer(tint: nowPlaying.accent, isPlaying: nowPlaying.isPlaying)
                                    .frame(width: 12, height: 11)
                                Text(nowPlaying.player?.scriptName ?? "")
                                    .font(.rounded(10.5, weight: .bold))
                                    .foregroundStyle(nowPlaying.accent)
                            }
                            Text(nowPlaying.title)
                                .font(.rounded(16, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(nowPlaying.artist)
                                .font(.rounded(12.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                        if nowPlaying.duration > 0 {
                            VStack(spacing: 3) {
                                ProgressLine(value: nowPlaying.elapsed(at: context.date) / nowPlaying.duration, tint: nowPlaying.accent)
                                HStack {
                                    Text(nowPlaying.elapsed(at: context.date).clock)
                                    Spacer()
                                    Text("-" + max(0, nowPlaying.duration - nowPlaying.elapsed(at: context.date)).clock)
                                }
                                .font(.numeric(10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.45))
                            }
                        }
                        HStack(spacing: 14) {
                            iconButton("backward.fill", help: "Previous", size: 30) { nowPlaying.previous() }
                            iconButton(nowPlaying.isPlaying ? "pause.fill" : "play.fill", help: nowPlaying.isPlaying ? "Pause" : "Play", size: 38, highlighted: true) {
                                nowPlaying.togglePlayback()
                            }
                            iconButton("forward.fill", help: "Next", size: 30) { nowPlaying.next() }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 6)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text("Nothing is playing")
                    .font(.rounded(14, weight: .bold))
                    .foregroundStyle(.white)
                HStack(spacing: 8) {
                    ForEach([NowPlaying.Player.spotify, .music], id: \.self) { player in
                        if NowPlaying.isInstalled(player) {
                            Button {
                                nowPlaying.play(in: player)
                            } label: {
                                Label("Play in \(player.scriptName)", systemImage: "play.fill")
                                    .font(.rounded(12, weight: .semibold))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 12)
                                    .frame(height: 28)
                                    .background(.white, in: .capsule)
                                    .contentShape(.capsule)
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var peek: some View {
        let announcement = controller.announcement
        let tint = announcement?.tint ?? tint
        return VStack(spacing: 0) {
            Color.clear
                .frame(height: controller.notch.height)
            HStack(spacing: 10) {
                Image(systemName: announcement?.symbol ?? symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(tint.opacity(0.2), in: .circle)
                    .symbolEffect(.bounce, value: announcement?.text)
                Text(announcement?.text ?? "")
                    .font(.rounded(13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .frame(height: 40)
        }
    }

    private var sessionSection: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 10) {
                thumbnail
                    .frame(width: 70, height: 70)
                    .clipShape(.rect(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        Label(caption, systemImage: symbol)
                            .font(.rounded(11, weight: .semibold))
                            .foregroundStyle(tint)
                            .lineLimit(1)
                        Text(time(at: context.date))
                            .font(.numeric(24, weight: .bold))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText(countsDown: !recorder.isActive))
                            .animation(Motion.quick, value: time(at: context.date))
                    }
                    ProgressLine(value: sessionProgress(at: context.date), tint: tint)
                    sessionControls
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var sessionControls: some View {
        HStack(spacing: 8) {
            if engine.isActive {
                iconButton("forward.end.fill", help: engine.isResting ? "Skip break" : "Skip round", size: 26) { engine.skip() }
                iconButton(engine.isPaused ? "play.fill" : "pause.fill", help: engine.isPaused ? "Resume" : "Pause", size: 32, highlighted: true) {
                    withAnimation(Motion.morph) { engine.togglePause() }
                }
                iconButton(soundscape.isEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill", help: soundscape.isEnabled ? "Mute soundscape" : "Play soundscape", size: 26) {
                    soundscape.isEnabled.toggle()
                }
            } else if recorder.isActive {
                iconButton("stop.fill", help: "Stop and save the recording", size: 32, highlighted: true) {
                    recorder.stopNow(engine: engine, enhancer: enhancer, persona: persona)
                }
            } else {
                iconButton("checkmark", help: "See summary", size: 32, highlighted: true) { controller.openApp() }
            }
        }
    }

    private var musicSection: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 8) {
                HStack(spacing: 10) {
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
                                    nowPlaying.accent.opacity(0.25)
                                    Image(systemName: "music.note")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(nowPlaying.accent)
                                }
                            }
                        }
                        .frame(width: 38, height: 38)
                        .clipShape(.rect(cornerRadius: 9))
                        .shadow(color: nowPlaying.accent.opacity(0.35), radius: 8, y: 2)
                    }
                    .buttonStyle(.pressable)
                    .help("Open \(nowPlaying.player?.scriptName ?? "player")")

                    VStack(alignment: .leading, spacing: 2) {
                        Text(nowPlaying.title)
                            .font(.rounded(13, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(nowPlaying.artist)
                            .font(.rounded(11.5, weight: .medium))
                            .foregroundStyle(nowPlaying.accent)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if nowPlaying.duration > 0 {
                    ProgressLine(value: nowPlaying.elapsed(at: context.date) / nowPlaying.duration, tint: .white.opacity(0.85))
                        .padding(.horizontal, 4)
                }

                HStack(spacing: 12) {
                    iconButton("backward.fill", help: "Previous", size: 26) { nowPlaying.previous() }
                    iconButton(nowPlaying.isPlaying ? "pause.fill" : "play.fill", help: nowPlaying.isPlaying ? "Pause" : "Play", size: 32, highlighted: true) {
                        nowPlaying.togglePlayback()
                    }
                    iconButton("forward.fill", help: "Next", size: 26) { nowPlaying.next() }
                }
            }
        }
    }

    private var launcherSection: some View {
        let today = library.focusedTime(in: Calendar.current.dateInterval(of: .day, for: .now))
        return VStack(spacing: 10) {
            VStack(spacing: 1) {
                Text(today.compactDuration)
                    .font(.numeric(22, weight: .bold))
                    .foregroundStyle(.white)
                Text(name.isEmpty ? "focused today" : "focused today, \(name)")
                    .font(.rounded(11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(FocusMode.allCases) { item in
                    Button {
                        start(item)
                    } label: {
                        Label(item.title, systemImage: item.symbol)
                            .font(.rounded(11.5, weight: .semibold))
                            .foregroundStyle(item.palette.mid)
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .background(item.palette.mid.opacity(item == mode ? 0.24 : 0.12), in: .capsule)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.pressable)
                    .help("Start \(item.title)")
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var agendaSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Up next")
                    .font(.rounded(12, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Button("Calendar") { controller.tab = .calendar }
                    .buttonStyle(.plain)
                    .font(.rounded(11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            switch calendar.access {
            case .granted:
                if calendar.upcoming.isEmpty {
                    Spacer()
                    Text("Nothing else today")
                        .font(.rounded(13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    VStack(spacing: 6) {
                        ForEach(calendar.upcoming.prefix(2)) { event in
                            EventRow(event: event, compact: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
            case .unknown:
                connectCalendar
            case .denied:
                deniedCalendar
            }
        }
    }

    private var connectCalendar: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
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
        HStack(alignment: .top, spacing: 12) {
            MonthGrid(calendar: calendar)
                .frame(width: 214)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(calendar.selected.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.rounded(12, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        calendar.openCalendar()
                    } label: {
                        Image(systemName: "arrow.up.forward")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 22, height: 22)
                            .background(.white.opacity(0.1), in: .circle)
                    }
                    .buttonStyle(.pressable)
                    .help("Open Calendar")
                }
                switch calendar.access {
                case .granted:
                    let events = calendar.events(on: calendar.selected)
                    if events.isEmpty {
                        Spacer()
                        Text("Nothing scheduled")
                            .font(.rounded(13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                            .frame(maxWidth: .infinity)
                        Spacer()
                    } else {
                        ScrollView {
                            VStack(spacing: 6) {
                                ForEach(events) { event in
                                    EventRow(event: event, compact: false)
                                        .transition(.opacity.combined(with: .offset(y: 4)))
                                }
                            }
                        }
                        .scrollIndicators(.never)
                    }
                case .unknown:
                    connectCalendar
                case .denied:
                    deniedCalendar
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.spring(response: 0.32, dampingFraction: 0.9), value: calendar.selected)
        }
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
                .background(highlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.12)), in: .circle)
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
            controller.announce("Break · \(Int((plan.breakDuration / 60).rounded())) min", symbol: "cup.and.saucer.fill", tint: Palette.rest.mid)
        } else {
            controller.announce("Round \((engine.segment?.round ?? 0) + 1) of \(plan.rounds)", symbol: plan.mode.symbol, tint: plan.mode.palette.mid)
        }
    }

    private func time(at date: Date) -> String {
        if recorder.isActive, case .recording(let since) = recorder.state {
            return date.timeIntervalSince(since).clock
        }
        return engine.remaining(at: date).clock
    }

    private func shortTime(at date: Date) -> String {
        if recorder.isActive, case .recording(let since) = recorder.state {
            return "\(Int(date.timeIntervalSince(since) / 60))′"
        }
        let remaining = engine.remaining(at: date)
        return remaining >= 60 ? "\(Int((remaining / 60).rounded(.up)))′" : "\(Int(remaining))″"
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
        .frame(height: 3)
    }
}

private struct Equalizer: View {
    let tint: Color
    let isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12, paused: !isPlaying || reduceMotion)) { context in
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
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                ForEach(calendar.days, id: \.self) { day in
                    let inMonth = system.isDate(day, equalTo: calendar.month, toGranularity: .month)
                    let isToday = system.isDateInToday(day)
                    let isSelected = system.isDate(day, inSameDayAs: calendar.selected)
                    Button {
                        calendar.select(day)
                    } label: {
                        VStack(spacing: 1) {
                            Text("\(system.component(.day, from: day))")
                                .font(.rounded(10.5, weight: isToday ? .bold : .semibold))
                                .foregroundStyle(isToday ? .white : .white.opacity(inMonth ? 0.9 : 0.25))
                                .frame(width: 19, height: 15)
                                .background {
                                    if isToday {
                                        Circle().fill(Color.accentColor)
                                    } else if isSelected {
                                        Circle().stroke(.white.opacity(0.5), lineWidth: 1.2)
                                    }
                                }
                            Circle()
                                .fill(.white.opacity(calendar.hasEvents(on: day) && inMonth ? 0.55 : 0))
                                .frame(width: 3, height: 3)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.9), value: calendar.month)
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

private struct EventRow: View {
    let event: CalendarStore.Event
    let compact: Bool

    var body: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(event.color)
                .frame(width: 3.5)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.rounded(12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.rounded(11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                if event.isAllDay {
                    Text("All day")
                } else {
                    Text(event.start.formatted(date: .omitted, time: .shortened))
                    if !compact {
                        Text(event.end.formatted(date: .omitted, time: .shortened))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
            }
            .font(.numeric(12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 9)
        .frame(height: compact ? 36 : 40)
        .background(.white.opacity(event.end < .now ? 0.03 : 0.07), in: .rect(cornerRadius: 12))
        .opacity(event.end < .now ? 0.55 : 1)
    }
}

private struct TopNotch: Shape {
    let fillet: CGFloat
    var radius: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let left = rect.minX + fillet
        let right = rect.maxX - fillet
        let r = min(radius, rect.height / 2, (right - left) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: left, y: rect.minY + fillet), control: CGPoint(x: left, y: rect.minY))
        path.addLine(to: CGPoint(x: left, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: left + r, y: rect.maxY), control: CGPoint(x: left, y: rect.maxY))
        path.addLine(to: CGPoint(x: right - r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: right, y: rect.maxY - r), control: CGPoint(x: right, y: rect.maxY))
        path.addLine(to: CGPoint(x: right, y: rect.minY + fillet))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: right, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
