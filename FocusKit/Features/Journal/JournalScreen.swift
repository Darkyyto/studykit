import Charts
import SwiftUI

struct JournalScreen: View {
    @Environment(Library.self) private var library

    private var stats: JournalStats {
        JournalStats(sessions: library.sessions)
    }

    var body: some View {
        let stats = stats
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ScreenTitle(title: "Journal", subtitle: "How your focus has been adding up.")

                HStack(spacing: 16) {
                    tile(label: "Total focus", value: stats.total.hours, unit: "h", symbol: "hourglass", tint: FocusMode.orbit.palette.deep)
                    tile(label: "This week", value: "\(Int(stats.thisWeek / 60))", unit: "min", symbol: "calendar", tint: FocusMode.flight.palette.deep)
                    tile(label: "Streak", value: "\(stats.streak)", unit: stats.streak == 1 ? "day" : "days", symbol: "flame.fill", tint: Palette.rest.deep)
                    tile(label: "Completed", value: "\(stats.completionRate)", unit: "%", symbol: "checkmark.seal.fill", tint: FocusMode.bloom.palette.deep)
                }

                HStack(alignment: .top, spacing: 16) {
                    GlassCard(radius: 30, padding: 22) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Last 7 days")
                                .font(.rounded(16, weight: .bold))
                                .foregroundStyle(Palette.ink)
                            WeekChart(days: stats.lastSevenDays)
                                .frame(height: 170)
                        }
                    }
                    GlassCard(radius: 30, padding: 22) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("By mode")
                                .font(.rounded(16, weight: .bold))
                                .foregroundStyle(Palette.ink)
                            ModeBreakdown(minutes: stats.minutesByMode)
                        }
                    }
                    .frame(width: 300)
                }

                GlassCard(radius: 30, padding: 22) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Last 20 weeks")
                                .font(.rounded(16, weight: .bold))
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            Text("\(stats.completed) completed · \(stats.stopped) ended early")
                                .font(.rounded(12, weight: .medium))
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        FocusHeatmap(minutesByDay: stats.minutesByDay)
                    }
                }

                history
            }
            .padding(.horizontal, 44)
            .padding(.top, 84)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.never)

    }

    private func tile(label: String, value: String, unit: String, symbol: String, tint: Color) -> some View {
        GlassCard(radius: 26, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(tint.gradient, in: .circle)
                Stat(label: label, value: value, unit: unit, size: 26)
            }
        }
    }

    private var history: some View {
        GlassCard(radius: 30, padding: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sessions")
                    .font(.rounded(16, weight: .bold))
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 6)

                let sessions = library.sessions.sorted { $0.startedAt > $1.startedAt }
                if sessions.isEmpty {
                    Text("Your finished sessions will appear here.")
                        .font(.rounded(14, weight: .medium))
                        .foregroundStyle(Palette.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(sessions) { session in
                            SessionRow(session: session, goal: library.goal(session.goalID))
                                .contextMenu {
                                    Button("Remove from Journal", role: .destructive) {
                                        withAnimation(Motion.standard) { library.delete(session) }
                                    }
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .animation(Motion.standard, value: sessions.map(\.id))
                }
            }
        }
    }
}

private struct SessionRow: View {
    let session: Session
    let goal: Goal?
    @Environment(Library.self) private var library
    @Environment(NoteEnhancer.self) private var enhancer
    @State private var isHovering = false
    @State private var isExpanded = false
    @Environment(\.present) private var present

    private var recording: Recording? {
        session.recordingID.flatMap { id in library.recordings.first { $0.id == id } }
    }

