import SwiftUI

struct IslandView: View {
    let controller: IslandController
    let calendar: CalendarStore
    let tray: FileTray
    let devices: DeviceWatcher
    let clipboard: ClipboardHistory
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
    @AppStorage(FileTray.enabledKey) private var showsTray = true
    @AppStorage(SystemHUD.percentKey) private var showsPercent = true
    @State private var isDropTargeted = false
    @State private var confirmsEnd = false
    @State private var choosesStart = false
    @State private var startMode = FocusMode.flight
    @State private var startMinutes = 25
    @State private var endReset: Task<Void, Never>?
    @Namespace private var tabs
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

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
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: controller.wing)
        .animation(.spring(response: 0.42, dampingFraction: 0.88), value: controller.tab)
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: controller.hasActivity)
        .environment(\.colorScheme, .dark)
        .environment(\.appearsActive, true)
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
        .onChange(of: devices.notice) { _, notice in
            guard let notice else { return }
            controller.announce(notice.title, detail: notice.detail, symbol: notice.symbol, tint: notice.tint, fromSystem: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: AppDelegate.openMainWindow)) { _ in
            openWindow(id: "main")
            NSApp.activate()
        }
        .onChange(of: systemHUD.event) { _, event in
            if event != nil { controller.showSystemHUD() }
        }
        .task(id: controller.tab) {
            if controller.tab == .calendar { await calendar.prepare() }
        }
        .onChange(of: controller.shape) { _, shape in
            if shape != .expanded {
                cancelEnd()
                choosesStart = false
            }
            if shape == .expanded {
                clipboard.refreshAccess()
                calendar.refresh()
                tray.prune()
            }
        }
        .onChange(of: showsTray) { _, shows in
            if !shows, controller.tab == .tray { controller.tab = .home }
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
                .animation(.easeOut(duration: 0.2), value: controller.announcement)
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
                case .tray: trayTab
                case .clipboard: clipboardTab
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
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .background(Color.accentColor.opacity(0.08), in: .rect(cornerRadius: 22, style: .continuous))
                    .padding(.horizontal, 8)
                    .padding(.top, controller.notch.height + 2)
                    .padding(.bottom, 8)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isDropTargeted)
        .contextMenu {
            Text("FocusKit \(Updater.currentVersion)")
            Divider()
            Button("Open FocusKit") {
                openWindow(id: "main")
                NSApp.activate()
            }
            Button("Settings…") {
                openSettings()
                NSApp.activate()
            }
            Divider()
            Button("Quit FocusKit") { NSApp.terminate(nil) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard showsTray else { return false }
            withAnimation(.spring(response: 0.36, dampingFraction: 0.85)) {
                tray.add(urls)
                controller.tab = .tray
            }
            IslandController.tap()
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted && showsTray
            if targeted, showsTray { controller.tab = .tray }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                tabButton(.home, symbol: "house.fill", help: "Home")
                tabButton(.music, symbol: "music.note", help: "Music")
                tabButton(.calendar, symbol: "calendar", help: "Calendar")
                if showsTray {
                    tabButton(.tray, symbol: tray.items.isEmpty ? "tray" : "tray.full.fill", help: "Tray")
                }
                tabButton(.clipboard, symbol: "list.clipboard", help: "Clipboard")
            }
            .padding(3)
            .background(.white.opacity(0.06), in: .capsule)
            .padding(.leading, 16)
            Spacer(minLength: max(controller.notch.width, 100))
            HStack(spacing: 10) {
                Text(Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                iconButton("arrow.up.forward.app", help: "Open FocusKit", size: 24) { controller.openApp() }
            }
            .padding(.trailing, 16)
        }
    }

    private func tabButton(_ tab: IslandController.Tab, symbol: String, help: String) -> some View {
        let isSelected = controller.tab == tab
        return Button {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) { controller.tab = tab }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.45))
                .frame(width: 28, height: 20)
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
        HStack(spacing: 0) {
            Group {
                if controller.isBusy {
                    sessionCard
                } else {
                    todayCard
                }
            }
            .frame(width: 250)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            Rectangle()
                .fill(.white.opacity(0.09))
                .frame(width: 1)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
            Group {
                if nowPlaying.hasTrack {
                    musicCard
                } else {
                    agendaCard
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }

    @ViewBuilder
    private var todayCard: some View {
        ZStack {
            if choosesStart {
                startChooser
                    .transition(.opacity.combined(with: .offset(x: 12)))
            } else {
                todaySummary
                    .transition(.opacity.combined(with: .offset(x: -12)))
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.9), value: choosesStart)
    }

    private var todaySummary: some View {
        let stats = JournalStats(sessions: library.sessions)
        let week = stats.lastSevenDays.map { $0.minutes.values.reduce(0, +) }
        let today = (week.last ?? 0) * 60
        return VStack(alignment: .leading, spacing: 0) {
            Text(greeting)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(today > 0 ? today.compactDuration : "0 min")
                    .font(.system(size: 30, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text("today")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer(minLength: 0)
                if stats.streak > 0 {
                    Label("\(stats.streak)", systemImage: "flame.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.rest.mid)
                        .help("\(stats.streak) day streak")
                }
            }
            Spacer(minLength: 10)
            Button {
                startMode = mode
                startMinutes = FocusEngine.preferredMinutes(for: mode)
                choosesStart = true
            } label: {
                Label("Start", systemImage: "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(.white, in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(.pressable)
            .help("Start a focus session")
        }
        .padding(.vertical, 4)
    }

    private var startChooser: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                glyphButton("chevron.left", size: 12, dim: true, help: "Back") { choosesStart = false }
                    .padding(.leading, -8)
                Spacer(minLength: 0)
                ForEach(FocusMode.allCases) { item in
                    let isSelected = startMode == item
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                            startMode = item
                            startMinutes = FocusEngine.preferredMinutes(for: item)
                        }
                    } label: {
                        Image(systemName: item.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isSelected ? .black : item.palette.mid)
                            .frame(width: 30, height: 30)
                            .background(isSelected ? AnyShapeStyle(item.palette.mid) : AnyShapeStyle(.white.opacity(0.08)), in: .circle)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.pressable)
                    .help(item.title)
                }
            }
            Spacer(minLength: 4)
            HStack(spacing: 0) {
                glyphButton("minus", size: 15, dim: true, help: "5 minutes less") {
                    startMinutes = max(5, startMinutes - 5)
                }
                .disabled(startMinutes <= 5)
                Spacer(minLength: 0)
                HStack(alignment: .lastTextBaseline, spacing: 5) {
                    Text("\(startMinutes)")
                        .font(.system(size: 40, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(value: Double(startMinutes)))
                        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: startMinutes)
                    Text("min")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer(minLength: 0)
                glyphButton("plus", size: 15, dim: true, help: "5 minutes more") {
                    startMinutes = min(180, startMinutes + 5)
                }
                .disabled(startMinutes >= 180)
            }
            Spacer(minLength: 4)
            Button {
                choosesStart = false
                start(startMode, minutes: startMinutes)
            } label: {
                Label("Start \(startMode.title)", systemImage: "play.fill")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(startMode.palette.mid, in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(.pressable)
            .animation(.easeOut(duration: 0.2), value: startMode)
        }
        .padding(.vertical, 2)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let part = hour < 5 ? "Good night" : hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        return name.isEmpty ? part : "\(part), \(name)"
    }

    private var sessionCard: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let progress = sessionProgress(at: context.date)
            VStack(alignment: .leading, spacing: 0) {
                Label(caption, systemImage: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                HStack(alignment: .center, spacing: 12) {
                    Text(time(at: context.date))
                        .font(.system(size: 34, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(countsDown: !recorder.isActive))
                        .animation(Motion.quick, value: time(at: context.date))
                    Spacer(minLength: 0)
                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.12), lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: progress)
                        Image(systemName: symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    .frame(width: 46, height: 46)
                }
                Spacer(minLength: 8)
                ZStack {
                    if confirmsEnd, engine.isActive {
                        endConfirmation
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    } else {
                        sessionControls
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                .frame(height: 34)
                .animation(.spring(response: 0.3, dampingFraction: 0.88), value: confirmsEnd)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var sessionControls: some View {
        HStack(spacing: 2) {
            if engine.isActive {
                glyphButton(engine.isPaused ? "play.fill" : "pause.fill", size: 21, help: engine.isPaused ? "Resume" : "Pause") {
                    withAnimation(Motion.morph) { engine.togglePause() }
                }
                glyphButton("forward.end.fill", size: 16, help: engine.isResting ? "Skip break" : "Skip round") { engine.skip() }
                glyphButton(soundscape.isEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill", size: 15, dim: true, help: soundscape.isEnabled ? "Mute soundscape" : "Play soundscape") {
                    soundscape.isEnabled.toggle()
                }
                Spacer(minLength: 0)
                glyphButton("stop.fill", size: 15, dim: true, help: "End session") { askToEnd() }
            } else if recorder.isActive {
                glyphButton("stop.fill", size: 20, help: "Stop and save the recording") {
                    recorder.stopNow(engine: engine, enhancer: enhancer, persona: persona)
                }
                Spacer(minLength: 0)
            } else {
                glyphButton("checkmark", size: 20, help: "Done") {
                    withAnimation(Motion.morph) { engine.finish(note: "") }
                }
                glyphButton("doc.text", size: 15, dim: true, help: "See summary") { controller.openApp() }
                Spacer(minLength: 0)
            }
        }
        .padding(.leading, -8)
    }

    private var endConfirmation: some View {
        HStack(spacing: 8) {
            Text("End session?")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 0)
            Button {
                cancelEnd()
            } label: {
                Text("Cancel")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(.white.opacity(0.18), in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(.pressable)
            Button {
                cancelEnd()
                engine.stop()
            } label: {
                Text("End")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .fixedSize()
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(Palette.record, in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(.pressable)
        }
    }

    private func askToEnd() {
        confirmsEnd = true
        endReset?.cancel()
        endReset = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            confirmsEnd = false
        }
    }

    private func cancelEnd() {
        endReset?.cancel()
        confirmsEnd = false
    }

    private var musicCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                artwork(size: 48, radius: 11)
                VStack(alignment: .leading, spacing: 2) {
                    Text(nowPlaying.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(nowPlaying.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                Equalizer(tint: nowPlaying.accent, isPlaying: nowPlaying.isPlaying)
                    .frame(width: 14, height: 12)
            }
            Spacer(minLength: 8)
            Scrubber(nowPlaying: nowPlaying, height: 4)
            Spacer(minLength: 4)
            HStack(spacing: 18) {
                glyphButton("backward.fill", size: 16, help: "Previous") { nowPlaying.previous() }
                glyphButton(nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 23, help: nowPlaying.isPlaying ? "Pause" : "Play") {
                    nowPlaying.togglePlayback()
                }
                glyphButton("forward.fill", size: 16, help: "Next") { nowPlaying.next() }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 4)
        .task { await keepInSync() }
    }

    private func keepInSync() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            nowPlaying.sync()
        }
    }

    private var agendaCard: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(context.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 30, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) { controller.tab = .calendar }
                    } label: {
                        Text(context.date.formatted(.dateTime.weekday(.abbreviated).day()).uppercased())
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xFF453A))
                    }
                    .buttonStyle(.plain)
                    .help("Calendar")
                }
                Spacer(minLength: 8)
                switch calendar.access {
                case .granted:
                    if let next = calendar.upcoming.first {
                        sectionLabel(next.start <= context.date ? "NOW" : "UP NEXT")
                            .padding(.bottom, 5)
                        EventBlock(event: next)
                        if calendar.upcoming.count > 1 {
                            Text("+\(calendar.upcoming.count - 1) more today")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.4))
                                .padding(.top, 5)
                        }
                    } else {
                        Text("No more events today")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                        Text("Your evening is clear")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                case .unknown:
                    Text("See your classes and meetings here")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.5))
                    Button("Connect Calendar") { Task { await calendar.prepare() } }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(.white, in: .capsule)
                        .padding(.top, 6)
                case .denied:
                    Text("FocusKit can't see your calendar")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.5))
                    Button("Open Privacy Settings") { calendar.openSettings() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.top, 4)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var musicTab: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                if nowPlaying.hasTrack {
                    artwork(size: 64, radius: 14)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(0.08))
                        .frame(width: 64, height: 64)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(nowPlaying.hasTrack ? nowPlaying.title : "Not Playing")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(nowPlaying.hasTrack ? 1 : 0.4))
                    if nowPlaying.hasTrack {
                        Text(nowPlaying.artist)
                            .font(.system(size: 13.5))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                Equalizer(tint: nowPlaying.hasTrack ? nowPlaying.accent : .white.opacity(0.25), isPlaying: nowPlaying.isPlaying)
                    .frame(width: 16, height: 14)
            }
            Scrubber(nowPlaying: nowPlaying, height: 5)
            HStack(spacing: 0) {
                playerButton
                Spacer()
                glyphButton("backward.fill", size: 21, help: "Previous") { nowPlaying.previous() }
                    .disabled(!nowPlaying.hasTrack)
                Spacer()
                glyphButton(nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 30, help: nowPlaying.isPlaying ? "Pause" : "Play") {
                    if nowPlaying.hasTrack {
                        nowPlaying.togglePlayback()
                    } else {
                        nowPlaying.play(in: NowPlaying.isInstalled(.spotify) ? .spotify : .music)
                    }
                }
                Spacer()
                glyphButton("forward.fill", size: 21, help: "Next") { nowPlaying.next() }
                    .disabled(!nowPlaying.hasTrack)
                Spacer()
                glyphButton("hifispeaker.2", size: 15, dim: true, help: "Sound output") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task { await keepInSync() }
    }

    private var playerButton: some View {
        let fallback: NowPlaying.Player = NowPlaying.isInstalled(.spotify) ? .spotify : .music
        let bundleID = nowPlaying.hasTrack ? (nowPlaying.appBundleID ?? fallback.rawValue) : fallback.rawValue
        let name = nowPlaying.hasTrack ? nowPlaying.appName : fallback.scriptName
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path(percentEncoded: false)) }
        return Button {
            if nowPlaying.hasTrack {
                nowPlaying.open()
            } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: fallback.rawValue) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        } label: {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "music.note").font(.system(size: 14, weight: .semibold))
                }
            }
            .frame(width: 22, height: 22)
            .frame(width: 30, height: 30)
            .contentShape(.circle)
        }
        .buttonStyle(GlyphButtonStyle())
        .help("Open \(name)")
    }

    private func glyphButton(_ symbol: String, size: CGFloat, dim: Bool = false, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(dim ? 0.55 : 1))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size * 1.8, height: size * 1.8)
                .contentShape(.circle)
        }
        .buttonStyle(GlyphButtonStyle())
        .help(help)
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
        .help(nowPlaying.appName.isEmpty ? "Open player" : "Open \(nowPlaying.appName)")
    }

    private func playbackControls(small: CGFloat, large: CGFloat) -> some View {
        HStack(spacing: small * 0.9) {
            glyphButton("backward.fill", size: small * 0.55, help: "Previous") { nowPlaying.previous() }
            glyphButton(nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: large * 0.62, help: nowPlaying.isPlaying ? "Pause" : "Play") {
                nowPlaying.togglePlayback()
            }
            glyphButton("forward.fill", size: small * 0.55, help: "Next") { nowPlaying.next() }
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

    private func wings<Leading: View, Trailing: View>(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 0) {
            leading()
                .frame(width: IslandController.hudWing - 26, alignment: .leading)
                .padding(.leading, 16)
                .padding(.trailing, 10)
            Spacer(minLength: 0)
            trailing()
                .frame(width: IslandController.hudWing - 26, alignment: .trailing)
                .padding(.leading, 10)
                .padding(.trailing, 16)
        }
        .frame(height: controller.notch.height)
    }

    @ViewBuilder
    private var hud: some View {
        if let event = systemHUD.event {
            let percent = Int((event.value * 100).rounded())
            wings {
                HStack(spacing: 8) {
                    Image(systemName: hudSymbol(event))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(hudTint(event))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 22)
                    Text(hudTitle(event))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            } trailing: {
                HStack(spacing: 8) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.18))
                            Capsule()
                                .fill(hudTint(event))
                                .frame(width: max(5, proxy.size.width * (event.kind == .volume && event.isMuted ? 0 : event.value)))
                                .animation(.spring(response: 0.28, dampingFraction: 1), value: event.value)
                        }
                    }
                    .frame(height: 5)
                    .opacity(event.kind == .volume && event.isMuted ? 0.5 : 1)
                    if showsPercent {
                        Text(event.kind == .volume && event.isMuted ? "" : "\(percent)")
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.7))
                            .contentTransition(.numericText(value: event.value))
                            .animation(Motion.quick, value: percent)
                            .frame(width: 24, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func hudTitle(_ event: SystemHUD.Event) -> String {
        switch event.kind {
        case .volume: event.isMuted ? "Muted" : "Volume"
        case .brightness: "Brightness"
        case .battery: event.isCharging ? "Charging" : "Battery"
        }
    }

    private func hudTint(_ event: SystemHUD.Event) -> Color {
        switch event.kind {
        case .battery:
            if event.isCharging { return Color(hex: 0x34C759) }
            return event.value < 0.2 ? Color(hex: 0xFF453A) : .white
        case .volume, .brightness:
            return .white
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

    private var compact: some View {
        HStack(spacing: 0) {
            leftWing
                .id(wingContent)
                .transition(.blurReplace)
                .frame(width: controller.wing, alignment: .leading)
                .padding(.leading, 14)
            Spacer(minLength: 0)
            rightWing
                .id(wingContent)
                .transition(.blurReplace)
                .frame(width: controller.wing, alignment: .trailing)
                .padding(.trailing, 14)
        }
        .frame(height: controller.notch.height)
        .animation(.easeOut(duration: 0.22), value: wingContent)
    }

    private var wingContent: Int {
        controller.isBusy ? 1 : nowPlaying.hasTrack ? 2 : 0
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
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
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
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Group {
                        if isMusic {
                            artworkThumbnail
                                .frame(width: 22, height: 22)
                                .clipShape(.rect(cornerRadius: 6, style: .continuous))
                        } else {
                            Image(systemName: announcement.symbol)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(announcement.tint)
                                .symbolEffect(.bounce, value: announcement.title)
                        }
                    }
                    .frame(width: IslandController.peekWing - 14, alignment: .leading)
                    .padding(.leading, 14)
                    Spacer(minLength: 0)
                    Group {
                        if isMusic {
                            Equalizer(tint: announcement.tint, isPlaying: nowPlaying.isPlaying)
                                .frame(width: 14, height: 14)
                        } else {
                            Circle()
                                .fill(announcement.tint)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .frame(width: IslandController.peekWing - 14, alignment: .trailing)
                    .padding(.trailing, 14)
                }
                .frame(height: controller.notch.height)
                HStack(spacing: 6) {
                    if isMusic {
                        Image(systemName: "music.note")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Text(announcement.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    if !announcement.detail.isEmpty {
                        Text("·")
                            .foregroundStyle(.white.opacity(0.35))
                        Text(announcement.detail)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(height: IslandController.peekLine - 4)
            }
            .id(announcement)
            .transition(.blurReplace)
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

    private var trayTab: some View {
        HStack(spacing: 10) {
            if tray.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .symbolEffect(.bounce, value: isDropTargeted)
                    Text("Drop files here")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Keep them close, then drag them out or AirDrop them.")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(tray.items) { item in
                            TrayTile(item: item, tray: tray)
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                    }
                    .padding(8)
                }
                .scrollIndicators(.never)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .notchCard()

                VStack(spacing: 6) {
                    trayAction("AirDrop", symbol: "antenna.radiowaves.left.and.right") { tray.airDrop(tray.urls) }
                    ShareLink(items: tray.urls) {
                        trayActionLabel("Share", symbol: "square.and.arrow.up")
                    }
                    .buttonStyle(.pressable)
                    trayAction("Clear", symbol: "xmark") {
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.9)) { tray.clear() }
                    }
                }
                .frame(width: 112)
            }
        }
    }

    private func trayAction(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            trayActionLabel(title, symbol: symbol)
        }
        .buttonStyle(.pressable)
    }

    private func trayActionLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 18)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 14, style: .continuous))
        .contentShape(.rect(cornerRadius: 14))
    }

    @ViewBuilder
    private var clipboardTab: some View {
        switch clipboard.access {
        case .off:
            clipboardMessage(
                symbol: "list.clipboard",
                title: "Clipboard history",
                text: "Keep the last 40 things you copy and copy them again with a click. Passwords are never kept, and nothing is saved to disk.",
                action: "Turn On"
            ) { clipboard.enable() }
        case .needsAlwaysAllow, .denied:
            clipboardMessage(
                symbol: "hand.raised.fill",
                title: "Allow FocusKit to read what you copy",
                text: "In System Settings › Privacy & Security, set FocusKit to Always Allow for pasting from other apps.",
                action: "Open Settings"
            ) { clipboard.openSettings() }
        case .active:
            if clipboard.items.isEmpty {
                clipboardMessage(symbol: "doc.on.doc", title: "Nothing copied yet", text: "Text, links, images and files you copy will show up here.", action: nil) {}
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        sectionLabel("RECENT")
                        Spacer()
                        Button("Clear") {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { clipboard.clear() }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 4)
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                            ForEach(clipboard.items) { item in
                                ClipboardCard(item: item, isCopied: clipboard.copiedID == item.id) {
                                    clipboard.copy(item)
                                } remove: {
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { clipboard.remove(item) }
                                }
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
                .padding(.horizontal, 4)
                .animation(.spring(response: 0.32, dampingFraction: 0.9), value: clipboard.items.map(\.id))
            }
        }
    }

    private func clipboardMessage(symbol: String, title: String, text: String, action: String?, perform: @escaping () -> Void) -> some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 56, height: 56)
                .background(.white.opacity(0.07), in: .rect(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                if let action {
                    HStack(spacing: 10) {
                        Button(action, action: perform)
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 14)
                            .frame(height: 26)
                            .background(.white, in: .capsule)
                        if clipboard.access != .off {
                            Button("Turn Off") { clipboard.disable() }
                                .buttonStyle(.plain)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var calendarTab: some View {
        let system = Calendar.current
        let day = calendar.selected
        let events = calendar.access == .granted ? calendar.events(on: day) : []
        let isToday = system.isDateInToday(day)
        let tomorrow = system.date(byAdding: .day, value: 1, to: system.startOfDay(for: .now)) ?? .now
        let upcoming = isToday && events.isEmpty && calendar.access == .granted ? calendar.events(on: tomorrow) : []
        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xFF453A))
                Text("\(system.component(.day, from: day))")
                    .font(.system(size: 46, weight: .regular))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .padding(.top, -4)
                Spacer(minLength: 0)
                calendarStatus(events: events, isToday: isToday)
            }
            .frame(width: 112, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 6) {
                if !events.isEmpty {
                    if !isToday {
                        sectionLabel(day.formatted(.dateTime.day().month(.abbreviated)))
                    }
                    eventList(events)
                } else if !upcoming.isEmpty {
                    sectionLabel("TOMORROW")
                    eventList(upcoming)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            MonthGrid(calendar: calendar)
                .frame(width: 168)
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: calendar.selected)
    }

    @ViewBuilder
    private func calendarStatus(events: [CalendarStore.Event], isToday: Bool) -> some View {
        switch calendar.access {
        case .granted:
            VStack(alignment: .leading, spacing: 2) {
                Text(events.isEmpty ? (isToday ? "No events today" : "No events") : "\(events.count) \(events.count == 1 ? "event" : "events")")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Text(events.isEmpty ? "Your day is clear" : isToday ? "Today" : calendar.selected.formatted(.dateTime.month(.wide)))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.35))
                if !isToday {
                    Button("Back to today") { calendar.select(.now) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xFF453A))
                        .padding(.top, 4)
                }
            }
        case .unknown:
            VStack(alignment: .leading, spacing: 6) {
                Text("See your classes here")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.5))
                Button("Connect") { Task { await calendar.prepare() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .frame(height: 24)
                    .background(.white, in: .capsule)
            }
        case .denied:
            VStack(alignment: .leading, spacing: 6) {
                Text("No access to Calendar")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.5))
                Button("Open Settings") { calendar.openSettings() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.4))
    }

    private func eventList(_ events: [CalendarStore.Event]) -> some View {
        ScrollView {
            VStack(spacing: 5) {
                ForEach(events) { event in
                    EventBlock(event: event)
                        .transition(.opacity.combined(with: .offset(y: 4)))
                }
            }
        }
        .scrollIndicators(.never)
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

    private func start(_ item: FocusMode, minutes: Int? = nil) {
        engine.startQuick(item, minutes: minutes)
    }
}

