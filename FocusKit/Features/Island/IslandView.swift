import SwiftUI

struct IslandView: View {
    let controller: IslandController
    @Environment(FocusEngine.self) private var engine
    @Environment(VoiceRecorder.self) private var recorder
    @Environment(Library.self) private var library
    @Environment(NowPlaying.self) private var nowPlaying
    @Environment(Soundscape.self) private var soundscape
    @AppStorage(Preference.focusMode) private var mode = FocusMode.flight
    @AppStorage(Preference.name) private var name = ""
    @AppStorage(Preference.homeAirport) private var homeCode = Airport.fallback.code
    @AppStorage("rounds") private var rounds = 1
    @AppStorage("breakMinutes") private var breakMinutes = 5

    private var soundscapeKind: Soundscape.Kind? {
        guard engine.isActive, !engine.isPaused, let plan = engine.plan else { return nil }
        return engine.isResting ? .breeze : Soundscape.Kind(mode: plan.mode)
    }

    var body: some View {
        let size = controller.size
        let radius: CGFloat = controller.shape == .expanded ? 26 : (controller.shape == .peek ? 22 : min(15, size.width / 2))
        ZStack(alignment: .trailing) {
            Color.clear
            SideNotch(fillet: IslandController.fillet, radius: radius)
                .fill(.black)
                .frame(width: size.width, height: size.height + IslandController.fillet * 2)
                .overlay(alignment: .trailing) {
                    content
                        .frame(width: size.width, height: size.height)
                        .clipShape(.rect(cornerRadius: radius))
                }
                .opacity(controller.shape == .hidden ? 0 : 1)
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
    }

    @ViewBuilder
    private var content: some View {
        switch controller.shape {
        case .expanded:
            expanded
                .transition(.blurReplace.animation(.easeOut(duration: 0.24).delay(0.06)))
        case .peek:
            peek
                .transition(.blurReplace.animation(.easeOut(duration: 0.2).delay(0.05)))
        case .compact:
            compact
                .transition(.blurReplace.animation(.easeOut(duration: 0.16)))
        case .hidden:
            Color.clear
        }
    }

    private var expanded: some View {
        VStack(spacing: 8) {
            ForEach(Array(controller.sections.enumerated()), id: \.element) { index, section in
                if index > 0 {
                    Rectangle()
                        .fill(.white.opacity(0.08))
                        .frame(height: 1)
                }
                Group {
                    switch section {
                    case .session: sessionSection
                    case .music: musicSection
                    case .launcher: launcherSection
                    }
                }
                .frame(height: section.height)
            }
        }
        .padding(14)
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
    private var compact: some View {
        if controller.isBusy {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 5) {
                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.14), lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: recorder.isActive ? 1 : engine.focusProgress(at: context.date))
                            .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: symbol)
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(tint)
                    }
                    .frame(width: 17, height: 17)
                    Text(shortTime(at: context.date))
                        .font(.numeric(9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                        .fixedSize()
                        .contentTransition(.numericText(countsDown: true))
                }
                .padding(.leading, 2)
            }
        } else if nowPlaying.isPlaying {
            Equalizer(tint: nowPlaying.accent, isPlaying: true)
                .frame(width: 12, height: 16)
                .padding(.leading, 2)
        } else {
            Capsule()
                .fill(.white.opacity(0.22))
                .frame(width: 2, height: 16)
        }
    }

    private var peek: some View {
        let announcement = controller.announcement
        let tint = announcement?.tint ?? tint
        return HStack(spacing: 10) {
            Image(systemName: announcement?.symbol ?? symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.2), in: .circle)
                .symbolEffect(.bounce, value: announcement?.text)
            Text(announcement?.text ?? "")
                .font(.rounded(13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
    }

    private var sessionSection: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 10) {
                thumbnail
                    .frame(height: 104)
                    .frame(maxWidth: .infinity)
                    .clipShape(.rect(cornerRadius: 16))
                    .overlay(alignment: .topTrailing) {
                        iconButton("arrow.up.forward", help: "Open FocusKit", size: 24) { controller.openApp() }
                            .padding(6)
                    }

                VStack(spacing: 2) {
                    Label(caption, systemImage: symbol)
                        .font(.rounded(11, weight: .semibold))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                    Text(time(at: context.date))
                        .font(.numeric(32, weight: .bold))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(countsDown: !recorder.isActive))
                        .animation(Motion.quick, value: time(at: context.date))
                }

                ProgressLine(value: sessionProgress(at: context.date), tint: tint)
                    .padding(.horizontal, 4)

                sessionControls
            }
        }
    }

    @ViewBuilder
    private var sessionControls: some View {
        HStack(spacing: 10) {
            if engine.isActive {
                iconButton("forward.end.fill", help: engine.isResting ? "Skip break" : "Skip round", size: 32) { engine.skip() }
                iconButton(engine.isPaused ? "play.fill" : "pause.fill", help: engine.isPaused ? "Resume" : "Pause", size: 42, highlighted: true) {
                    withAnimation(Motion.morph) { engine.togglePause() }
                }
                iconButton(soundscape.isEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill", help: soundscape.isEnabled ? "Mute soundscape" : "Play soundscape", size: 32) {
                    soundscape.isEnabled.toggle()
                }
            } else if recorder.isActive {
                iconButton("stop.fill", help: "Open to stop", size: 42, highlighted: true) { controller.openApp() }
            } else {
                iconButton("checkmark", help: "See summary", size: 42, highlighted: true) { controller.openApp() }
            }
        }
    }

    private var musicSection: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 10) {
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
                        .frame(width: 44, height: 44)
                        .clipShape(.rect(cornerRadius: 10))
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

                HStack(spacing: 14) {
                    iconButton("backward.fill", help: "Previous", size: 30) { nowPlaying.previous() }
                    iconButton(nowPlaying.isPlaying ? "pause.fill" : "play.fill", help: nowPlaying.isPlaying ? "Pause" : "Play", size: 38, highlighted: true) {
                        nowPlaying.togglePlayback()
                    }
                    iconButton("forward.fill", help: "Next", size: 30) { nowPlaying.next() }
                }
            }
        }
    }

    private var launcherSection: some View {
        let today = library.focusedTime(in: Calendar.current.dateInterval(of: .day, for: .now))
        return VStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(today.compactDuration)
                    .font(.numeric(28, weight: .bold))
                    .foregroundStyle(.white)
                Text(name.isEmpty ? "focused today" : "focused today, \(name)")
                    .font(.rounded(11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(FocusMode.allCases) { item in
                    Button {
                        start(item)
                    } label: {
                        Label(item.title, systemImage: item.symbol)
                            .font(.rounded(12, weight: .semibold))
                            .foregroundStyle(item.palette.mid)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(item.palette.mid.opacity(item == mode ? 0.24 : 0.12), in: .capsule)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.pressable)
                    .help("Start \(item.title)")
                }
            }
            Button {
                controller.openApp()
            } label: {
                Text("Open FocusKit")
                    .font(.rounded(12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background(.white.opacity(0.08), in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(.pressable)
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

private struct SideNotch: Shape {
    let fillet: CGFloat
    var radius: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let fillet = min(self.fillet, rect.width * 0.7)
        let top = rect.minY + self.fillet
        let bottom = rect.maxY - self.fillet
        let r = min(radius, (bottom - top) / 2, rect.width)
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - fillet, y: top), control: CGPoint(x: rect.maxX, y: top))
        path.addLine(to: CGPoint(x: rect.minX + r, y: top))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: top + r), control: CGPoint(x: rect.minX, y: top))
        path.addLine(to: CGPoint(x: rect.minX, y: bottom - r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: bottom), control: CGPoint(x: rect.minX, y: bottom))
        path.addLine(to: CGPoint(x: rect.maxX - fillet, y: bottom))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.maxX, y: bottom))
        path.closeSubpath()
        return path
    }
}
