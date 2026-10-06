import SwiftUI
import UniformTypeIdentifiers

struct SubjectDetail: View {
    let goalID: Goal.ID
    @Environment(Library.self) private var library
    @Environment(\.closeCard) private var close
    @Environment(\.present) private var present
    @AppStorage(Preference.persona) private var persona = Persona.personal
    @State private var importsDocument = false

    private var goal: Goal? {
        library.goal(goalID)
    }

    private var recordings: [Recording] {
        library.recordings
            .filter { $0.goalID == goalID && $0.stage != .recording }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var documents: [StudyDocument] {
        library.documents
            .filter { $0.goalID == goalID }
            .sorted { $0.openedAt > $1.openedAt }
    }

    private var sessions: [Session] {
        library.sessions
            .filter { $0.goalID == goalID }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private var flashcards: Int {
        recordings.reduce(0) { total, recording in
            total + (recording.notes?.sections ?? []).filter { $0.style == .flashcards }.reduce(0) { $0 + $1.items.count }
        } + documents.reduce(0) { $0 + $1.flashcards.count }
    }

    var body: some View {
        if let goal {
            VStack(alignment: .leading, spacing: 0) {
                header(goal)
                    .padding(28)
                    .padding(.bottom, -8)
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        stats(goal)
                        lectures(goal)
                        documentsSection(goal)
                        if !sessions.isEmpty {
                            history(goal)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.never)
            }
            .animation(Motion.standard, value: recordings.map(\.id))
            .animation(Motion.standard, value: documents.map(\.id))
            .fileImporter(isPresented: $importsDocument, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                for url in urls {
                    if var document = PDFImport.open(url, into: library) {
                        document.goalID = goalID
                        library.save(document)
                    }
                }
            }
        } else {
            Color.clear.onAppear { close() }
        }
    }

    private func header(_ goal: Goal) -> some View {
        HStack(alignment: .top, spacing: 16) {
            RoundedRectangle(cornerRadius: 14)
                .fill(goal.tint.color.gradient)
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: persona == .professional ? "briefcase.fill" : persona == .student ? "book.closed.fill" : "flag.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: goal.tint.color.opacity(0.35), radius: 10, y: 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(goal.title)
                    .font(.rounded(28, weight: .bold))
                    .displayTracking(28)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if let days = goal.daysUntilDeadline {
                        Text(deadlineText(days))
                            .font(.rounded(12, weight: .bold))
                            .foregroundStyle(goal.tint.color)
                            .padding(.horizontal, 9)
                            .frame(height: 22)
                            .background(goal.tint.color.opacity(0.12), in: .capsule)
                    }
                    if !goal.notes.isEmpty {
                        Text(goal.notes)
                            .font(.rounded(13, weight: .medium))
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Button("Edit") { present(.goal(goal)) }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                Button("Done") { close() }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(goal.tint.color)
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    private func stats(_ goal: Goal) -> some View {
        let week = library.focusedTime(for: goal.id, in: .currentWeek)
        let total = library.focusedTime(for: goal.id)
        let target = TimeInterval(goal.weeklyTargetMinutes * 60)
        return HStack(spacing: 10) {
            stat("This week", value: week.compactDuration, detail: "of \(target.compactDuration)", progress: target > 0 ? min(1, week / target) : nil, tint: goal.tint.color)
            stat("All time", value: total.compactDuration, detail: "\(sessions.count) sessions", progress: nil, tint: goal.tint.color)
            stat(persona.recordingsTitle, value: "\(recordings.count)", detail: recordings.isEmpty ? "none yet" : recordings.reduce(0) { $0 + $1.duration }.compactDuration, progress: nil, tint: goal.tint.color)
            stat("Flashcards", value: "\(flashcards)", detail: "\(documents.count) PDF\(documents.count == 1 ? "" : "s")", progress: nil, tint: goal.tint.color)
        }
    }

    private func stat(_ title: String, value: String, detail: String, progress: Double?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.rounded(12, weight: .semibold))
                .foregroundStyle(Palette.inkSecondary)
            Text(value)
                .font(.numeric(22, weight: .bold))
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText())
            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(tint)
            } else {
                Text(detail)
                    .font(.rounded(11, weight: .medium))
                    .foregroundStyle(Palette.inkTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Palette.canvas, in: .rect(cornerRadius: 18))
    }

    private func lectures(_ goal: Goal) -> some View {
        let available = library.recordings.filter { $0.goalID != goalID && $0.stage != .recording }.sorted { $0.createdAt > $1.createdAt }
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader(persona.recordingsTitle) {
                Menu {
                    ForEach(available.prefix(20)) { recording in
                        Button("\(recording.title) · \(recording.createdAt.formatted(date: .abbreviated, time: .omitted))") {
                            assign(recording, to: goalID)
                        }
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .disabled(available.isEmpty)
            }
            if recordings.isEmpty {
                placeholder("Lectures you record for \(goal.title) appear here. You can also add ones you already have.")
            } else {
                ForEach(recordings) { recording in
                    row(
                        symbol: "waveform",
                        tint: goal.tint.color,
                        title: recording.title,
                        detail: "\(recording.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(recording.duration.compactDuration)",
                        badge: recording.notes.map { notes in
                            let cards = notes.sections.filter { $0.style == .flashcards }.reduce(0) { $0 + $1.items.count }
                            return cards > 0 ? "\(cards) card\(cards == 1 ? "" : "s")" : "Notes"
                        }
                    ) {
                        present(.recording(recording))
                    }
                    .contextMenu {
                        Button("Open") { present(.recording(recording)) }
                        Button("Remove from \(goal.title)") { assign(recording, to: nil) }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func documentsSection(_ goal: Goal) -> some View {
        let available = library.documents.filter { $0.goalID != goalID }
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Documents") {
                Menu {
                    Button("Import PDF…") { importsDocument = true }
                    if !available.isEmpty {
                        Divider()
                        ForEach(available.prefix(20)) { document in
                            Button(document.title) {
                                var moved = document
                                moved.goalID = goalID
                                library.save(moved)
                            }
                        }
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
            if documents.isEmpty {
                placeholder("Slides, handouts and books for \(goal.title). Drop in a PDF to read it in a session.")
            } else {
                ForEach(documents) { document in
                    row(
                        symbol: "doc.text.fill",
                        tint: goal.tint.color,
                        title: document.title,
                        detail: "\(document.pageCount) pages · \(Int(document.progress * 100))% read",
                        badge: document.flashcards.isEmpty ? nil : "\(document.flashcards.count) card\(document.flashcards.count == 1 ? "" : "s")"
                    ) {
                        library.pendingDocumentID = document.id
                        close()
                        NotificationCenter.default.post(name: .showFocus, object: nil)
                    }
                    .contextMenu {
                        Button("Study in a Session") {
                            library.pendingDocumentID = document.id
                            close()
                            NotificationCenter.default.post(name: .showFocus, object: nil)
                        }
                        Button("Open in Preview") { NSWorkspace.shared.open(library.url(for: document)) }
                        Button("Remove from \(goal.title)") {
                            var moved = document
                            moved.goalID = nil
                            library.save(moved)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func history(_ goal: Goal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Recent sessions") { EmptyView() }
            VStack(spacing: 0) {
                ForEach(sessions.prefix(5)) { session in
                    HStack {
                        Image(systemName: session.mode.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(session.mode.palette.deep)
                            .frame(width: 24)
                        Text(session.intention.isEmpty ? (session.kind?.title ?? session.mode.title) : session.intention)
                            .font(.rounded(14, weight: .medium))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Spacer()
                        Text("\(session.focused.compactDuration) · \(session.startedAt.formatted(.dateTime.day().month(.abbreviated)))")
                            .font(.rounded(12, weight: .medium))
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(.vertical, 9)
                    .padding(.horizontal, 12)
                }
            }
            .background(Palette.canvas, in: .rect(cornerRadius: 16))
        }
    }

    private func sectionHeader<Accessory: View>(_ title: String, @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack {
            Text(title)
                .font(.rounded(17, weight: .bold))
                .foregroundStyle(Palette.ink)
            Spacer()
            accessory()
                .menuStyle(.button)
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .fixedSize()
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.rounded(13, weight: .medium))
            .foregroundStyle(Palette.inkTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Palette.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
            }
    }

    private func row(symbol: String, tint: Color, title: String, detail: String, badge: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(tint.gradient, in: .rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.rounded(14, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(detail)
                        .font(.rounded(12, weight: .medium))
                        .foregroundStyle(Palette.inkSecondary)
                }
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.rounded(11, weight: .bold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(tint.opacity(0.12), in: .capsule)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.inkTertiary)
            }
            .padding(10)
            .background(Palette.canvas, in: .rect(cornerRadius: 16))
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.pressable)
    }

    private func assign(_ recording: Recording, to goalID: Goal.ID?) {
        var moved = recording
        moved.goalID = goalID
        library.save(moved)
    }

    private func deadlineText(_ days: Int) -> String {
        let label = persona.deadlineLabel
        switch days {
        case ..<0: return "\(label) passed"
        case 0: return "\(label) today"
        case 1: return "\(label) tomorrow"
        default: return "\(label) in \(days) days"
        }
    }
}

extension Notification.Name {
    static let showFocus = Notification.Name("FocusKitShowFocus")
}