private struct Equalizer: View {
    let tint: Color
    let isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: FrameRate.interval(active: false), paused: !isPlaying || reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    let phase = t * (2.6 + Double(index) * 0.9) + Double(index) * 1.7
                    Capsule()
                        .fill(tint)
                        .frame(width: 2.5, height: isPlaying && !reduceMotion ? 4 + 12 * (0.5 + 0.5 * sin(phase)) * (0.6 + 0.4 * sin(phase * 0.37)) : 3 + CGFloat(index % 2) * 2)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isPlaying)
    }
}

private struct MonthGrid: View {
    let calendar: CalendarStore

    var body: some View {
        let system = Calendar.current
        VStack(spacing: 3) {
            HStack(spacing: 0) {
                Text(calendar.month.formatted(.dateTime.month(.wide)).capitalized)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xFF453A))
                Spacer()
                chevron("chevron.left") { calendar.showMonth(offset: -1) }
                chevron("chevron.right") { calendar.showMonth(offset: 1) }
            }
            .padding(.leading, 4)
            HStack(spacing: 0) {
                ForEach(Array(calendar.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 1) {
                ForEach(calendar.days, id: \.self) { day in
                    if system.isDate(day, equalTo: calendar.month, toGranularity: .month) {
                        DayCell(
                            day: system.component(.day, from: day),
                            hasEvents: calendar.hasEvents(on: day),
                            isToday: system.isDateInToday(day),
                            isSelected: system.isDate(day, inSameDayAs: calendar.selected),
                            isWeekend: system.isDateInWeekend(day)
                        ) {
                            calendar.select(day)
                        }
                    } else {
                        Color.clear
                            .frame(height: 22)
                    }
                }
            }
            .id(calendar.month)
            .transition(.opacity)
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.9), value: calendar.month)
    }

    private func chevron(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 20, height: 18)
                .contentShape(.rect)
        }
        .buttonStyle(GlyphButtonStyle())
    }
}

