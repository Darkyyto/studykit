import SwiftUI

struct EndSessionPrompt: View {
    let plan: FocusPlan
    let focused: TimeInterval
    let keepGoing: () -> Void
    let end: () -> Void
    @State private var appeared = false

    private var savesTime: Bool {
        focused >= 60
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.08))
                .ignoresSafeArea()
                .onTapGesture(perform: keepGoing)

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(plan.mode.palette.light)
                    Circle()
                        .trim(from: 0, to: min(1, focused / max(plan.totalFocus, 1)))
                        .stroke(plan.mode.palette.deep, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(8)
                    Image(systemName: plan.mode.symbol)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(plan.mode.palette.deep)
                }
                .frame(width: 84, height: 84)
                .scaleEffect(appeared ? 1 : 0.7)

                VStack(spacing: 8) {
                    Text("End this session?")
                        .font(.rounded(24, weight: .bold))
                        .displayTracking(24)
                        .foregroundStyle(Palette.ink)
                    Text(message)
                        .font(.rounded(14, weight: .medium))
                        .foregroundStyle(Palette.inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 10) {
                    Button(action: keepGoing) {
                        Text("Keep Going")
                            .font(.rounded(15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(plan.mode.palette.deep)
                    .keyboardShortcut(.cancelAction)

                    Button(action: end) {
                        Text(savesTime ? "End and Save" : "End Session")
                            .font(.rounded(15, weight: .semibold))
                            .foregroundStyle(Palette.record)
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                    }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.defaultAction)
                }
                .buttonBorderShape(.capsule)
                .controlSize(.large)
            }
            .padding(28)
            .frame(width: 340)
            .glassEffect(.regular, in: .rect(cornerRadius: 34))
            .shadow(color: .black.opacity(0.12), radius: 40, y: 18)
        }
        .onAppear {
            withAnimation(Motion.settle.delay(0.05)) { appeared = true }
        }
    }

    private var message: String {
        let minutes = Int(focused / 60)
        guard savesTime else { return "You have just started. Nothing will be saved yet." }
        return "You have focused for \(minutes) min. It will be saved to your journal."
    }
}
