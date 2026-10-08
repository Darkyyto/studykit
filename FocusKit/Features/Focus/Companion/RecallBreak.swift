import SwiftUI

struct RecallBreak: View {
    let cards: [SmartNotes.Item]
    @Environment(\.chromeInset) private var chromeInset
    @State private var index = 0
    @State private var flipped = false
    @State private var known = 0

    var body: some View {
        ZStack {
            BreatheScene()
                .opacity(0.35)
                .allowsHitTesting(false)

            VStack(spacing: 18) {
                VStack(spacing: 4) {
                    Label("Recall break", systemImage: "rectangle.on.rectangle.angled")
                        .font(.rounded(13, weight: .bold))
                        .foregroundStyle(Palette.rest.deep)
                    Text("Answer in your head, then flip. Active recall beats rereading.")
                        .font(.rounded(13, weight: .medium))
                        .foregroundStyle(Palette.inkSecondary)
                }

                if cards.isEmpty {
                    empty
                } else {
                    card(cards[index % cards.count])
                    controls
                }
                Spacer(minLength: 0)
            }
            .padding(.top, chromeInset + 20)
            .frame(maxWidth: 560)
        }
    }

    private func card(_ item: SmartNotes.Item) -> some View {
        Button {
            withAnimation(Motion.settle) { flipped.toggle() }
        } label: {
            ZStack {
                face(item.primary, caption: "Question \(index % cards.count + 1) of \(cards.count)", tint: Palette.rest.deep)
                    .opacity(flipped ? 0 : 1)
                face(item.secondary ?? "", caption: "Answer", tint: FocusMode.bloom.palette.deep)
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                    .opacity(flipped ? 1 : 0)
            }
            .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        }
        .buttonStyle(.pressable)
        .id(index)
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
    }

    private func face(_ text: String, caption: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(caption)
                .font(.rounded(12, weight: .bold))
                .foregroundStyle(tint)
            Text(text)
                .font(.rounded(21, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            Text(flipped ? "Click to see the question" : "Click to flip")
                .font(.rounded(11, weight: .semibold))
                .foregroundStyle(Palette.inkTertiary)
        }
        .padding(24)
        .frame(width: 520, height: 230, alignment: .topLeading)
        .background(Palette.surface.opacity(0.85), in: .rect(cornerRadius: 28))
        .shadow(color: .black.opacity(0.08), radius: 20, y: 10)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                next(knewIt: false)
            } label: {
                Label("Again later", systemImage: "arrow.uturn.backward")
                    .font(.rounded(14, weight: .semibold))
            }
            .buttonStyle(.glass)
            Button {
                next(knewIt: true)
            } label: {
                Label("Got it", systemImage: "checkmark")
                    .font(.rounded(14, weight: .semibold))
            }
            .buttonStyle(.glassProminent)
            .tint(FocusMode.bloom.palette.deep)
            Text("\(known) known")
                .font(.rounded(12, weight: .semibold))
                .foregroundStyle(Palette.inkSecondary)
                .padding(.leading, 6)
                .contentTransition(.numericText())
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.badge.plus")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Palette.rest.deep)
            Text("No flashcards yet")
                .font(.rounded(18, weight: .bold))
                .foregroundStyle(Palette.ink)
            Text("Record a lecture and FocusKit will turn it into questions you can review here. For now, breathe with the circle.")
                .font(.rounded(13, weight: .medium))
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(width: 420)
        .background(Palette.surface.opacity(0.75), in: .rect(cornerRadius: 28))
    }

    private func next(knewIt: Bool) {
        withAnimation(Motion.morph) {
            if knewIt { known += 1 }
            flipped = false
            index += 1
        }
    }
}

extension Library {
    func flashcards(for goalID: Goal.ID?) -> [SmartNotes.Item] {
        let sources = recordings.filter { $0.notes != nil }
        let preferred = goalID.map { id in sources.filter { $0.goalID == id } } ?? []
        let pool = (preferred.isEmpty ? sources : preferred).prefix(6)
        let documentCards = documents
            .filter { goalID == nil || $0.goalID == nil || $0.goalID == goalID }
            .prefix(6)
            .flatMap(\.flashcards)
        let cards = pool.flatMap { recording in
            (recording.notes?.sections ?? []).filter { $0.style == .flashcards }.flatMap(\.items)
        } + documentCards
        var generator = SeededGenerator(seed: UInt64(cards.count &* 7919 &+ Calendar.current.component(.day, from: .now)))
        return cards.shuffled(using: &generator)
    }
}