private struct DayCell: View {
    let day: Int
    let hasEvents: Bool
    let isToday: Bool
    let isSelected: Bool
    let isWeekend: Bool
    let select: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: select) {
            VStack(spacing: 1) {
                Text("\(day)")
                    .font(.system(size: 11, weight: isToday ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? .white : .white.opacity(isWeekend ? 0.45 : 0.85))
                    .frame(width: 18, height: 18)
                    .background {
                        Circle()
                            .fill(isToday ? AnyShapeStyle(Color(hex: 0xFF453A)) : AnyShapeStyle(.white.opacity(isSelected ? 0.2 : isHovering ? 0.08 : 0)))
                    }
                Circle()
                    .fill(.white.opacity(hasEvents ? 0.45 : 0))
                    .frame(width: 2.5, height: 2.5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .animation(.spring(response: 0.28, dampingFraction: 1), value: isSelected)
    }
}

private struct EventBlock: View {
    let event: CalendarStore.Event

    var body: some View {
        let isNow = event.start <= .now && event.end > .now
        let isPast = event.end < .now
        let text = event.color.mix(with: .white, by: 0.35)
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(event.color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(text)
                    .lineLimit(1)
                if let location = event.location, !location.isEmpty {
                    Label(location, systemImage: "mappin")
                        .labelStyle(TightLabel())
                        .font(.system(size: 11))
                        .foregroundStyle(text.opacity(0.75))
                        .lineLimit(1)
                }
                Text(event.isAllDay ? "All day" : "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(text.opacity(0.75))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(event.color.opacity(isNow ? 0.3 : 0.18), in: .rect(cornerRadius: 8, style: .continuous))
        .opacity(isPast ? 0.5 : 1)
    }
}

private struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}

private struct GlyphButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GlyphBody(configuration: configuration)
    }

    private struct GlyphBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .opacity(isEnabled ? 1 : 0.35)
                .background {
                    Circle()
                        .fill(.white.opacity(configuration.isPressed ? 0.16 : isHovering && isEnabled ? 0.09 : 0))
                }
                .scaleEffect(configuration.isPressed ? 0.9 : 1)
                .animation(.spring(response: 0.2, dampingFraction: 1), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.12), value: isHovering)
                .onHover { isHovering = $0 }
        }
    }
}

