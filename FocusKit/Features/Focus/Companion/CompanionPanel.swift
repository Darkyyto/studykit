import SwiftUI

struct CompanionPanel: View {
    let kind: SessionKind
    let tint: Color
    @Binding var selection: Companion
    @Binding var width: Double
    @Binding var isExpanded: Bool
    let close: () -> Void
    @Environment(FocusEngine.self) private var engine
    @Environment(VoiceRecorder.self) private var recorder
    @FocusState private var focusedField: Companion?
    @State private var draft = ""
    @State private var dragStart: Double?
    @State private var isHoveringEdge = false

    static let widthRange: ClosedRange<Double> = 300...640

    private var textSize: CGFloat {
        if isExpanded { return 18 }
        return width > 460 ? 16 : 15
    }

    private var panelWidth: CGFloat? {
        isExpanded ? nil : CGFloat(width)
    }

    private var contentWidth: CGFloat {
        isExpanded ? 760 : .infinity
    }

    private var panelMaxWidth: CGFloat? {
        isExpanded ? .infinity : nil
    }

    private var panelMaxHeight: CGFloat {
        isExpanded ? .infinity : 600
    }

    static func tabs(for kind: SessionKind) -> [Companion] {
        kind.companions.filter { $0 != .recall }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                GlassSegmented(options: Self.tabs(for: kind), selection: $selection, tint: tint) { $0.title }
                Spacer(minLength: 0)
                Button {
                    withAnimation(Motion.morph) { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.inkSecondary)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 30, height: 30)
                        .contentShape(.circle)
                }
                .buttonStyle(.pressable)
                .help(isExpanded ? "Shrink (⇧⌘\\)" : "Expand (⇧⌘\\)")
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.inkSecondary)
                        .frame(width: 30, height: 30)
                        .contentShape(.circle)
                }
                .buttonStyle(.pressable)
                .help("Close (⌘\\)")
            }

            Group {
                switch selection {
                case .notes: notes
                case .transcript: transcript
                case .tasks: tasks
                case .parkingLot: parkingLot
                case .recall: EmptyView()
                }
            }
            .frame(maxWidth: contentWidth, maxHeight: .infinity, alignment: .top)
            .frame(maxWidth: .infinity)
            .transition(.opacity)
        }
        .padding(isExpanded ? 20 : 16)
        .frame(width: panelWidth)
        .frame(maxWidth: panelMaxWidth, maxHeight: panelMaxHeight)
        .background(.white.opacity(isExpanded ? 0.94 : 0.88), in: .rect(cornerRadius: 24))
        .overlay(alignment: .leading) {
            if !isExpanded {
                resizeEdge
            }
        }
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
        .shadow(color: .black.opacity(0.1), radius: 30, y: 14)
        .animation(Motion.standard, value: selection)
        .background {
            Button("") {
                selection = .parkingLot
                focusedField = .parkingLot
            }
            .keyboardShortcut("d", modifiers: .command)
            .hidden()
            Button("") {
                withAnimation(Motion.morph) { isExpanded.toggle() }
            }
            .keyboardShortcut("\\", modifiers: [.command, .shift])
            .hidden()
        }
    }

    private var resizeEdge: some View {
        Capsule()
            .fill(Palette.inkTertiary.opacity(isHoveringEdge || dragStart != nil ? 0.8 : 0))
            .frame(width: 4, height: 44)
            .frame(width: 14)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .offset(x: -7)
            .pointerStyle(.frameResize(position: .leading))
            .onHover { hovering in
                withAnimation(Motion.quick) { isHoveringEdge = hovering }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start: Double = dragStart ?? width
                        dragStart = start
                        let proposed: Double = start - Double(value.translation.width)
                        width = Self.widthRange.clamped(proposed)
                    }
                    .onEnded { _ in
                        withAnimation(Motion.quick) { dragStart = nil }
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(Motion.morph) { width = 330 }
            }
            .help("Drag to resize")
    }

    private var notes: some View {
        @Bindable var workspace = engine.workspace
        return VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if workspace.notes.isEmpty {
                    Text(kind.notesPlaceholder)
                        .font(.rounded(textSize, weight: .medium))
                        .foregroundStyle(Palette.inkTertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $workspace.notes)
                    .font(.rounded(textSize, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .scrollContentBackground(.hidden)
                    .focused($focusedField, equals: .notes)
                    .lineSpacing(4)
            }
            .padding(8)
            .background(.white.opacity(0.55), in: .rect(cornerRadius: 18))

            HStack {
                Text(kind == .writing ? "\(workspace.wordCount) words" : "Saved with this session")
                    .font(.rounded(11, weight: .semibold))
                    .foregroundStyle(Palette.inkSecondary)
                    .contentTransition(.numericText())
                    .animation(Motion.quick, value: workspace.wordCount)
                Spacer()
            }
        }
    }

    private var transcript: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(recorder.isActive ? Palette.record : Palette.inkTertiary)
                    .frame(width: 7, height: 7)
                Text(recorderStatus)
                    .font(.rounded(12, weight: .semibold))
                    .foregroundStyle(recorder.isActive ? Palette.record : Palette.inkSecondary)
                Spacer()
                if let locale = recorder.transcriptionLocale {
                    Text(locale.localizedName)
                        .font(.rounded(11, weight: .medium))
                        .foregroundStyle(Palette.inkTertiary)
                }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    Group {
                        if recorder.finalizedText.isEmpty && recorder.volatileText.isEmpty {
                            Text("Words appear here as people speak. Smart notes are made when the session ends.")
                                .foregroundStyle(Palette.inkTertiary)
                        } else {
                            Text("\(Text(recorder.finalizedText).foregroundStyle(Palette.ink)) \(Text(recorder.volatileText).foregroundStyle(Palette.inkTertiary))")
                        }
                    }
                    .font(.rounded(textSize - 1, weight: .medium))
                    .lineSpacing(isExpanded ? 7 : 5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(height: 1).id("end")
                }
                .scrollIndicators(.never)
                .onChange(of: recorder.volatileText) {
                    withAnimation(Motion.standard) { proxy.scrollTo("end", anchor: .bottom) }
                }
            }
            .padding(12)
            .background(.white.opacity(0.55), in: .rect(cornerRadius: 18))
            if let error = recorder.errorMessage {
                Text(error)
                    .font(.rounded(11, weight: .medium))
                    .foregroundStyle(Palette.record)
            }
        }
    }

    private var recorderStatus: String {
        switch recorder.state {
        case .recording: "Transcribing live"
        case .preparing: "Starting the microphone…"
        case .downloadingModel: "Downloading the language model…"
        case .finishing: "Saving…"
        case .idle: "Not recording"
        }
    }

    private var tasks: some View {
        let workspace = engine.workspace
        let done = workspace.tasks.count { $0.isDone }
        return VStack(alignment: .leading, spacing: 10) {
            if !workspace.tasks.isEmpty {
                HStack {
                    Text("\(done) of \(workspace.tasks.count) done")
                        .font(.rounded(12, weight: .semibold))
                        .foregroundStyle(Palette.inkSecondary)
                        .contentTransition(.numericText())
                    Spacer()
                }
                ProgressView(value: Double(done), total: Double(max(1, workspace.tasks.count)))
                    .tint(tint)
            }
            if workspace.tasks.isEmpty {
                Text("Break the session into two or three concrete steps. Ticking them off keeps momentum.")
                    .font(.rounded(12, weight: .medium))
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(workspace.tasks) { task in
                        Button {
                            withAnimation(Motion.quick) { workspace.toggle(task) }
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(task.isDone ? tint : Palette.inkTertiary)
                                    .contentTransition(.symbolEffect(.replace))
                                Text(task.title)
                                    .font(.rounded(14, weight: .medium))
                                    .foregroundStyle(task.isDone ? Palette.inkTertiary : Palette.ink)
                                    .strikethrough(task.isDone)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(.white.opacity(task.isDone ? 0.3 : 0.6), in: .rect(cornerRadius: 12))
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.never)
            inputField("Add a task", focus: .tasks) { workspace.addTask($0) }
        }
    }

    private var parkingLot: some View {
        let workspace = engine.workspace
        return VStack(alignment: .leading, spacing: 10) {
            Text("Something pops into your head? Park it here and get back to work. It will be waiting when the session ends.")
                .font(.rounded(12, weight: .medium))
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            inputField("Park a thought  ⌘D", focus: .parkingLot) { workspace.park($0) }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(workspace.parked.enumerated()), id: \.offset) { _, thought in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "tray.and.arrow.down.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(tint)
                            Text(thought)
                                .font(.rounded(13, weight: .medium))
                                .foregroundStyle(Palette.ink)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(.white.opacity(0.6), in: .rect(cornerRadius: 12))
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(Motion.standard, value: workspace.parked)
            }
            .scrollIndicators(.never)
        }
    }

    private func inputField(_ prompt: String, focus: Companion, submit: @escaping (String) -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
            TextField(prompt, text: $draft)
                .textFieldStyle(.plain)
                .font(.rounded(13, weight: .medium))
                .focused($focusedField, equals: focus)
                .onSubmit {
                    withAnimation(Motion.quick) { submit(draft) }
                    draft = ""
                }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(.white.opacity(0.7), in: .capsule)
    }
}

private extension ClosedRange where Bound == Double {
    func clamped(_ value: Double) -> Double {
        Swift.min(upperBound, Swift.max(lowerBound, value))
    }
}
