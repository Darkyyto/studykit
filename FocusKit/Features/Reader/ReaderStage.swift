import SwiftUI

struct ReaderStage: View {
    let document: StudyDocument
    let plan: FocusPlan
    let canTakeNotes: Bool
    let showScene: () -> Void
    let end: () -> Void
    let quoted: () -> Void

    @Environment(FocusEngine.self) private var engine
    @Environment(Library.self) private var library
    @Environment(NoteEnhancer.self) private var enhancer
    @Environment(\.chromeInset) private var chromeInset
    @State private var model: ReaderModel
    @State private var isMaking = false
    @State private var toast: String?

    init(document: StudyDocument, url: URL, plan: FocusPlan, canTakeNotes: Bool, showScene: @escaping () -> Void, end: @escaping () -> Void, quoted: @escaping () -> Void) {
        self.document = document
        self.plan = plan
        self.canTakeNotes = canTakeNotes
        self.showScene = showScene
        self.end = end
        self.quoted = quoted
        _model = State(initialValue: ReaderModel(url: url, startPage: document.lastPage))
    }

    private var tint: Color {
        plan.mode.palette.deep
    }

    var body: some View {
        VStack(spacing: 12) {
            sessionBar
            ZStack(alignment: .bottom) {
                PDFReader(model: model)
                    .background(Color(hex: 0xECEAE5))
                    .clipShape(.rect(cornerRadius: 24))
                    .shadow(color: .black.opacity(0.08), radius: 18, y: 8)

                if !model.selection.isEmpty, canTakeNotes {
                    Button {
                        engine.workspace.quote(model.selection, page: model.page)
                        model.clearSelection()
                        quoted()
                        show("Quote added to your notes")
                    } label: {
                        Label("Add to notes", systemImage: "text.quote")
                            .font(.rounded(13, weight: .semibold))
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(tint)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if let toast {
                    Label(toast, systemImage: "checkmark.circle.fill")
                        .font(.rounded(13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .background(Palette.ink.opacity(0.85), in: .capsule)
                        .padding(.bottom, 18)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(Motion.settle, value: model.selection.isEmpty)
            .animation(Motion.settle, value: toast)
        }
        .padding(.top, chromeInset)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .onChange(of: model.page) { _, page in
            engine.workspace.markRead(page)
            var updated = library.documents.first { $0.id == document.id } ?? document
            updated.lastPage = page
            updated.openedAt = .now
            library.save(updated)
        }
        .onAppear { engine.workspace.markRead(model.page) }
    }

    private var sessionBar: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 14) {
                Button(action: showScene) {
                    FocusScene(
                        mode: plan.mode,
                        progress: { engine.focusProgress(at: $0) },
                        route: plan.route,
                        variant: plan.variant,
                        isPaused: engine.isPaused,
                        isAnimated: false,
                        insets: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
                    )
                    .frame(width: 46, height: 46)
                    .background(plan.mode.palette.light)
                    .clipShape(.rect(cornerRadius: 13))
                }
                .buttonStyle(.pressable)
                .help("Back to the \(plan.mode.title.lowercased()) view")

                VStack(alignment: .leading, spacing: 0) {
                    Text(engine.isPaused ? "Paused" : plan.kind.title)
                        .font(.rounded(11, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(engine.remaining(at: context.date).clock)
                        .font(.numeric(24, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(Motion.quick, value: Int(engine.remaining(at: context.date)))
                }
                .frame(width: 92, alignment: .leading)

                HStack(spacing: 6) {
                    barButton(engine.isPaused ? "play.fill" : "pause.fill", help: engine.isPaused ? "Resume" : "Pause") {
                        withAnimation(Motion.morph) { engine.togglePause() }
                    }
                    .keyboardShortcut(.space, modifiers: [.option])
                    barButton("stop.fill", help: "End session", action: end)
                }

                Divider().frame(height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(document.title)
                        .font(.rounded(13, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text("Page \(model.page + 1) of \(model.pageCount)")
                        .font(.rounded(11, weight: .medium))
                        .foregroundStyle(Palette.inkSecondary)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    barButton("minus.magnifyingglass", help: "Zoom out") { model.zoom(by: 0.85) }
                        .keyboardShortcut("-", modifiers: .command)
                    barButton("arrow.left.and.right", help: "Fit width") { model.fitWidth() }
                        .keyboardShortcut("0", modifiers: .command)
                    barButton("plus.magnifyingglass", help: "Zoom in") { model.zoom(by: 1.18) }
                        .keyboardShortcut("=", modifiers: .command)
                }

                flashcardButton
            }
            .padding(.horizontal, 12)
            .frame(height: 64)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
        }
    }

    @ViewBuilder
    private var flashcardButton: some View {
        if enhancer.availability == .available {
            Button {
                makeFlashcards()
            } label: {
                if isMaking {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Flashcards", systemImage: "rectangle.on.rectangle.angled")
                        .font(.rounded(13, weight: .semibold))
                }
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .disabled(isMaking)
            .help("Make flashcards from these pages for your Recall breaks")
        }
    }

    private func barButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.6), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.pressable)
        .help(help)
    }

    private func makeFlashcards() {
        isMaking = true
        let text = model.text(around: model.page)
        Task {
            defer { isMaking = false }
            do {
                let cards = try await enhancer.flashcards(from: text)
                var updated = library.documents.first { $0.id == document.id } ?? document
                updated.flashcards.append(contentsOf: cards)
                updated.goalID = updated.goalID ?? plan.goalID
                library.save(updated)
                show("\(cards.count) flashcards ready for your next break")
            } catch {
                show(enhancer.describeFailure(error))
            }
        }
    }

    private func show(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            if toast == message { toast = nil }
        }
    }
}