private struct Scrubber: View {
    let nowPlaying: NowPlaying
    var height: CGFloat = 4
    @State private var dragFraction: Double?
    @State private var isHovering = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let duration = nowPlaying.duration
            let hasDuration = nowPlaying.hasTrack && duration > 0
            let elapsed = nowPlaying.elapsed(at: context.date)
            let fraction = dragFraction ?? (hasDuration ? min(1, max(0, elapsed / duration)) : 0)
            let shown = dragFraction.map { $0 * duration } ?? elapsed
            let isActive = hasDuration && (isHovering || dragFraction != nil)
            HStack(spacing: 10) {
                Text(hasDuration ? shown.clock : "-:--")
                    .frame(width: 38, alignment: .leading)
                GeometryReader { proxy in
                    let width = proxy.size.width
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.18))
                        Capsule()
                            .fill(.white.opacity(isActive ? 1 : 0.85))
                            .frame(width: hasDuration ? max(height, width * fraction) : 0)
                    }
                    .frame(height: isActive ? height + 3 : height)
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard hasDuration else { return }
                                dragFraction = min(1, max(0, value.location.x / max(1, width)))
                            }
                            .onEnded { value in
                                guard hasDuration else { return }
                                nowPlaying.seek(to: min(1, max(0, value.location.x / max(1, width))))
                                dragFraction = nil
                            }
                    )
                }
                .frame(height: 14)
                Text(hasDuration ? "-" + max(0, duration - shown).clock : "--:--")
                    .frame(width: 44, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(isActive ? 0.8 : 0.45))
            .animation(.spring(response: 0.25, dampingFraction: 0.9), value: isActive)
        }
        .onHover { isHovering = $0 }
    }
}

