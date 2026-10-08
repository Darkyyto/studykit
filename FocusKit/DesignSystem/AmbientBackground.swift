import SwiftUI

struct AmbientBackground: View {
    let palette: ModePalette
    var intensity: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: FrameRate.half, paused: reduceMotion || !appearsActive)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            MeshGradient(
                width: 3,
                height: 3,
                points: points(at: t),
                colors: colors,
                smoothsColors: true
            )
        }
        .animation(.easeInOut(duration: 1.2), value: palette)
        .animation(.easeInOut(duration: 1.2), value: intensity)
        .ignoresSafeArea()
    }

    private var colors: [Color] {
        let isDark = colorScheme == .dark
        let light = isDark
            ? palette.light.mix(with: Palette.canvas, by: 0.55 - 0.25 * intensity)
            : palette.light.opacity(0.55 + 0.45 * intensity)
        let mid = isDark
            ? palette.mid.mix(with: Palette.canvas, by: 0.9 - 0.08 * intensity)
            : palette.mid.opacity(0.18 + 0.4 * intensity)
        return [
            Palette.canvas, light, Palette.canvas,
            light, mid, Palette.canvas,
            Palette.canvas, light, light,
        ]
    }

    private func points(at time: TimeInterval) -> [SIMD2<Float>] {
        let slow = Float(time / 34)
        let drift = { (phase: Float, amount: Float) in sin(slow + phase) * amount }
        return [
            [0, 0], [0.5 + drift(0, 0.08), 0], [1, 0],
            [0, 0.5 + drift(1.3, 0.07)], [0.5 + drift(2.1, 0.12), 0.5 + drift(0.7, 0.1)], [1, 0.5 + drift(3.4, 0.07)],
            [0, 1], [0.5 + drift(4.2, 0.08), 1], [1, 1],
        ]
    }
}