    private var hasDetails: Bool {
        recording != nil || session.notes != nil || !(session.tasks ?? []).isEmpty || !(session.parked ?? []).isEmpty || !session.note.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: session.kind?.symbol ?? session.mode.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(session.mode.palette.deep)
                    .frame(width: 38, height: 38)
                    .background(session.mode.palette.light, in: .circle)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.rounded(14, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(session.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                        if let kind = session.kind {
                            Text("· \(kind.title)")
                        }
                        if let goal {
                            Circle().fill(goal.tint.color).frame(width: 5, height: 5)
                            Text(goal.title)
                        }
                        if let tasks = session.tasks, !tasks.isEmpty {
                            Text("· \(tasks.count { $0.isDone })/\(tasks.count) tasks")
                        }
                        if let pages = session.pages {
                            Text("· pp. \(pages.lowerBound + 1)–\(pages.upperBound + 1)")
                        }
                    }
                    .font(.rounded(12, weight: .medium))
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
                }

                Spacer()

                Text(session.focused.compactDuration)
                    .font(.numeric(14, weight: .semibold))
                    .foregroundStyle(Palette.ink)

                Image(systemName: session.outcome == .completed ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(session.outcome == .completed ? FocusMode.bloom.palette.deep : Palette.inkTertiary)
                    .help(session.outcome == .completed ? "Completed" : "Ended early")

                if hasDetails {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.inkTertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }

            if isExpanded {
                details
                    .padding(.leading, 52)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Palette.surface.opacity(isHovering || isExpanded ? 0.6 : 0), in: .rect(cornerRadius: 18))
        .contentShape(.rect)
        .onTapGesture {
            guard hasDetails else { return }
            withAnimation(Motion.standard) { isExpanded.toggle() }
        }
        .animation(Motion.quick, value: isHovering)
        .onHover { isHovering = $0 }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let recording {
                recordingCard(recording)
            }
            if !session.note.isEmpty {
                Text(session.note)
                    .font(.rounded(13, weight: .medium))
                    .foregroundStyle(Palette.ink)
            }
            if let notes = session.notes {
                Text(notes)
                    .font(.rounded(13, weight: .medium))
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(8)
                    .textSelection(.enabled)
            }
            if let tasks = session.tasks, !tasks.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(tasks) { task in
                        Label(task.title, systemImage: task.isDone ? "checkmark.circle.fill" : "circle")
                            .font(.rounded(13, weight: .medium))
                            .foregroundStyle(task.isDone ? Palette.inkSecondary : Palette.ink)
                    }
                }
            }
            if let parked = session.parked, !parked.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Parked")
                        .font(.rounded(11, weight: .bold))
                        .foregroundStyle(Palette.inkTertiary)
                    ForEach(parked, id: \.self) { thought in
                        Label(thought, systemImage: "tray.and.arrow.down")
                            .font(.rounded(13, weight: .medium))
                            .foregroundStyle(Palette.ink)
                    }
                }
            }
        }
    }

    private func recordingCard(_ recording: Recording) -> some View {
        let isLecture = session.kind == .lecture
        let cards = recording.notes?.sections.first { $0.style == .flashcards }?.items.count ?? 0
        return Button {
            present(.recording(recording))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isLecture ? "graduationcap.fill" : "person.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(FocusMode.orbit.palette.deep.gradient, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isLecture ? "Lecture notes" : "Meeting minutes")
                        .font(.rounded(13, weight: .bold))
                        .foregroundStyle(Palette.ink)
                    Text(subtitle(for: recording, cards: cards))
                        .font(.rounded(12, weight: .medium))
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.inkTertiary)
            }
            .padding(10)
            .background(FocusMode.orbit.palette.light.opacity(0.7), in: .rect(cornerRadius: 14))
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
    }

    private func subtitle(for recording: Recording, cards: Int) -> String {
        if enhancer.isWorking(on: recording) { return "Writing your notes…" }
        guard let notes = recording.notes else { return "\(recording.duration.compactDuration) recorded · transcript ready" }
        return cards > 0 ? "\(cards) flashcards · \(notes.summary)" : notes.summary
    }

    private var title: String {
        if !session.intention.isEmpty { return session.intention }
        if session.mode == .flight, let route = session.route {
            return "\(route.origin) → \(route.destination)"
        }
        return session.kind?.title ?? session.mode.title
    }
}

private struct WeekChart: View {
    let days: [(day: Date, minutes: [FocusMode: Double])]

    var body: some View {
        Chart {
            ForEach(days, id: \.day) { entry in
                ForEach(FocusMode.allCases) { mode in
                    BarMark(
                        x: .value("Day", entry.day, unit: .day),
                        y: .value("Minutes", entry.minutes[mode] ?? 0),
                        width: .ratio(0.55)
                    )
                    .foregroundStyle(by: .value("Mode", mode.title))
                    .clipShape(.rect(cornerRadius: 6))
                }
            }
        }
        .chartForegroundStyleScale(
            domain: FocusMode.allCases.map(\.title),
            range: FocusMode.allCases.map(\.palette.deep)
        )
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow))
                    .font(.rounded(11, weight: .semibold))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    .foregroundStyle(Palette.hairline)
                AxisValueLabel()
                    .font(.rounded(10, weight: .medium))
            }
        }
    }
}

private struct ModeBreakdown: View {
    let minutes: [FocusMode: Double]

    var body: some View {
        let total = max(1, minutes.values.reduce(0, +))
        VStack(spacing: 14) {
            ForEach(FocusMode.allCases) { mode in
                let value = minutes[mode] ?? 0
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(mode.title, systemImage: mode.symbol)
                            .font(.rounded(13, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Text(TimeInterval(value * 60).compactDuration)
                            .font(.numeric(12, weight: .medium))
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(mode.palette.light)
                            Capsule()
                                .fill(mode.palette.deep.gradient)
                                .frame(width: max(8, proxy.size.width * value / total))
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
    }
}

struct JournalStats {
    let total: TimeInterval
    let thisWeek: TimeInterval
    let streak: Int
    let completed: Int
    let stopped: Int
    let minutesByDay: [Date: Double]
    let minutesByMode: [FocusMode: Double]
    let lastSevenDays: [(day: Date, minutes: [FocusMode: Double])]

    var completionRate: Int {
        completed + stopped == 0 ? 0 : Int((Double(completed) / Double(completed + stopped) * 100).rounded())
    }

    init(sessions: [Session], calendar: Calendar = .current, now: Date = .now) {
        total = sessions.reduce(0) { $0 + $1.focused }
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        thisWeek = sessions.filter { week?.contains($0.startedAt) ?? false }.reduce(0) { $0 + $1.focused }
        completed = sessions.count { $0.outcome == .completed }
        stopped = sessions.count { $0.outcome == .stopped }

        var byDay: [Date: Double] = [:]
        var byMode: [FocusMode: Double] = [:]
        var byDayAndMode: [Date: [FocusMode: Double]] = [:]
        for session in sessions {
            let day = calendar.startOfDay(for: session.startedAt)
            let minutes = session.focused / 60
            byDay[day, default: 0] += minutes
            byMode[session.mode, default: 0] += minutes
            byDayAndMode[day, default: [:]][session.mode, default: 0] += minutes
        }
        minutesByDay = byDay
        minutesByMode = byMode

        let today = calendar.startOfDay(for: now)
        lastSevenDays = (0..<7).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { ($0, byDayAndMode[$0] ?? [:]) }
        }

        var day = today
        if byDay[day] == nil, let yesterday = calendar.date(byAdding: .day, value: -1, to: day) {
            day = yesterday
        }
        var streak = 0
        while byDay[day] != nil {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        self.streak = streak
    }
}