private struct ClipboardCard: View {
    let item: ClipboardHistory.Item
    let isCopied: Bool
    let copy: () -> Void
    let remove: () -> Void
    @State private var isHovering = false

    private var preview: String {
        let flat = item.text.split(whereSeparator: \.isNewline).joined(separator: " ")
        return String(flat.trimmingCharacters(in: .whitespaces).prefix(160))
    }

    private var symbol: String {
        switch item.kind {
        case .text: "text.alignleft"
        case .link: "link"
        case .image: "photo"
        case .files: "doc"
        }
    }

    var body: some View {
        Button(action: copy) {
            HStack(spacing: 9) {
                thumbnail
                    .frame(width: 30, height: 30)
                    .clipShape(.rect(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.kind == .image ? "Image" : preview)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(item.kind == .link ? Color(hex: 0x64A8FF) : .white.opacity(0.9))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 4) {
                        if let icon = sourceIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 11, height: 11)
                        }
                        Text(isCopied ? "Copied" : item.date.formatted(.relative(presentation: .named)))
                            .font(.system(size: 10, weight: isCopied ? .semibold : .regular))
                            .foregroundStyle(isCopied ? Color(hex: 0x34C759) : .white.opacity(0.4))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(7)
            .frame(height: 52)
            .background(.white.opacity(isCopied ? 0.12 : isHovering ? 0.1 : 0.055), in: .rect(cornerRadius: 11, style: .continuous))
            .contentShape(.rect(cornerRadius: 11))
        }
        .buttonStyle(.pressable)
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button(action: remove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 16, height: 16)
                        .background(.white.opacity(0.16), in: .circle)
                }
                .buttonStyle(.plain)
                .padding(5)
                .help("Remove")
                .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .animation(.easeOut(duration: 0.15), value: isCopied)
        .help(item.kind == .image ? "Click to copy the image" : "Click to copy")
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = item.image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if item.kind == .files, let url = item.files.first {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
                .resizable()
        } else {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.white.opacity(0.08))
        }
    }

    private var sourceIcon: NSImage? {
        guard let bundleID = item.sourceBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
    }
}

