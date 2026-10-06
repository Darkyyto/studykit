import SwiftUI

struct FlightScene: View {
    let state: SceneState
    let origin: Airport
    let destination: Airport
    let palette: ModePalette

    private enum Symbol: Hashable {
        case plane
    }

    var body: some View {
        Canvas { context, size in
            let route = RouteGeometry(from: origin, to: destination, in: state.stage)
            let aircraft = position(on: route)
            let altitude = Easing.ramp(state.progress, from: 0, to: 0.1) * Easing.ramp(1 - state.progress, from: 0, to: 0.12)

            drawGrid(in: &context, size: size, route: route)
            drawClouds(in: &context, size: size, heading: aircraft.heading, layer: 0)
            drawRoute(in: &context, route: route)
            drawAirport(origin, at: route.start, highlighted: false, in: &context)
            drawAirport(destination, at: route.end, highlighted: true, in: &context)
            drawPlane(in: &context, at: aircraft.point, heading: aircraft.heading, altitude: altitude)
            drawClouds(in: &context, size: size, heading: aircraft.heading, layer: 1)
        } symbols: {
            Image(systemName: "airplane")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(palette.deep)
                .tag(Symbol.plane)
        }
    }

    private func position(on route: RouteGeometry) -> (point: CGPoint, heading: Angle) {
        let position = route.position(at: state.progress)
        guard state.isPaused else { return position }
        let angle = state.time * 0.5
        let radius: CGFloat = 26
        let center = CGPoint(x: position.point.x, y: position.point.y - radius)
        return (CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius), .radians(angle + .pi / 2))
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize, route: RouteGeometry) {
        let topLeft = route.coordinate(at: .zero)
        let bottomRight = route.coordinate(at: CGPoint(x: size.width, y: size.height))
        let span = topLeft.latitude - bottomRight.latitude
        let step = [0.25, 0.5, 1, 2, 5, 10, 15, 30].first { span / $0 <= 14 } ?? 30
        let dot = GraphicsContext.Shading.color(palette.deep.opacity(0.16))

        var latitude = (bottomRight.latitude / step).rounded(.down) * step
        while latitude <= topLeft.latitude {
            var longitude = (topLeft.longitude / step).rounded(.down) * step
            while longitude <= bottomRight.longitude {
                let point = route.screen(latitude: latitude, longitude: longitude)
                context.fill(Path(ellipseIn: CGRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3)), with: dot)
                longitude += step
            }
            latitude += step
        }
    }

    private func drawRoute(in context: inout GraphicsContext, route: RouteGeometry) {
        context.stroke(
            Path(route.path()),
            with: .color(palette.deep.opacity(0.28)),
            style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [0.1, 10])
        )
        context.stroke(
            Path(route.path(through: state.progress)),
            with: .linearGradient(Gradient(colors: [palette.mid, palette.deep]), startPoint: route.start, endPoint: route.end),
            style: StrokeStyle(lineWidth: 4, lineCap: .round)
        )
    }

    private func drawAirport(_ airport: Airport, at point: CGPoint, highlighted: Bool, in context: inout GraphicsContext) {
        let unit = state.unit
        let radius = 11 * unit
        let outer = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        var shadowed = context
        shadowed.addFilter(.shadow(color: palette.deep.opacity(0.25), radius: 8, y: 3))
        shadowed.fill(Path(ellipseIn: outer), with: .color(.white))
        context.fill(Path(ellipseIn: outer.insetBy(dx: 6 * unit, dy: 6 * unit)), with: .color(highlighted ? palette.deep : palette.mid))

        context.draw(
            Text(airport.code).font(.rounded(14 * unit, weight: .bold)).foregroundStyle(Palette.ink),
            at: CGPoint(x: point.x, y: point.y + radius + 8 * unit),
            anchor: .top
        )
        context.draw(
            Text(airport.city).font(.rounded(12 * unit, weight: .medium)).foregroundStyle(Palette.inkSecondary),
            at: CGPoint(x: point.x, y: point.y + radius + 26 * unit),
            anchor: .top
        )
    }

    private func drawPlane(in context: inout GraphicsContext, at point: CGPoint, heading: Angle, altitude: Double) {
        guard let plane = context.resolveSymbol(id: Symbol.plane) else { return }
        let lift = (8 + 18 * altitude) * state.unit
        let scale = (0.85 + 0.2 * altitude) * state.unit

        var shadow = context
        shadow.opacity = 0.18
        shadow.addFilter(.blur(radius: 3))
        shadow.addFilter(.colorMultiply(palette.deep))
        shadow.translateBy(x: point.x + lift * 0.5, y: point.y + lift)
        shadow.rotate(by: heading)
        shadow.scaleBy(x: scale * 0.9, y: scale * 0.9)
        shadow.draw(plane, at: .zero)

        var body = context
        body.translateBy(x: point.x, y: point.y)
        body.rotate(by: heading)
        body.scaleBy(x: scale, y: scale)
        body.draw(plane, at: .zero)
    }

    private func drawClouds(in context: inout GraphicsContext, size: CGSize, heading: Angle, layer: Int) {
        let speed: CGFloat = layer == 0 ? 6 : 14
        let drift = CGPoint(x: -cos(heading.radians) * speed * state.time, y: -sin(heading.radians) * speed * state.time)
        CloudField.draw(in: &context, size: size, drift: drift, layer: layer, scale: state.unit, shadow: palette.deep)
    }
}

