import SwiftUI

struct BloomScene: View {
    let state: SceneState
    let palette: ModePalette
    var flower: FlowerKind = .daisy

    private static let leaves: [(position: Double, side: Double, size: Double)] = [
        (0.16, -1, 0.9), (0.28, 1, 1), (0.42, -1, 1.05), (0.55, 1, 0.95), (0.68, -1, 0.85), (0.8, 1, 0.7),
    ]

    private static let pollen: [(x: CGFloat, speed: Double, phase: Double, size: CGFloat)] = {
        var generator = SeededGenerator(seed: 7)
        return (0..<18).map { _ in
            (
                x: .random(in: 0...1, using: &generator),
                speed: .random(in: 8...18, using: &generator),
                phase: .random(in: 0...1, using: &generator),
                size: .random(in: 2...5, using: &generator)
            )
        }
    }()

    var body: some View {
        Canvas { context, size in
            let stage = state.stage
            let ground = CGPoint(x: stage.midX, y: stage.maxY - 34)
            let growth = Easing.smoothstep(min(1, state.progress / 0.9)) * 0.92 + 0.08
            let height = stage.height * 0.84 * growth
            let sway = state.isPaused ? 0 : sin(state.time * 0.55) * 7 * growth
            let stem = Stem(base: ground, height: height, sway: sway)

            drawPollen(in: &context, size: size)
            drawHill(in: &context, at: ground, width: stage.width)
            drawStem(stem, in: &context)
            for leaf in Self.leaves {
                let opening = Easing.ramp(state.progress, from: leaf.position - 0.04, to: leaf.position + 0.06)
                guard opening > 0 else { continue }
                drawLeaf(on: stem, at: leaf.position / 0.9, side: leaf.side, scale: opening * leaf.size, in: &context)
            }
            drawFlower(at: stem.point(at: 1), in: &context)
        }
    }

    private func drawHill(in context: inout GraphicsContext, at ground: CGPoint, width: CGFloat) {
        let hill = Path(ellipseIn: CGRect(x: ground.x - width * 0.36, y: ground.y - 18, width: width * 0.72, height: 56))
        context.fill(hill, with: .linearGradient(
            Gradient(colors: [palette.mid.opacity(0.9), palette.light.opacity(0)]),
            startPoint: CGPoint(x: ground.x, y: ground.y - 22),
            endPoint: CGPoint(x: ground.x, y: ground.y + 90)
        ))
    }

    private func drawStem(_ stem: Stem, in context: inout GraphicsContext) {
        context.stroke(
            stem.path,
            with: .linearGradient(Gradient(colors: [palette.deep, palette.mid]), startPoint: stem.base, endPoint: stem.point(at: 1)),
            style: StrokeStyle(lineWidth: 7 * state.unit, lineCap: .round)
        )
    }