private struct TrayTile: View {
    let item: FileTray.Item
    let tray: FileTray
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let image = tray.thumbnails[item.url] {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                } else {
                    Color.clear
                }
            }
            .frame(width: 58, height: 58)
            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            Text(item.name)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .frame(height: 28, alignment: .top)
        }
        .frame(width: 84)
        .padding(.vertical, 8)
        .background(.white.opacity(isHovering ? 0.09 : 0), in: .rect(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { tray.remove(item) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(.white.opacity(0.22), in: .circle)
                }
                .buttonStyle(.pressable)
                .padding(4)
                .help("Remove from Tray")
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .contentShape(.rect(cornerRadius: 12))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .onTapGesture(count: 2) { tray.open(item) }
        .onDrag {
            NSItemProvider(object: item.url as NSURL)
        }
        .contextMenu {
            Button("Open") { tray.open(item) }
            Button("Show in Finder") { tray.reveal(item) }
            Divider()
            Button("AirDrop") { tray.airDrop([item.url]) }
            ShareLink(item: item.url)
            Button("Copy") { tray.copy(item) }
            Divider()
            Button("Remove from Tray", role: .destructive) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { tray.remove(item) }
            }
        }
        .help(item.name)
        .task(id: item.url) { await tray.loadThumbnail(for: item.url) }
    }
}

private extension View {
    func notchCard() -> some View {
        background(.white.opacity(0.055), in: .rect(cornerRadius: 18, style: .continuous))
            .clipShape(.rect(cornerRadius: 18, style: .continuous))
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