enum CloudField {
    private struct Cloud {
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let layer: Int
        let puffs: [(dx: CGFloat, dy: CGFloat, radius: CGFloat)]
    }

    private static let clouds: [Cloud] = {
        var generator = SeededGenerator(seed: 11)
        return (0..<8).map { index in
            let count = Int.random(in: 3...5, using: &generator)
            let puffs = (0..<count).map { item in
                let spread = CGFloat(item) / CGFloat(max(1, count - 1)) - 0.5
                return (dx: spread * 1.5, dy: CGFloat.random(in: -0.12...0.08, using: &generator), radius: CGFloat.random(in: 0.38...0.6, using: &generator))
            }
            return Cloud(
                x: .random(in: 0...1, using: &generator),
                y: .random(in: 0...1, using: &generator),
                size: .random(in: 46...84, using: &generator),
                layer: index % 3 == 0 ? 1 : 0,
                puffs: puffs
            )
        }
    }()

    static func draw(in context: inout GraphicsContext, size: CGSize, drift: CGPoint, layer: Int, scale: CGFloat, shadow: Color) {
        let margin: CGFloat = 200
        let width = size.width + margin * 2
        let height = size.height + margin * 2

        for cloud in clouds where cloud.layer == layer {
            var x = (cloud.x * width + drift.x).truncatingRemainder(dividingBy: width)
            var y = (cloud.y * height + drift.y).truncatingRemainder(dividingBy: height)
            if x < 0 { x += width }
            if y < 0 { y += height }
            let center = CGPoint(x: x - margin, y: y - margin)
            let cloud = Cloud(x: cloud.x, y: cloud.y, size: cloud.size * scale, layer: cloud.layer, puffs: cloud.puffs)

            var shape = Path()
            for puff in cloud.puffs {
                let radius = puff.radius * cloud.size
                shape.addEllipse(in: CGRect(
                    x: center.x + puff.dx * cloud.size - radius,
                    y: center.y + puff.dy * cloud.size - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
            }
            shape.addRoundedRect(
                in: CGRect(x: center.x - cloud.size * 0.85, y: center.y, width: cloud.size * 1.7, height: cloud.size * 0.42),
                cornerSize: CGSize(width: cloud.size * 0.21, height: cloud.size * 0.21)
            )

            var layerContext = context
            layerContext.opacity = layer == 0 ? 0.75 : 0.92
            layerContext.addFilter(.shadow(color: shadow.opacity(0.12), radius: 14, y: 10))
            layerContext.fill(shape, with: .color(.white))
        }
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed &* 0x9E3779B97F4A7C15
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