    private func drawLeaf(on stem: Stem, at position: Double, side: Double, scale: Double, in context: inout GraphicsContext) {
        let anchor = stem.point(at: min(1, position))
        let length = 74 * scale * state.unit
        let width = 28 * scale * state.unit
        var leaf = Path()
        leaf.move(to: .zero)
        leaf.addQuadCurve(to: CGPoint(x: length, y: 0), control: CGPoint(x: length * 0.5, y: -width))
        leaf.addQuadCurve(to: .zero, control: CGPoint(x: length * 0.5, y: width))

        var leafContext = context
        leafContext.translateBy(x: anchor.x, y: anchor.y)
        leafContext.rotate(by: .degrees(side > 0 ? -32 : 212) + .degrees(sin(state.time * 0.8 + position * 6) * 3))
        leafContext.addFilter(.shadow(color: palette.deep.opacity(0.2), radius: 6, y: 3))
        leafContext.fill(leaf, with: .linearGradient(
            Gradient(colors: [palette.deep, palette.mid]),
            startPoint: .zero,
            endPoint: CGPoint(x: length, y: 0)
        ))
        var vein = Path()
        vein.move(to: CGPoint(x: 4, y: 0))
        vein.addLine(to: CGPoint(x: length * 0.75, y: 0))
        leafContext.stroke(vein, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
    }

    private func drawFlower(at top: CGPoint, in context: inout GraphicsContext) {
        let bud = Easing.ramp(state.progress, from: 0.78, to: 0.86)
        let bloom = Easing.ramp(state.progress, from: 0.86, to: 1)
        guard bud > 0 else {
            context.fill(Path(ellipseIn: CGRect(x: top.x - 6, y: top.y - 6, width: 12, height: 12)), with: .color(palette.mid))
            return
        }

        let kind = self.flower
        var flower = context
        flower.translateBy(x: top.x, y: top.y)
        flower.rotate(by: .degrees(state.time * 4))
        flower.addFilter(.shadow(color: kind.petal.opacity(0.35), radius: 12, y: 5))
        let unit = state.unit

        switch kind {
        case .tulip:
            flower.rotate(by: .degrees(-state.time * 4))
            let height = (24 + 30 * bloom) * unit
            let width = (14 + 10 * bloom) * unit
            for (index, angle) in [-22.0 * bloom, 0, 22.0 * bloom].enumerated() {
                var petal = flower
                petal.rotate(by: .degrees(angle))
                petal.fill(
                    Path(roundedRect: CGRect(x: -width / 2, y: -height, width: width, height: height), cornerRadius: width / 2),
                    with: .color(kind.petal.opacity(index == 1 ? 1 : 0.85))
                )
            }
        case .lavender:
            flower.rotate(by: .degrees(-state.time * 4))
            let count = 4 + Int(6 * bloom)
            for index in 0..<count {
                let y = -CGFloat(index) * 9 * unit
                let r = (5.5 - CGFloat(index) * 0.25) * unit
                for side in [-1.0, 1.0] {
                    flower.fill(Path(ellipseIn: CGRect(x: side * 4 * unit - r, y: y - r, width: r * 2, height: r * 2)), with: .color(kind.petal.opacity(0.7 + 0.3 * bud)))
                }
            }
        case .daisy, .sunflower:
            let petals = kind == .sunflower ? 16 : 8
            let length = (14 + (kind == .sunflower ? 34 : 40) * bloom) * unit
            let width = (kind == .sunflower ? 9 + 6 * bloom : 12 + 10 * bloom) * unit
            for index in 0..<petals {
                var petal = flower
                petal.rotate(by: .degrees(Double(index) / Double(petals) * 360))
                let rect = CGRect(x: -width / 2, y: -length - 4 * bloom, width: width, height: length)
                petal.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(kind.petal.opacity(0.65 + 0.35 * bud)))
            }
            let heart = ((kind == .sunflower ? 16 : 10) + 7 * bloom) * unit
            flower.fill(Path(ellipseIn: CGRect(x: -heart, y: -heart, width: heart * 2, height: heart * 2)), with: .color(kind.heart))
        }
    }

    private func drawPollen(in context: inout GraphicsContext, size: CGSize) {
        let visibility = Easing.ramp(state.progress, from: 0.3, to: 0.6)
        guard visibility > 0 else { return }
        for grain in Self.pollen {
            let travel = (grain.phase * Double(size.height) + state.time * grain.speed).truncatingRemainder(dividingBy: Double(size.height))
            let y = size.height - CGFloat(travel)
            let x = grain.x * size.width + CGFloat(sin(state.time * 0.6 + grain.phase * 9)) * 14
            context.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: grain.size, height: grain.size)),
                with: .color(flower.heart.opacity(0.45 * visibility))
            )
        }
    }
}

private struct Stem {
    let base: CGPoint
    let height: CGFloat
    let sway: Double

    var control: CGPoint {
        CGPoint(x: base.x - CGFloat(sway) * 0.4 + 10, y: base.y - height * 0.55)
    }

    var tip: CGPoint {
        CGPoint(x: base.x + CGFloat(sway), y: base.y - height)
    }

    var path: Path {
        Path { path in
            path.move(to: base)
            path.addQuadCurve(to: tip, control: control)
        }
    }

    func point(at t: Double) -> CGPoint {
        let t = CGFloat(t)
        let u = 1 - t
        return CGPoint(
            x: u * u * base.x + 2 * u * t * control.x + t * t * tip.x,
            y: u * u * base.y + 2 * u * t * control.y + t * t * tip.y
        )
    }
}
