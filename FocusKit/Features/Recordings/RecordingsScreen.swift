import SwiftUI

struct RecordingsScreen: View {
    @Environment(Library.self) private var library
    @Environment(VoiceRecorder.self) private var recorder
    @Environment(NoteEnhancer.self) private var enhancer
    @Environment(FocusEngine.self) private var engine
    @AppStorage(Preference.persona) private var persona = Persona.personal
    @State private var query = ""
    @State private var goalFilter: Goal.ID?
    @Environment(\.present) private var present
    @State private var renaming: Recording?
    @State private var newTitle = ""
    @State private var deleting: Recording?
    @State private var merging: [Recording] = []
    @State private var selecting = false
    @State private var selection: Set<Recording.ID> = []
    @State private var deletingSelection = false
    @State private var mergeError: String?

    private var visible: [Recording] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        return library.recordings
            .filter { $0.stage != .recording }
            .filter { goalFilter == nil || $0.goalID == goalFilter }
            .filter { recording in
                needle.isEmpty
                    || recording.title.localizedStandardContains(needle)
                    || recording.transcript.localizedStandardContains(needle)
                    || (recording.notes?.text.localizedStandardContains(needle) ?? false)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var days: [(day: Date, recordings: [Recording])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: visible) { calendar.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    private var goals: [Goal] {
        let used = Set(library.recordings.compactMap(\.goalID))
        return library.goals.filter { used.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center) {
                    ScreenTitle(title: persona.recordingsTitle, subtitle: persona.recordingsSubtitle)
                    Spacer()
                    if library.recordings.contains(where: { $0.stage != .recording }) {
                        Button(selecting ? "Done" : "Select") {
                            withAnimation(Motion.standard) {
                                selecting.toggle()
                                selection = []
                            }
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                        .keyboardShortcut(selecting ? .cancelAction : nil)
                    }
                }

                if case .recording(let since) = recorder.state {
                    LiveCard(since: since, levels: recorder.levels, text: recorder.volatileText.isEmpty ? recorder.finalizedText : recorder.volatileText) {
                        recorder.stopNow(engine: engine, enhancer: enhancer, persona: persona)
                    }
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }

                if library.recordings.contains(where: { $0.stage != .recording }) {
                    controls
                    if days.isEmpty {
                        Text("Nothing matches “\(query)”.")
                            .font(.rounded(15, weight: .medium))
                            .foregroundStyle(Palette.inkSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                    ForEach(days, id: \.day) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(entry.day.relativeDayTitle)
                                .font(.rounded(13, weight: .bold))
                                .foregroundStyle(Palette.inkSecondary)
                                .padding(.leading, 4)
                            ForEach(entry.recordings) { recording in
                                RecordingRow(recording: recording, persona: persona, isSelected: selecting ? selection.contains(recording.id) : nil) {
                                    if selecting {
                                        withAnimation(Motion.quick) {
                                            if selection.contains(recording.id) {
                                                selection.remove(recording.id)
                                            } else {
                                                selection.insert(recording.id)
                                            }
                                        }
                                    } else {
                                        present(.recording(recording))
                                    }
                                } actions: {
                                    actions(for: recording)
                                }
                                .contextMenu { actions(for: recording) }
                                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                            }
                        }
                        .transition(.opacity)
                    }
                } else if !recorder.isActive {
                    empty
                }
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 44)
            .padding(.top, 84)
            .padding(.bottom, selecting ? 110 : 40)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
        .overlay(alignment: .bottom) {
            if selecting {
                selectionBar
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .confirmationDialog(
            "Delete \(selection.count) recording\(selection.count == 1 ? "" : "s")?",
            isPresented: $deletingSelection
        ) {
            Button("Delete", role: .destructive) {
                withAnimation(Motion.standard) {
                    for recording in selectedRecordings {
                        library.delete(recording)
                    }
                    selection = []
                }
            }
        } message: {
            Text("The audio, transcripts and notes will be removed from this Mac. This cannot be undone.")
        }
        .animation(Motion.standard, value: visible.map(\.id))
        .animation(Motion.standard, value: recorder.isActive)
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $newTitle)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") {
                let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if var recording = renaming, !title.isEmpty {
                    recording.title = title
                    recording.isNamed = true
                    library.save(recording)
                }
                renaming = nil
            }
        }
        .confirmationDialog(
            "Merge these recordings?",
            isPresented: Binding(get: { !merging.isEmpty }, set: { if !$0 { merging = [] } })
        ) {
            Button("Merge") {
                merge(merging)
                merging = []
                selection = []
            }
        } message: {
            Text("“\(merging.sorted { $0.createdAt < $1.createdAt }.map(\.title).joined(separator: "” and “"))” become one recording, in the order they were recorded. Audio, transcripts, notes and flashcards are joined.")
        }
        .alert("Could not merge", isPresented: Binding(get: { mergeError != nil }, set: { if !$0 { mergeError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(mergeError ?? "")
        }
        .confirmationDialog(
            "Delete “\(deleting?.title ?? "")”?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
        ) {
            Button("Delete", role: .destructive) {
                if let deleting {
                    withAnimation(Motion.standard) { library.delete(deleting) }
                }
                deleting = nil
            }
        } message: {
            Text("The audio, the transcript and the notes will be removed from this Mac. This cannot be undone.")
        }
    }

    @ViewBuilder
    private func actions(for recording: Recording) -> some View {
        Button("Open", systemImage: "arrow.up.forward.app") { present(.recording(recording)) }
        Button("Rename…", systemImage: "pencil") {
            newTitle = recording.title
            renaming = recording
        }
        Menu("Move to", systemImage: "folder") {
            Button("None") { move(recording, to: nil) }
            Divider()
            ForEach(library.activeGoals) { goal in
                Button(goal.title) { move(recording, to: goal.id) }
            }
        }
        Menu("Merge with", systemImage: "arrow.triangle.merge") {
            ForEach(mergeCandidates(for: recording)) { other in
                Button("\(other.title) · \(other.createdAt.formatted(date: .abbreviated, time: .shortened))") {
                    merging = [recording, other]
                }
            }
        }
        .disabled(mergeCandidates(for: recording).isEmpty || enhancer.isWorking(on: recording))
        Divider()
        Button("Export as PDF…", systemImage: "arrow.down.doc") {
            NotesPDF.export(recording, goal: library.goal(recording.goalID), original: false)
        }
        Button("Copy Transcript", systemImage: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(recording.notes?.text ?? recording.transcript, forType: .string)
        }
        Button("Transcribe Again", systemImage: "arrow.clockwise") { transcribeAgain(recording) }
            .disabled(enhancer.isWorking(on: recording))
        Button("Show Audio in Finder", systemImage: "folder.badge.gearshape") {
            NSWorkspace.shared.activateFileViewerSelecting([library.audioURL(for: recording)])
        }
        Divider()
        Button("Delete…", systemImage: "trash", role: .destructive) { deleting = recording }
    }

    private var selectedRecordings: [Recording] {
        library.recordings.filter { selection.contains($0.id) }
    }

    private var selectionBar: some View {
        GlassEffectContainer {
            HStack(spacing: 10) {
                Text(selection.isEmpty ? "Select recordings" : "\(selection.count) selected")
                    .font(.rounded(14, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText())
                    .padding(.leading, 8)
                    .frame(minWidth: 130, alignment: .leading)

                Button("Select All") {
                    withAnimation(Motion.quick) { selection = Set(visible.map(\.id)) }
                }
                .buttonStyle(.plain)
                .font(.rounded(13, weight: .semibold))
                .foregroundStyle(Palette.inkSecondary)

                Divider().frame(height: 22)

                Button("Merge", systemImage: "arrow.triangle.merge") { merging = selectedRecordings }
                    .disabled(selection.count < 2 || selectedRecordings.contains { enhancer.isWorking(on: $0) })
                Menu("Move to", systemImage: "folder") {
                    Button("None") { moveSelection(to: nil) }
                    Divider()
                    ForEach(library.activeGoals) { goal in
                        Button(goal.title) { moveSelection(to: goal.id) }
                    }
                }
                .disabled(selection.isEmpty)
                Button("PDF", systemImage: "arrow.down.doc") {
                    NotesPDF.exportAll(selectedRecordings, library: library)
                }
                .disabled(selection.isEmpty)
                Button("Delete", systemImage: "trash", role: .destructive) { deletingSelection = true }
                    .disabled(selection.isEmpty)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .padding(8)
            .glassEffect(.regular, in: .capsule)
        }
        .animation(Motion.quick, value: selection.count)
    }

    private func moveSelection(to goalID: Goal.ID?) {
        for recording in selectedRecordings {
            move(recording, to: goalID)
        }
    }

    private func mergeCandidates(for recording: Recording) -> [Recording] {
        library.recordings
            .filter { $0.id != recording.id && $0.stage != .recording && !enhancer.isWorking(on: $0) }
            .filter { abs($0.createdAt.timeIntervalSince(recording.createdAt)) < 3 * 86_400 }
            .sorted { abs($0.createdAt.timeIntervalSince(recording.createdAt)) < abs($1.createdAt.timeIntervalSince(recording.createdAt)) }
            .prefix(8)
            .map { $0 }
    }

    private func merge(_ recordings: [Recording]) {
        Task {
            do {
                let merged = try await RecordingMerger.merge(recordings, in: library)
                if merged.notes == nil {
                    enhancer.enhance(merged, for: persona)
                }
            } catch {
                mergeError = error.localizedDescription
            }
        }
    }

    private func move(_ recording: Recording, to goalID: Goal.ID?) {
        var moved = recording
        moved.goalID = goalID
        library.save(moved)
    }

    private func transcribeAgain(_ recording: Recording) {
        var refreshed = recording
        refreshed.stage = .refining
        library.save(refreshed)
        enhancer.enhance(refreshed, for: persona)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.inkSecondary)
                TextField("Search titles, transcripts and notes", text: $query)
                    .textFieldStyle(.plain)
                    .font(.rounded(15, weight: .medium))
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Palette.inkTertiary)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .glassEffect(.regular, in: .capsule)

            if !goals.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        chip(title: "All", tint: Palette.ink, isSelected: goalFilter == nil) { goalFilter = nil }
                        ForEach(goals) { goal in
                            chip(title: goal.title, tint: goal.tint.color, isSelected: goalFilter == goal.id) {
                                goalFilter = goalFilter == goal.id ? nil : goal.id
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.never)
            }
        }
        .animation(Motion.quick, value: goalFilter)
        .animation(Motion.quick, value: query.isEmpty)
    }

    private func chip(title: String, tint: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isSelected ? .white : tint)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.rounded(13, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : Palette.ink)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(isSelected ? AnyShapeStyle(tint) : AnyShapeStyle(Palette.surface.opacity(0.7)), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.pressable)
    }

    private var empty: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(FocusMode.orbit.palette.deep.gradient, in: .circle)
                .shadow(color: FocusMode.orbit.palette.deep.opacity(0.35), radius: 16, y: 8)
            Text(persona.recordingsEmptyTitle)
                .font(.rounded(20, weight: .bold))
                .foregroundStyle(Palette.ink)
            Text(persona.recordingsEmptyMessage)
                .font(.rounded(15, weight: .medium))
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

private struct LiveCard: View {
    let since: Date
    let levels: [Float]
    let text: String
    let stop: () -> Void
    @State private var pulses = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Palette.record)
                    .frame(width: 9, height: 9)
                    .opacity(pulses ? 0.35 : 1)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulses)
                Text("Recording now")
                    .font(.rounded(14, weight: .bold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(context.date.timeIntervalSince(since).clock)
                        .font(.numeric(15, weight: .semibold))
                        .foregroundStyle(Palette.inkSecondary)
                        .contentTransition(.numericText())
                }
                Button(action: stop) {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.rounded(13, weight: .semibold))
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(Palette.record)
                .help("Stop and save the recording")
            }
            Waveform(levels: Array(levels.suffix(64)))
                .frame(height: 34)
            if !text.isEmpty {
                Text(text.suffix(220))
                    .font(.rounded(14, weight: .medium))
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(2)
                    .truncationMode(.head)
            }
        }
        .padding(20)
        .background(Palette.surface.opacity(0.75), in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Palette.record.opacity(0.18), lineWidth: 1))
        .onAppear { pulses = true }
    }
}

