import SwiftUI

enum BreathCycle {
    static let inhale: TimeInterval = 4
    static let hold: TimeInterval = 2
    static let exhale: TimeInterval = 6

    static var period: TimeInterval { inhale + hold + exhale }

    static func expansion(at time: TimeInterval) -> Double {
        let t = time.truncatingRemainder(dividingBy: period)
        if t < inhale { return Easing.smoothstep(t / inhale) }
        if t < inhale + hold { return 1 }
        return 1 - Easing.smoothstep((t - inhale - hold) / exhale)
    }

    static func instruction(at time: TimeInterval) -> String {
        let t = time.truncatingRemainder(dividingBy: period)
        if t < inhale { return "Breathe in" }
        if t < inhale + hold { return "Hold" }
        return "Breathe out"
    }
}

struct BreatheScene: View {
    var insets = EdgeInsets(top: 90, leading: 60, bottom: 280, trailing: 60)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.isOnScreen) private var isOnScreen

    var body: some View {
        TimelineView(.animation(minimumInterval: FrameRate.interval(active: appearsActive), paused: reduceMotion || !isOnScreen)) { context in
            let time = reduceMotion ? BreathCycle.inhale : context.date.timeIntervalSinceReferenceDate
            let expansion = BreathCycle.expansion(at: time)
            let palette = Palette.rest

            Canvas { canvas, size in
                let center = CGPoint(
                    x: insets.leading + (size.width - insets.leading - insets.trailing) / 2,
                    y: insets.top + (size.height - insets.top - insets.bottom) / 2
                )
                let base = min(size.width, size.height - insets.top - insets.bottom) * 0.27
                for ring in (0..<4).reversed() {
                    let radius = base * (0.7 + 0.55 * expansion) * (1 + CGFloat(ring) * 0.28)
                    var layer = canvas
                    layer.opacity = 0.18 + 0.82 * pow(0.55, Double(ring))
                    if ring == 0 {
                        layer.addFilter(.shadow(color: palette.deep.opacity(0.3), radius: 30, y: 12))
                    }
                    layer.fill(
                        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                        with: .radialGradient(
                            Gradient(colors: ring == 0 ? [.white, palette.mid] : [palette.light, palette.mid.opacity(0.6)]),
                            center: CGPoint(x: center.x - radius * 0.3, y: center.y - radius * 0.35),
                            startRadius: 0,
                            endRadius: radius * 1.6
                        )
                    )
                }
                canvas.draw(
                    Text(BreathCycle.instruction(at: time))
                        .font(.rounded(17, weight: .semibold))
                        .foregroundStyle(palette.deep),
                    at: center
                )
            }
        }
        .accessibilityLabel("Break. Follow the circle and breathe slowly.")
    }
}
