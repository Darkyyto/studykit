import SwiftUI

struct GoalsScreen: View {
    @Environment(Library.self) private var library
    @AppStorage(Preference.persona) private var persona = Persona.personal
    @Environment(\.present) private var present
    @State private var showsArchived = false

    private var active: [Goal] {
        library.activeGoals.sorted { lhs, rhs in
            switch (lhs.daysUntilDeadline, rhs.daysUntilDeadline) {
            case let (l?, r?): l < r
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): lhs.createdAt > rhs.createdAt
            }
        }
    }

    private var archived: [Goal] {
        library.goals.filter(\.isArchived)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if active.isEmpty {
                    empty
                } else {
                    weekSummary
                    VStack(spacing: 8) {
                        ForEach(active) { goal in
                            GoalRow(goal: goal, persona: persona) { present(.goal(goal)) }
                                .contextMenu { menu(for: goal) }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }

                if !archived.isEmpty {
                    archive
                }
            }
            .frame(maxWidth: 720)
            .padding(.horizontal, 44)
            .padding(.top, 84)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
        .animation(Motion.standard, value: library.goals)
    }

    private var header: some View {
        HStack(alignment: .center) {
            ScreenTitle(title: persona.goalsTitle, subtitle: persona.goalsSubtitle)
            Spacer()
            Button {
                present(.goal(Goal(title: "")))
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Palette.ink, in: .circle)
            }
            .buttonStyle(.pressable)
            .keyboardShortcut("n", modifiers: .command)
            .help("New \(persona.goalNoun) (⌘N)")
        }
    }

    private var weekSummary: some View {
        let week = DateInterval.currentWeek
        let focused = active.reduce(0) { $0 + library.focusedTime(for: $1.id, in: week) }
        let target = TimeInterval(active.reduce(0) { $0 + $1.weeklyTargetMinutes } * 60)
        let fraction = target > 0 ? min(1, focused / target) : 0

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week")
                    .font(.rounded(15, weight: .semibold))
                    .foregroundStyle(Palette.inkSecondary)
                Spacer()
                Text(focused.compactDuration)
                    .font(.numeric(22, weight: .bold))
                    .foregroundStyle(Palette.ink)
                Text("of \(target.compactDuration)")
                    .font(.rounded(14, weight: .medium))
                    .foregroundStyle(Palette.inkSecondary)
            }
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(active) { goal in
                        let share = target > 0 ? library.focusedTime(for: goal.id, in: week) / target : 0
                        if share > 0 {
                            Rectangle()
                                .fill(goal.tint.color)
                                .frame(width: max(4, proxy.size.width * share))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .background(Palette.ink.opacity(0.07))
                .clipShape(.capsule)
            }
            .frame(height: 10)
            Text(fraction >= 1 ? "Weekly target reached. Nice work." : "\(Int(fraction * 100))% of your weekly target")
                .font(.rounded(12, weight: .medium))
                .foregroundStyle(Palette.inkSecondary)
        }
        .padding(20)
        .background(.white.opacity(0.7), in: .rect(cornerRadius: 22))
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "flag.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(FocusMode.orbit.palette.deep.gradient, in: .circle)
            Text("Add your first \(persona.goalNoun)")
                .font(.rounded(20, weight: .bold))
                .foregroundStyle(Palette.ink)
            Text("Give your sessions a direction and a weekly target to aim for.")
                .font(.rounded(14, weight: .medium))
                .foregroundStyle(Palette.inkSecondary)
            Button("New \(persona.goalNoun.capitalized)") { present(.goal(Goal(title: ""))) }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(Palette.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var archive: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(Motion.standard) { showsArchived.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(showsArchived ? 90 : 0))
                    Text("Archived (\(archived.count))")
                        .font(.rounded(13, weight: .semibold))
                }
                .foregroundStyle(Palette.inkSecondary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if showsArchived {
                ForEach(archived) { goal in
                    GoalRow(goal: goal, persona: persona) { present(.goal(goal)) }
                        .opacity(0.6)
                        .contextMenu { menu(for: goal) }
                }
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func menu(for goal: Goal) -> some View {
        Button("Edit…") { present(.goal(goal)) }
        Button(goal.isArchived ? "Restore" : "Archive") {
            var updated = goal
            updated.isArchived.toggle()
            library.save(updated)
        }
        Divider()
        Button("Delete", role: .destructive) { library.delete(goal) }
    }
}

private struct GoalRow: View {
    let goal: Goal
    let persona: Persona
    let edit: () -> Void
    @Environment(Library.self) private var library
    @State private var isHovering = false

    var body: some View {
        let week = library.focusedTime(for: goal.id, in: .currentWeek)
        let target = TimeInterval(goal.weeklyTargetMinutes * 60)
        let fraction = target > 0 ? min(1, week / target) : 0

        Button(action: edit) {
            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(goal.tint.color)
                    .frame(width: 6, height: 40)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(goal.title)
                            .font(.rounded(16, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        if let days = goal.daysUntilDeadline {
                            DeadlineTag(label: persona.deadlineLabel, days: days)
                        }
                    }
                    if let materials {
                        Text(materials)
                            .font(.rounded(12, weight: .medium))
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(goal.tint.color.opacity(0.15))
                            Capsule()
                                .fill(goal.tint.color)
                                .frame(width: max(4, proxy.size.width * fraction))
                        }
                    }
                    .frame(height: 5)
                }

                VStack(alignment: .trailing, spacing: 2) {
                    Text(week.compactDuration)
                        .font(.numeric(15, weight: .bold))
                        .foregroundStyle(Palette.ink)
                    Text("of \(target.compactDuration)")
                        .font(.rounded(11, weight: .medium))
                        .foregroundStyle(Palette.inkTertiary)
                }
                .frame(width: 80, alignment: .trailing)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(.white.opacity(isHovering ? 0.9 : 0.65), in: .rect(cornerRadius: 18))
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(PressableStyle(scale: 0.99))
        .onHover { isHovering = $0 }
        .animation(Motion.quick, value: isHovering)
    }

    private var materials: String? {
        let recordings = library.recordings.filter { $0.goalID == goal.id }
        var cards = 0
        for recording in recordings {
            for section in recording.notes?.sections ?? [] where section.style == .flashcards {
                cards += section.items.count
            }
        }
        for document in library.documents where document.goalID == goal.id {
            cards += document.flashcards.count
        }
        var parts: [String] = []
        if !recordings.isEmpty {
            let noun = persona == .professional ? "meeting" : "lecture"
            parts.append("\(recordings.count) \(noun)\(recordings.count == 1 ? "" : "s")")
        }
        if cards > 0, persona != .professional {
            parts.append("\(cards) flashcards")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private struct DeadlineTag: View {
    let label: String
    let days: Int

    private var isUrgent: Bool {
        (0...3).contains(days)
    }

    var body: some View {
        Text(text)
            .font(.rounded(11, weight: .bold))
            .foregroundStyle(isUrgent ? Palette.record : Palette.inkSecondary)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background((isUrgent ? Palette.record : Palette.ink).opacity(0.08), in: .capsule)
    }

    private var text: String {
        switch days {
        case ..<0: "\(label) passed"
        case 0: "\(label) today"
        case 1: "\(label) tomorrow"
        default: "\(label) in \(days)d"
        }
    }
}

struct ProgressRing: View {
    let progress: Double
    let tint: Color
    var lineWidth: CGFloat = 7

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, progress))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(Motion.settle, value: progress)
    }
}