private struct RecordingRow<Actions: View>: View {
    let recording: Recording
    let persona: Persona
    var isSelected: Bool?
    let open: () -> Void
    @ViewBuilder let actions: () -> Actions
    @Environment(Library.self) private var library
    @Environment(NoteEnhancer.self) private var enhancer
    @State private var isHovering = false

    private var tint: Color {
        library.goal(recording.goalID)?.tint.color ?? FocusMode.orbit.palette.deep
    }

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 14) {
                if let isSelected {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(isSelected ? AnyShapeStyle(tint) : AnyShapeStyle(Palette.inkTertiary))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(height: 44)
                        .transition(.scale.combined(with: .opacity))
                }
                Image(systemName: recording.title.hasPrefix("Meeting") ? "person.2.wave.2.fill" : "waveform")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(tint.gradient, in: .rect(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(recording.title)
                            .font(.rounded(16, weight: .bold))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Spacer(minLength: 12)
                        status
                        Menu {
                            actions()
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Palette.inkSecondary)
                                .frame(width: 26, height: 22)
                                .contentShape(.rect)
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .opacity(isHovering && isSelected == nil ? 1 : 0)
                        .help("More")
                    }
                    Text(metadata)
                        .font(.rounded(12, weight: .medium))
                        .foregroundStyle(Palette.inkSecondary)
                    if let summary = recording.notes?.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.rounded(13, weight: .medium))
                            .foregroundStyle(Palette.ink.opacity(0.75))
                            .lineLimit(2)
                            .padding(.top, 2)
                    } else if !recording.transcript.isEmpty {
                        Text(recording.transcript)
                            .font(.rounded(13, weight: .medium))
                            .foregroundStyle(Palette.inkTertiary)
                            .lineLimit(1)
                            .padding(.top, 2)
                    }
                }
            }
            .padding(14)
            .background(Palette.surface.opacity(isHovering ? 0.92 : 0.7), in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(tint, lineWidth: 2)
                    .opacity(isSelected == true ? 1 : 0)
            }
            .shadow(color: .black.opacity(isHovering ? 0.06 : 0), radius: 12, y: 6)
            .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.pressable)
        .onHover { hovering in
            withAnimation(Motion.quick) { isHovering = hovering }
        }
    }

    private var metadata: String {
        let length = recording.duration < 60 ? "\(Int(recording.duration.rounded())) s" : recording.duration.compactDuration
        var parts = [recording.createdAt.formatted(date: .omitted, time: .shortened), length]
        if let goal = library.goal(recording.goalID) {
            parts.append(goal.title)
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var status: some View {
        switch enhancer.phase(of: recording) {
        case .transcribing:
            StatusPill(text: "Transcribing", tint: tint, isBusy: true)
        case .writing:
            StatusPill(text: "Writing notes", tint: tint, isBusy: true)
        case nil:
            if recording.wasInterrupted == true {
                StatusPill(text: "Recovered", tint: Palette.rest.deep, isBusy: false)
            } else if let count = highlight {
                StatusPill(text: count, tint: tint, isBusy: false)
            }
        }
    }

    private var highlight: String? {
        guard let notes = recording.notes else { return nil }
        if let cards = notes.sections.first(where: { $0.style == .flashcards })?.items.count, cards > 0 {
            return "\(cards) flashcard\(cards == 1 ? "" : "s")"
        }
        if let actions = notes.sections.first(where: { $0.style == .checklist })?.items.count, actions > 0 {
            return "\(actions) action item\(actions == 1 ? "" : "s")"
        }
        return "Notes ready"
    }
}

private struct StatusPill: View {
    let text: String
    let tint: Color
    let isBusy: Bool

    var body: some View {
        HStack(spacing: 5) {
            if isBusy {
                ProgressView()
                    .controlSize(.mini)
            }
            Text(text)
                .font(.rounded(11, weight: .bold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(tint.opacity(0.12), in: .capsule)
        .transition(.blurReplace)
    }
}

private extension Date {
    var relativeDayTitle: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "Today" }
        if calendar.isDateInYesterday(self) { return "Yesterday" }
        return formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}
