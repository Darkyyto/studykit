import SwiftUI

struct ModeLauncher: View {
    let mode: FocusMode
    let isCurrent: Bool
    var size: CGFloat = 38
    let start: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: start) {
            VStack(spacing: 5) {
                Image(systemName: mode.symbol)
                    .font(.system(size: size * 0.37, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background {
                        Circle()
                            .fill(LinearGradient(colors: [mode.palette.mid, mode.palette.deep], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(isCurrent ? 0.7 : 0.15), lineWidth: isCurrent ? 1.5 : 0.5)
                    }
                    .shadow(color: mode.palette.deep.opacity(isHovering ? 0.6 : 0.3), radius: isHovering ? 10 : 5, y: 2)
                    .scaleEffect(isHovering ? 1.08 : 1)
                Text(mode.title)
                    .font(.rounded(10, weight: .semibold))
                    .foregroundStyle(isCurrent || isHovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .onHover { hovering in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) { isHovering = hovering }
        }
        .help("Start \(mode.title)")
    }
}

extension FocusEngine {
    func startQuick(_ mode: FocusMode) {
        let defaults = UserDefaults.standard
        defaults.set(mode.rawValue, forKey: Preference.focusMode)
        let minutes = defaults.integer(forKey: Preference.minutes(for: mode))
        let duration = TimeInterval((minutes > 0 ? minutes : mode.suggestedMinutes) * 60)
        let rounds = max(1, defaults.object(forKey: "rounds") as? Int ?? 1)
        let breakMinutes = defaults.object(forKey: "breakMinutes") as? Int ?? 5
        let origin = Airport.named(defaults.string(forKey: Preference.homeAirport) ?? Airport.fallback.code) ?? .fallback
        let destination = origin.routes(closestTo: duration)[0]
        start(FocusPlan(
            mode: mode,
            intention: "",
            goalID: nil,
            focusDuration: duration,
            rounds: rounds,
            breakDuration: rounds > 1 ? TimeInterval(breakMinutes * 60) : 0,
            route: mode == .flight ? Session.Route(origin: origin.code, destination: destination.code) : nil
        ))
    }
}
