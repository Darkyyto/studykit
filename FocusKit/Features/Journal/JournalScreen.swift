import Charts
import SwiftUI

struct JournalScreen: View {
    @Environment(Library.self) private var library
    @AppStorage(Preference.focusMode) private var mode = FocusMode.flight

    private var stats: JournalStats {
        JournalStats(sessions: library.sessions)
    }

    var body: some View {
        let stats = stats
        let accent = mode.tone
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ScreenTitle(title: "Journal", subtitle: "How your focus has been adding up.")

                HStack(alignment: .top, spacing: 16) {
                    JournalCard(padding: 22) {
                        WeekChart(days: stats.lastSevenDays, thisWeek: stats.thisWeek, accent: accent)
                    }
                    VStack(spacing: 12) {
                        metric("Streak", value: "\(stats.streak)", unit: stats.streak == 1 ? "day" : "days", symbol: "flame.fill", tint: Palette.rest.deep)
                        metric("All Time", value: stats.total.hours, unit: "h", symbol: "hourglass", tint: accent)
                        metric("Completed", value: "\(stats.completionRate)", unit: "%", symbol: "checkmark.circle.fill", tint: FocusMode.bloom.tone)
                    }
                    .frame(width: 230)
                }
                .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 16) {
                    section("By Mode") {
                        JournalCard {
                            ModeBreakdown(minutes: stats.minutesByMode)
                        }
                    }
                    .frame(width: 330)
                    section("Activity") {
                        JournalCard {
                            FocusHeatmap(minutesByDay: stats.minutesByDay, tint: accent)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                history
            }
            .frame(maxWidth: 980, alignment: .leading)
            .padding(.horizontal, 44)
            .padding(.top, 84)
            .padding(.bottom, 44)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
    }

    private func metric(_ label: String, value: String, unit: String, symbol: String, tint: Color) -> some View {
        JournalCard(padding: 16) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.rounded(12, weight: .medium))
                        .foregroundStyle(Palette.inkSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(value)
                            .font(.numeric(22, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .contentTransition(.numericText())
                        Text(unit)
                            .font(.rounded(13, weight: .medium))
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func section<Content: View>(_ title: String, detail: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.rounded(17, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(.rounded(12, weight: .medium))
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .padding(.horizontal, 4)
            content()
        }
    }

    private var history: some View {
        let sessions = library.sessions.sorted { $0.startedAt > $1.startedAt }
        let days = Dictionary(grouping: sessions) { Calendar.current.startOfDay(for: $0.startedAt) }
            .sorted { $0.key > $1.key }
        return section("Sessions", detail: sessions.isEmpty ? nil : "\(sessions.count) total") {
            if sessions.isEmpty {
                JournalCard {
                    Text("Your finished sessions will appear here.")
                        .font(.rounded(13, weight: .medium))
                        .foregroundStyle(Palette.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                }
            } else {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(days, id: \.key) { day, entries in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(dayTitle(day))
                                Spacer()
                                Text(entries.reduce(0) { $0 + $1.focused }.compactDuration)
                                    .monospacedDigit()
                            }
                            .font(.rounded(12, weight: .semibold))
                            .foregroundStyle(Palette.inkSecondary)
                            .padding(.horizontal, 6)

                            JournalCard(padding: 0) {
                                VStack(spacing: 0) {
                                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, session in
                                        if index > 0 {
                                            Divider().padding(.leading, 56)
                                        }
                                        SessionRow(session: session, goal: library.goal(session.goalID))
                                            .contextMenu {
                                                Button("Remove from Journal", role: .destructive) {
                                                    withAnimation(Motion.standard) { library.delete(session) }
                                                }
                                            }
                                    }
                                }
                                .clipShape(.rect(cornerRadius: 16, style: .continuous))
                            }
                        }
                        .transition(.opacity)
                    }
                }
                .animation(Motion.standard, value: sessions.map(\.id))
            }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let title: String
        if let days = calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: .now)).day, days < 7 {
            title = day.formatted(.dateTime.weekday(.wide))
        } else if calendar.isDate(day, equalTo: .now, toGranularity: .year) {
            title = day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        } else {
            title = day.formatted(.dateTime.day().month(.wide).year())
        }
        return title.prefix(1).uppercased() + title.dropFirst()
    }
}

extension FocusMode {
    var tone: Color {
        switch self {
        case .flight: Color(light: 0x2F86E8, dark: 0x7DBBFF)
        case .orbit: Color(light: 0x6650E6, dark: 0xA99CFF)
        case .bloom: Color(light: 0x2FA35E, dark: 0x7DD6A0)
        case .tide: Color(light: 0x14939B, dark: 0x66CFD4)
        }
    }
}

private enum JournalTone {
    static let fill = Color(light: 0xFFFFFF, lightAlpha: 0.62, dark: 0xFFFFFF, darkAlpha: 0.055)
    static let edge = Color(light: 0xFFFFFF, lightAlpha: 0.9, dark: 0xFFFFFF, darkAlpha: 0.08)
}

