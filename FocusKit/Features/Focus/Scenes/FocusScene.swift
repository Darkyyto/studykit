import SwiftUI

extension EnvironmentValues {
    @Entry var isOnScreen = true
}

enum FrameRate {
    static let full = 1.0 / 64
    static let half = 1.0 / 32
    static let quarter = 1.0 / 16

    static func interval(active: Bool) -> Double {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        switch (active, lowPower) {
        case (true, false): return full
        case (false, true): return quarter
        default: return half
        }
    }
}

struct SceneState {
    var progress: Double
    var time: TimeInterval
    var isPaused: Bool
    var stage: CGRect

    var unit: CGFloat {
        min(1.15, max(0.4, min(stage.width, stage.height) / 360))
    }
}

struct FocusScene: View {
    let mode: FocusMode
    let progress: (Date) -> Double
    var route: Session.Route?
    var variant: String?
    var isPaused = false
    var isAnimated = true
    var insets = EdgeInsets(top: 90, leading: 60, bottom: 280, trailing: 60)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.isOnScreen) private var isOnScreen

    var body: some View {
        TimelineView(.animation(minimumInterval: FrameRate.interval(active: appearsActive), paused: !isAnimated || reduceMotion || !isOnScreen)) { context in
            let time = isAnimated && !reduceMotion ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600) : 12
            let progress = min(1, max(0, progress(context.date)))
            GeometryReader { proxy in
                let state = SceneState(
                    progress: progress,
                    time: time,
                    isPaused: isPaused,
                    stage: CGRect(
                        x: insets.leading,
                        y: insets.top,
                        width: max(1, proxy.size.width - insets.leading - insets.trailing),
                        height: max(1, proxy.size.height - insets.top - insets.bottom)
                    )
                )
                scene(state)
                    .drawingGroup()
            }
        }
        .accessibilityElement()
        .accessibilityLabel(mode.title)
    }

    @ViewBuilder
    private func scene(_ state: SceneState) -> some View {
        switch mode {
        case .flight:
            let resolved = FlightRoute.resolve(route)
            FlightScene(state: state, origin: resolved.origin, destination: resolved.destination, palette: mode.palette)
        case .orbit:
            let planet = OrbitBody.resolve(variant)
            OrbitScene(state: state, palette: planet.palette, planet: planet)
        case .bloom:
            BloomScene(state: state, palette: mode.palette, flower: FlowerKind.resolve(variant))
        case .tide:
            let tide = TideVariant.resolve(variant)
            TideScene(state: state, palette: tide.sky.water, variant: tide)
        }
    }
}

enum FlightRoute {
    static func resolve(_ route: Session.Route?) -> (origin: Airport, destination: Airport) {
        let origin = route.flatMap { Airport.named($0.origin) } ?? .fallback
        let destination = route.flatMap { Airport.named($0.destination) } ?? origin.routes(closestTo: 45 * 60)[0]
        return (origin, destination)
    }
}

enum Easing {
    static func smoothstep(_ value: Double) -> Double {
        let x = min(1, max(0, value))
        return x * x * (3 - 2 * x)
    }

    static func ramp(_ value: Double, from start: Double, to end: Double) -> Double {
        smoothstep((value - start) / (end - start))
    }
}
