import SwiftUI

struct OrbitScene: View {
    let state: SceneState
    let palette: ModePalette
    var planet: OrbitBody = .neptune

    private static let stars: [(x: CGFloat, y: CGFloat, size: CGFloat, phase: Double)] = {
        var generator = SeededGenerator(seed: 42)
        return (0..<70).map { _ in
            (
                x: .random(in: 0...1, using: &generator),
                y: .random(in: 0...1, using: &generator),
                size: .random(in: 1.5...3.5, using: &generator),
                phase: .random(in: 0...(2 * .pi), using: &generator)
            )
        }
    }()

    var body: some View {
        Canvas { context, size in
            let stage = state.stage
            let center = CGPoint(x: stage.midX, y: stage.midY)
            let planet = min(stage.width, stage.height) * 0.205
            let track = planet * 2.05

            drawStars(in: &context, size: size)
            drawTrack(in: &context, center: center, radius: track)
            drawPlanet(in: &context, center: center, radius: planet)
            drawMoon(in: &context, center: center, radius: planet)
            drawSatellite(in: &context, center: center, radius: track)
        }
    }

    private func drawStars(in context: inout GraphicsContext, size: CGSize) {
        for star in Self.stars {
            let twinkle = 0.35 + 0.35 * (1 + sin(state.time * 0.4 + star.phase)) / 2
            let rect = CGRect(x: star.x * size.width, y: star.y * size.height, width: star.size, height: star.size)
            context.fill(Path(ellipseIn: rect), with: .color(palette.deep.opacity(0.25 * twinkle)))
        }
    }

    private func drawTrack(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let width = 10 * state.unit
        context.stroke(Path(ellipseIn: rect), with: .color(palette.deep.opacity(0.1)), lineWidth: width)

        guard state.progress > 0 else { return }
        var arc = Path()
        arc.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * state.progress),
            clockwise: false
        )
        context.stroke(
            arc,
            with: .conicGradient(Gradient(colors: [palette.mid, palette.deep]), center: center, angle: .degrees(-90)),
            style: StrokeStyle(lineWidth: width, lineCap: .round)
        )
    }

    private func drawPlanet(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        let ringRect = CGRect(x: center.x - radius * 1.55, y: center.y - radius * 0.32, width: radius * 3.1, height: radius * 0.64)
        let tilt = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: -0.32).translatedBy(x: -center.x, y: -center.y)
        let ring = Path(ellipseIn: ringRect).applying(tilt)

        if planet.hasRings {
            var back = context
            back.clip(to: Path(CGRect(x: center.x - radius * 2, y: center.y - radius * 2, width: radius * 4, height: radius * 2)).applying(tilt))
            back.stroke(ring, with: .color(palette.mid.opacity(0.55)), lineWidth: (planet == .saturn ? 9 : 4) * state.unit)
        }

        let body = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        var lit = context
        lit.addFilter(.shadow(color: palette.deep.opacity(0.35), radius: 30, y: 16))
        lit.fill(
            body,
            with: .radialGradient(
                Gradient(colors: [palette.light, palette.mid, palette.deep]),
                center: CGPoint(x: center.x - radius * 0.4, y: center.y - radius * 0.45),
                startRadius: 0,
                endRadius: radius * 2.1
            )
        )

        var surface = context
        surface.clip(to: body)
        switch planet {
        case .moon:
            for (dx, dy, size) in [(-0.35, -0.2, 0.22), (0.3, 0.25, 0.3), (0.1, -0.45, 0.14), (-0.2, 0.5, 0.18), (0.55, -0.1, 0.12)] {
                let crater = CGRect(x: center.x + dx * radius - size * radius, y: center.y + dy * radius - size * radius, width: size * radius * 2, height: size * radius * 2)
                surface.fill(Path(ellipseIn: crater), with: .color(palette.deep.opacity(0.22)))
            }
        case .mars:
            for (dx, dy, w, h) in [(-0.4, 0.1, 0.5, 0.18), (0.2, -0.35, 0.4, 0.14), (0.1, 0.45, 0.6, 0.12)] {
                surface.fill(Path(ellipseIn: CGRect(x: center.x + dx * radius, y: center.y + dy * radius, width: w * radius, height: h * radius)), with: .color(palette.deep.opacity(0.3)))
            }
            surface.fill(Path(ellipseIn: CGRect(x: center.x - radius * 0.3, y: center.y - radius * 1.02, width: radius * 0.6, height: radius * 0.22)), with: .color(.white.opacity(0.7)))
        case .saturn, .neptune:
            for index in 0..<4 {
                let y = center.y - radius * 0.55 + CGFloat(index) * radius * 0.32
                surface.fill(
                    Path(roundedRect: CGRect(x: center.x - radius, y: y, width: radius * 2, height: radius * 0.12), cornerRadius: radius * 0.06),
                    with: .color(.white.opacity(planet == .saturn ? 0.18 : 0.12))
                )
            }
        }

        if planet.hasRings {
            var front = context
            front.clip(to: Path(CGRect(x: center.x - radius * 2, y: center.y, width: radius * 4, height: radius * 2)).applying(tilt))
            front.stroke(ring, with: .color(palette.mid.opacity(0.9)), lineWidth: (planet == .saturn ? 9 : 4) * state.unit)
        }
    }

    private func drawMoon(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        let angle = state.time * 0.35
        let point = CGPoint(x: center.x + cos(angle) * radius * 1.45, y: center.y + sin(angle) * radius * 0.5)
        guard sin(angle) > -0.2 || abs(cos(angle)) > 0.75 else { return }
        let size = radius * 0.16
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - size, y: point.y - size, width: size * 2, height: size * 2)),
            with: .color(.white.opacity(0.95))
        )
    }

    private func drawSatellite(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        let angle = -Double.pi / 2 + 2 * .pi * state.progress
        let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        let pulse = (state.isPaused ? 1 + 0.15 * sin(state.time * 2.4) : 1) * state.unit
        let unit = state.unit

        var halo = context
        halo.opacity = 0.35
        halo.fill(Path(ellipseIn: CGRect(x: point.x - 20 * pulse, y: point.y - 20 * pulse, width: 40 * pulse, height: 40 * pulse)), with: .color(palette.mid))

        var dot = context
        dot.addFilter(.shadow(color: palette.deep.opacity(0.4), radius: 6, y: 2))
        dot.fill(Path(ellipseIn: CGRect(x: point.x - 11 * unit, y: point.y - 11 * unit, width: 22 * unit, height: 22 * unit)), with: .color(.white))
        context.fill(Path(ellipseIn: CGRect(x: point.x - 5 * unit, y: point.y - 5 * unit, width: 10 * unit, height: 10 * unit)), with: .color(palette.deep))
    }
}
