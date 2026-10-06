import SwiftUI

struct CloseCardAction: Sendable {
    let action: @MainActor @Sendable () -> Void

    @MainActor
    func callAsFunction() {
        action()
    }
}

enum Modal: Identifiable {
    case goal(Goal)
    case recording(Recording)

    var id: String {
        switch self {
        case .goal(let goal): "goal-\(goal.id)"
        case .recording(let recording): "recording-\(recording.id)"
        }
    }
}

struct PresentAction: Sendable {
    let action: @MainActor @Sendable (Modal) -> Void

    @MainActor
    func callAsFunction(_ modal: Modal) {
        action(modal)
    }
}

extension EnvironmentValues {
    @Entry var closeCard = CloseCardAction {}
    @Entry var present = PresentAction { _ in }
}

private struct CardPresentation<Item: Identifiable, Card: View>: ViewModifier {
    @Binding var item: Item?
    let card: (Item) -> Card

    func body(content: Content) -> some View {
        content.overlay {
            ZStack {
                if let value = item {
                    Rectangle()
                        .fill(Palette.canvas.opacity(0.6))
                        .ignoresSafeArea()
                        .contentShape(.rect)
                        .onTapGesture { item = nil }
                        .transition(.opacity)

                    card(value)
                        .background(.white, in: .rect(cornerRadius: 32))
                        .clipShape(.rect(cornerRadius: 32))
                        .shadow(color: .black.opacity(0.12), radius: 40, y: 20)
                        .environment(\.closeCard, CloseCardAction { [binding = $item] in binding.wrappedValue = nil })
                        .id(value.id)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.94).combined(with: .opacity),
                            removal: .scale(scale: 0.97).combined(with: .opacity)
                        ))
                }
            }
            .animation(Motion.settle, value: item?.id)
        }
    }
}

extension View {
    func card<Item: Identifiable, Card: View>(item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Card) -> some View {
        modifier(CardPresentation(item: item, card: content))
    }
}
