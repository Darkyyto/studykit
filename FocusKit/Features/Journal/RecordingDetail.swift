import SwiftUI

struct RecordingDetail: View {
    @State var recording: Recording
    @Environment(Library.self) private var library
    @Environment(NoteEnhancer.self) private var enhancer
    @State private var playback = Playback()
    @State private var confirmsDeletion = false
    @Environment(\.closeCard) private var dismiss
    @State private var showsOriginal = false
    @AppStorage(Preference.persona) private var persona = Persona.personal

    private var stored: Recording {
        library.recordings.first { $0.id == recording.id } ?? recording
    }

    var body: some View {
        let stored = stored
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(metadata)
                        .font(.rounded(13, weight: .medium))
                        .foregroundStyle(Palette.inkSecondary)
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .keyboardShortcut(.cancelAction)
                }
                TextField("Title", text: $recording.title)
                    .textFieldStyle(.plain)
                    .font(.rounded(30, weight: .bold))
                    .onSubmit { save() }
            }

            HStack(spacing: 12) {
                PlayerBar(playback: playback)
                if stored.notes != nil {
                    GlassSegmented(options: [false, true], selection: $showsOriginal, tint: Palette.ink) { $0 ? "Original" : "Polished" }
                        .fixedSize()
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let notes = stored.notes, !showsOriginal {
                        SmartNotesView(notes: notes)
                        body(notes.text)
                    } else {
                        body(stored.transcript.isEmpty ? "No transcript was captured for this recording." : stored.transcript, muted: stored.transcript.isEmpty)
                    }
                }
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(Motion.standard, value: showsOriginal)
            }
            .scrollIndicators(.never)

            if enhancer.isWorking(on: stored) {
                PolishingBanner()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if let failure = enhancer.failures[stored.id] {
                ErrorBanner(message: failure) { enhancer.dismissFailure(for: stored) }
                    .padding(-24)
            }

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    goalMenu
                    Spacer()
                    polishButton(stored)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(exportText(stored), forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .disabled(stored.transcript.isEmpty)

                    Button {
                        NotesPDF.export(stored, goal: library.goal(stored.goalID), original: showsOriginal)
                    } label: {
                        Label("PDF", systemImage: "arrow.down.doc")
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .disabled(stored.transcript.isEmpty && stored.notes == nil)
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .help("Export as PDF (⇧⌘E)")

                    ShareLink(item: library.audioURL(for: recording)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)

                    Button {
                        confirmsDeletion = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .help("Delete recording")
                }
                .controlSize(.large)
            }
        }
        .padding(32)
        .animation(Motion.standard, value: enhancer.isWorking(on: stored))
        .animation(Motion.standard, value: stored.notes)
        .onAppear { playback.load(library.audioURL(for: recording)) }
        .onChange(of: stored.title) { _, title in recording.title = title }
        .onDisappear {
            playback.stop()
            save()
        }
        .confirmationDialog("Delete “\(recording.title)”?", isPresented: $confirmsDeletion) {
            Button("Delete", role: .destructive) {
                playback.stop()
                library.delete(recording)
                dismiss()
            }
        } message: {
            Text("The audio and its transcript will be removed from this Mac.")
        }
    }

    private func body(_ text: String, muted: Bool = false) -> some View {
        Text(text)
            .font(.rounded(18, weight: .medium))
            .lineSpacing(7)
            .foregroundStyle(muted ? Palette.inkTertiary : Palette.ink)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func polishButton(_ stored: Recording) -> some View {
        switch enhancer.availability {
        case .available:
            Button {
                enhancer.enhance(stored, for: persona)
            } label: {
                Label(stored.notes == nil ? "Make Notes" : "Redo Notes", systemImage: "wand.and.sparkles")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .disabled(stored.transcript.isEmpty || enhancer.isWorking(on: stored))
        case .unavailable(let reason):
            Image(systemName: "wand.and.sparkles")
                .foregroundStyle(Palette.inkTertiary)
                .help(reason)
        }
    }

    private func exportText(_ stored: Recording) -> String {
        guard let notes = stored.notes, !showsOriginal else { return stored.transcript }
        var lines = [recording.title, "", notes.summary, ""]
        for section in notes.sections {
            lines.append(section.title)
            for item in section.items {
                let marker = section.style == .checklist ? "☐" : "•"
                lines.append(item.secondary.map { "\(marker) \(item.primary): \($0)" } ?? "\(marker) \(item.primary)")
            }
            lines.append("")
        }
        lines.append(notes.text)
        return lines.joined(separator: "\n")
    }

    private func save() {
        var updated = stored
        updated.title = recording.title
        updated.goalID = recording.goalID
        library.save(updated)
    }

    private var metadata: String {
        let date = recording.createdAt.formatted(date: .abbreviated, time: .shortened)
        let language = Locale(identifier: recording.localeIdentifier).localizedName
        return "\(date) · \(recording.duration.compactDuration) · \(language)"
    }

    private var goalMenu: some View {
        Menu {
            Button("No Goal") { assign(nil) }
            Divider()
            ForEach(library.activeGoals) { goal in
                Button(goal.title) { assign(goal.id) }
            }
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(library.goal(recording.goalID)?.tint.color ?? Palette.inkTertiary)
                    .frame(width: 8, height: 8)
                Text(library.goal(recording.goalID)?.title ?? "Attach to Goal")
            }
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .fixedSize()
    }

    private func assign(_ goalID: Goal.ID?) {
        recording.goalID = goalID
        save()
    }
}

private struct SmartNotesView: View {
    let notes: SmartNotes

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Summary", systemImage: "sparkles")
                    .font(.rounded(13, weight: .semibold))
                    .foregroundStyle(FocusMode.orbit.palette.deep)
                Text(notes.summary)
                    .font(.rounded(16, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [FocusMode.orbit.palette.light, .white.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .rect(cornerRadius: 24)
            )

            ForEach(notes.sections, id: \.title) { section in
                VStack(alignment: .leading, spacing: 10) {
                    Text(section.title)
                        .font(.rounded(13, weight: .semibold))
                        .foregroundStyle(Palette.inkSecondary)
                    switch section.style {
                    case .flashcards:
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                            ForEach(section.items, id: \.self) { item in
                                Flashcard(item: item)
                            }
                        }
                    case .definitions:
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(section.items, id: \.self) { item in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.primary)
                                        .font(.rounded(14, weight: .bold))
                                        .foregroundStyle(Palette.ink)
                                    if let secondary = item.secondary {
                                        Text(secondary)
                                            .font(.rounded(14, weight: .medium))
                                            .foregroundStyle(Palette.inkSecondary)
                                    }
                                }
                            }
                        }
                    case .checklist:
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(section.items, id: \.self) { item in
                                ChecklistRow(item: item)
                            }
                        }
                    case .bullets:
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(section.items, id: \.self) { item in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Circle()
                                        .fill(FocusMode.orbit.palette.mid)
                                        .frame(width: 6, height: 6)
                                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                                    Text(item.primary)
                                        .font(.rounded(14, weight: .medium))
                                        .foregroundStyle(Palette.ink)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct Flashcard: View {
    let item: SmartNotes.Item
    @State private var flipped = false

    var body: some View {
        Button {
            withAnimation(Motion.settle) { flipped.toggle() }
        } label: {
            ZStack {
                face(text: item.primary, caption: "Question", tint: FocusMode.orbit.palette.deep)
                    .opacity(flipped ? 0 : 1)
                face(text: item.secondary ?? "", caption: "Answer", tint: FocusMode.bloom.palette.deep)
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                    .opacity(flipped ? 1 : 0)
            }
            .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        }
        .buttonStyle(.pressable)
        .help(flipped ? "Show question" : "Show answer")
    }

    private func face(text: String, caption: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(caption)
                .font(.rounded(11, weight: .bold))
                .foregroundStyle(tint)
            Text(text)
                .font(.rounded(14, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(.white.opacity(0.75), in: .rect(cornerRadius: 18))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }
}

private struct ChecklistRow: View {
    let item: SmartNotes.Item
    @State private var done = false

    var body: some View {
        Button {
            withAnimation(Motion.quick) { done.toggle() }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? FocusMode.bloom.palette.deep : Palette.inkTertiary)
                    .contentTransition(.symbolEffect(.replace))
                Text(item.primary)
                    .font(.rounded(14, weight: .medium))
                    .foregroundStyle(done ? Palette.inkTertiary : Palette.ink)
                    .strikethrough(done)
                if let owner = item.secondary {
                    Text(owner)
                        .font(.rounded(12, weight: .semibold))
                        .foregroundStyle(FocusMode.flight.palette.deep)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(FocusMode.flight.palette.light, in: .capsule)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct PolishingBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wand.and.sparkles")
                .symbolEffect(.pulse, options: .repeating)
                .foregroundStyle(FocusMode.orbit.palette.deep)
            Text("Polishing grammar and writing a summary on this Mac…")
                .font(.rounded(13, weight: .medium))
                .foregroundStyle(Palette.inkSecondary)
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .background(.white.opacity(0.6), in: .capsule)
    }
}

private struct PlayerBar: View {
    let playback: Playback

    var body: some View {
        HStack(spacing: 14) {
            Button {
                playback.toggle()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 42, height: 42)
                    .background(Palette.ink, in: .circle)
            }
            .buttonStyle(.pressable)

            TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                HStack(spacing: 12) {
                    Scrubber(
                        progress: playback.duration > 0 ? playback.currentTime / playback.duration : 0,
                        seek: { playback.seek(to: $0 * playback.duration) }
                    )
                    Text("\(playback.currentTime.clock) / \(playback.duration.clock)")
                        .font(.numeric(12, weight: .medium))
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize()
                }
            }
        }
        .padding(8)
        .padding(.trailing, 10)
        .background(.white.opacity(0.6), in: .capsule)
    }
}

private struct Scrubber: View {
    let progress: Double
    let seek: (Double) -> Void
    @State private var dragProgress: Double?

    var body: some View {
        GeometryReader { proxy in
            let value = dragProgress ?? progress
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Palette.ink.opacity(0.1))
                Capsule()
                    .fill(Palette.ink)
                    .frame(width: max(8, proxy.size.width * value))
            }
            .frame(height: dragProgress == nil ? 6 : 10)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        dragProgress = min(1, max(0, gesture.location.x / proxy.size.width))
                    }
                    .onEnded { _ in
                        if let dragProgress { seek(dragProgress) }
                        dragProgress = nil
                    }
            )
            .animation(Motion.quick, value: dragProgress == nil)
        }
        .frame(height: 24)
    }
}