private struct JournalCard<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(JournalTone.fill, in: .rect(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(JournalTone.edge, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
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

    private var meta: String {
        var parts = [session.startedAt.formatted(date: .omitted, time: .shortened)]
        if let kind = session.kind { parts.append(kind.title) }
        if let goal { parts.append(goal.title) }
        if let tasks = session.tasks, !tasks.isEmpty { parts.append("\(tasks.count { $0.isDone })/\(tasks.count) tasks") }
        if let pages = session.pages { parts.append("pp. \(pages.lowerBound + 1)–\(pages.upperBound + 1)") }
        if session.outcome != .completed { parts.append("Ended early") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: session.kind?.symbol ?? session.mode.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(session.mode.tone.gradient, in: .rect(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.rounded(13, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(meta)
                        .font(.rounded(12))
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Text(session.focused.compactDuration)
                    .font(.numeric(13, weight: .medium))
                    .foregroundStyle(session.outcome == .completed ? Palette.ink : Palette.inkSecondary)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.inkTertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .opacity(hasDetails ? 1 : 0)
            }

            if isExpanded {
                details
                    .padding(.leading, 40)
                    .padding(.bottom, 4)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Palette.ink.opacity(isHovering && hasDetails ? 0.035 : 0))
        .contentShape(.rect)
        .onTapGesture {
            guard hasDetails else { return }
            withAnimation(Motion.standard) { isExpanded.toggle() }
        }
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
    let thisWeek: TimeInterval
    let accent: Color
    @State private var isRevealed = false

    var body: some View {
        let totals = days.map { $0.minutes.values.reduce(0, +) }
        let average = totals.reduce(0, +) / Double(max(1, days.count))
        let peak = max(30, (totals.max() ?? 0) * 1.08)
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("This Week")
                        .font(.rounded(12, weight: .medium))
                        .foregroundStyle(Palette.inkSecondary)
                    Text(thisWeek.compactDuration)
                        .font(.numeric(30, weight: .semibold))
                        .displayTracking(30)
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Daily Average")
                        .font(.rounded(12, weight: .medium))
                        .foregroundStyle(Palette.inkSecondary)
                    Text(TimeInterval(average * 60).compactDuration)
                        .font(.numeric(17, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }

            Chart {
                ForEach(Array(zip(days, totals)), id: \.0.day) { entry, total in
                    BarMark(x: .value("Day", entry.day, unit: .day), y: .value("Track", peak), width: .ratio(0.3))
                        .foregroundStyle(accent.opacity(0.1))
                        .clipShape(.capsule)
                    BarMark(x: .value("Day", entry.day, unit: .day), y: .value("Minutes", isRevealed ? max(total, total > 0 ? peak * 0.06 : 0) : 0), width: .ratio(0.3), stacking: .unstacked)
                        .foregroundStyle(LinearGradient(colors: [accent.opacity(0.75), accent], startPoint: .bottom, endPoint: .top))
                        .clipShape(.capsule)
                        .opacity(Calendar.current.isDateInToday(entry.day) ? 1 : 0.78)
                }
                if average > 0 {
                    RuleMark(y: .value("Average", average))
                        .lineStyle(StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2, 4]))
                        .foregroundStyle(Palette.inkTertiary)
                }
            }
            .chartYScale(domain: 0...peak)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                        .font(.rounded(11, weight: isToday(value) ? .semibold : .medium))
                        .foregroundStyle(isToday(value) ? Palette.ink : Palette.inkTertiary)
                }
            }
            .frame(height: 170)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.9, bounce: 0).delay(0.1)) { isRevealed = true }
        }
    }

    private func isToday(_ value: AxisValue) -> Bool {
        value.as(Date.self).map { Calendar.current.isDateInToday($0) } ?? false
    }
}

private struct ModeBreakdown: View {
    let minutes: [FocusMode: Double]
    @State private var isRevealed = false

    var body: some View {
        let peak = max(1, minutes.values.max() ?? 0)
        let total = minutes.values.reduce(0, +)
        VStack(spacing: 16) {
            ForEach(FocusMode.allCases) { mode in
                let value = minutes[mode] ?? 0
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(mode.tone)
                            .frame(width: 16)
                        Text(mode.title)
                            .font(.rounded(13, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Text(TimeInterval(value * 60).compactDuration)
                            .font(.numeric(12, weight: .medium))
                            .foregroundStyle(Palette.inkSecondary)
                        if total > 0 {
                            Text("\(Int((value / total * 100).rounded()))%")
                                .font(.numeric(12, weight: .medium))
                                .foregroundStyle(Palette.inkTertiary)
                                .frame(width: 34, alignment: .trailing)
                        }
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(mode.tone.opacity(0.12))
                            Capsule()
                                .fill(LinearGradient(colors: [mode.tone.opacity(0.75), mode.tone], startPoint: .leading, endPoint: .trailing))
                                .frame(width: value > 0 ? max(6, proxy.size.width * (isRevealed ? value / peak : 0)) : 0)
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.9, bounce: 0).delay(0.15)) { isRevealed = true }
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

