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

    private static let sprouts: [(offset: CGFloat, start: Double, height: CGFloat, lean: Double)] = [
        (-0.2, 0.18, 0.16, -0.12), (0.17, 0.3, 0.2, 0.1), (-0.32, 0.46, 0.12, -0.2), (0.3, 0.6, 0.14, 0.18),
    ]

    private static let blades: [(offset: CGFloat, height: CGFloat, phase: Double)] = {
        var generator = SeededGenerator(seed: 21)
        return (0..<26).map { _ in
            (
                offset: .random(in: -0.42...0.42, using: &generator),
                height: .random(in: 8...20, using: &generator),
                phase: .random(in: 0...6, using: &generator)
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

            drawSun(in: &context, size: size)
            drawPollen(in: &context, size: size)
            drawBackHills(in: &context, ground: ground, size: size)
            drawHill(in: &context, at: ground, width: stage.width)
            drawSprouts(in: &context, ground: ground, width: stage.width)
            drawGrass(in: &context, ground: ground, width: stage.width)
            drawStem(stem, in: &context)
            for leaf in Self.leaves {
                let opening = Easing.ramp(state.progress, from: leaf.position - 0.04, to: leaf.position + 0.06)
                guard opening > 0 else { continue }
                drawLeaf(on: stem, at: leaf.position / 0.9, side: leaf.side, scale: opening * leaf.size, in: &context)
            }
            drawFlower(at: stem.point(at: 1), in: &context)
            drawButterflies(in: &context, around: stem.point(at: 0.7), size: size)
        }
    }

    private func drawSun(in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width * 0.82, y: size.height * 0.16)
        let radius = max(size.width, size.height) * 0.32
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .radialGradient(
                Gradient(colors: [Color(hex: 0xFFE9B0).opacity(0.55 + 0.25 * state.progress), Color(hex: 0xFFE9B0).opacity(0)]),
                center: center,
                startRadius: 0,
                endRadius: radius
            )
        )
    }

    private func drawBackHills(in context: inout GraphicsContext, ground: CGPoint, size: CGSize) {
        for (index, layer) in [(lift: 70.0, amplitude: 26.0, opacity: 0.22, phase: 0.0), (lift: 38.0, amplitude: 18.0, opacity: 0.32, phase: 2.1)].enumerated() {
            var hills = Path()
            let base = ground.y - CGFloat(layer.lift) * state.unit
            hills.move(to: CGPoint(x: 0, y: size.height))
            hills.addLine(to: CGPoint(x: 0, y: base))
            let steps = 24
            for step in 0...steps {
                let x = size.width * CGFloat(step) / CGFloat(steps)
                let wave = sin(Double(step) / Double(steps) * .pi * 2.2 + layer.phase) + 0.4 * sin(Double(step) / Double(steps) * .pi * 5 + layer.phase)
                hills.addLine(to: CGPoint(x: x, y: base - CGFloat(wave * layer.amplitude) * state.unit))
            }
            hills.addLine(to: CGPoint(x: size.width, y: size.height))
            hills.closeSubpath()
            context.fill(hills, with: .linearGradient(
                Gradient(colors: [palette.mid.opacity(layer.opacity + 0.12 * Double(index) * state.progress), palette.light.opacity(0)]),
                startPoint: CGPoint(x: 0, y: base - 30),
                endPoint: CGPoint(x: 0, y: size.height)
            ))
        }
    }

    private func drawSprouts(in context: inout GraphicsContext, ground: CGPoint, width: CGFloat) {
        for sprout in Self.sprouts {
            let grow = Easing.ramp(state.progress, from: sprout.start, to: sprout.start + 0.18)
            guard grow > 0 else { continue }
            let base = CGPoint(x: ground.x + width * sprout.offset, y: ground.y + 4 + abs(sprout.offset) * 26)
            let height = state.stage.height * sprout.height * grow
            let sway = sin(state.time * 0.7 + Double(sprout.offset) * 9) * 3 + sprout.lean * 20
            let tip = CGPoint(x: base.x + CGFloat(sway) * grow, y: base.y - height)
            var stem = Path()
            stem.move(to: base)
            stem.addQuadCurve(to: tip, control: CGPoint(x: base.x + CGFloat(sway) * 0.2, y: base.y - height * 0.6))
            context.stroke(stem, with: .color(palette.deep.opacity(0.85)), style: StrokeStyle(lineWidth: 3.2 * state.unit, lineCap: .round))
            for side in [-1.0, 1.0] {
                let size = 24 * grow * state.unit
                var leaf = Path()
                leaf.move(to: .zero)
                leaf.addQuadCurve(to: CGPoint(x: size, y: 0), control: CGPoint(x: size * 0.5, y: -size * 0.45))
                leaf.addQuadCurve(to: .zero, control: CGPoint(x: size * 0.5, y: size * 0.45))
                var leafContext = context
                let anchor = CGPoint(x: base.x + (tip.x - base.x) * 0.55, y: base.y - height * 0.55)
                leafContext.translateBy(x: anchor.x, y: anchor.y)
                leafContext.rotate(by: .degrees(side > 0 ? -38 : 218) + .degrees(sin(state.time + side) * 4))
                leafContext.fill(leaf, with: .color(palette.mid))
            }
            let blossom = Easing.ramp(state.progress, from: 0.9, to: 1)
            if blossom > 0 {
                let r = 6 * blossom * state.unit
                for index in 0..<5 {
                    let angle = Double(index) / 5 * .pi * 2 + state.time * 0.2
                    let petal = CGPoint(x: tip.x + CGFloat(cos(angle)) * r, y: tip.y + CGFloat(sin(angle)) * r)
                    context.fill(Path(ellipseIn: CGRect(x: petal.x - r * 0.7, y: petal.y - r * 0.7, width: r * 1.4, height: r * 1.4)), with: .color(flower.petal.opacity(0.85)))
                }
                context.fill(Path(ellipseIn: CGRect(x: tip.x - r * 0.55, y: tip.y - r * 0.55, width: r * 1.1, height: r * 1.1)), with: .color(flower.heart))
            } else {
                context.fill(Path(ellipseIn: CGRect(x: tip.x - 3, y: tip.y - 3, width: 6, height: 6)), with: .color(palette.mid))
            }
        }
    }

    private func drawGrass(in context: inout GraphicsContext, ground: CGPoint, width: CGFloat) {
        let lushness = 0.35 + 0.65 * Easing.smoothstep(state.progress)
        for blade in Self.blades {
            let x = ground.x + width * blade.offset
            let y = ground.y + 6 + abs(blade.offset) * 30
            let height = blade.height * CGFloat(lushness) * state.unit
            let bend = CGFloat(sin(state.time * 1.1 + blade.phase) * 3)
            var path = Path()
            path.move(to: CGPoint(x: x - 2, y: y))
            path.addQuadCurve(to: CGPoint(x: x + bend, y: y - height), control: CGPoint(x: x - 1, y: y - height * 0.6))
            path.addQuadCurve(to: CGPoint(x: x + 2, y: y), control: CGPoint(x: x + 1, y: y - height * 0.6))
            context.fill(path, with: .color(palette.deep.opacity(0.35 + 0.25 * lushness)))
        }
    }

    private func drawButterflies(in context: inout GraphicsContext, around anchor: CGPoint, size: CGSize) {
        let visibility = Easing.ramp(state.progress, from: 0.5, to: 0.62)
        guard visibility > 0 else { return }
        let colors = [flower.petal, Color(hex: 0xFFB48A)]
        for index in 0..<2 {
            let t = state.time * (0.32 + Double(index) * 0.07) + Double(index) * 2.4
            let center = CGPoint(
                x: anchor.x + CGFloat(sin(t) * 120 + sin(t * 2.3) * 24) * state.unit,
                y: anchor.y + CGFloat(cos(t * 0.8) * 60 + sin(t * 3.1) * 12) * state.unit - CGFloat(index) * 40
            )
            let flap = state.isPaused ? 0.6 : abs(sin(state.time * 14 + Double(index)))
            var butterfly = context
            butterfly.translateBy(x: center.x, y: center.y)
            butterfly.rotate(by: .radians(sin(t) * 0.3))
            butterfly.opacity = visibility
            let wing = 12 * state.unit
            for side in [-1.0, 1.0] {
                let rect = CGRect(x: side > 0 ? 0 : -wing * CGFloat(0.3 + 0.7 * flap), y: -wing * 0.9, width: wing * CGFloat(0.3 + 0.7 * flap), height: wing * 1.4)
                butterfly.fill(Path(ellipseIn: rect), with: .color(colors[index].opacity(0.9)))
            }
            butterfly.fill(Path(roundedRect: CGRect(x: -1.2, y: -wing * 0.7, width: 2.4, height: wing * 1.3), cornerRadius: 1.2), with: .color(palette.deep))
        }
    }

    private func drawHill(in context: inout GraphicsContext, at ground: CGPoint, width: CGFloat) {
        let half = width * 0.46
        var hill = Path()
        hill.move(to: CGPoint(x: ground.x - half, y: ground.y + 48))
        hill.addCurve(
            to: CGPoint(x: ground.x, y: ground.y - 14),
            control1: CGPoint(x: ground.x - half * 0.55, y: ground.y + 10),
            control2: CGPoint(x: ground.x - half * 0.35, y: ground.y - 14)
        )
        hill.addCurve(
            to: CGPoint(x: ground.x + half, y: ground.y + 48),
            control1: CGPoint(x: ground.x + half * 0.35, y: ground.y - 14),
            control2: CGPoint(x: ground.x + half * 0.55, y: ground.y + 10)
        )
        hill.closeSubpath()
        context.fill(hill, with: .linearGradient(
            Gradient(colors: [palette.mid.opacity(0.95), palette.mid.opacity(0.35), palette.light.opacity(0)]),
            startPoint: CGPoint(x: ground.x, y: ground.y - 16),
            endPoint: CGPoint(x: ground.x, y: ground.y + 60)
        ))
        var highlight = Path()
        highlight.move(to: CGPoint(x: ground.x - half * 0.5, y: ground.y + 2))
        highlight.addQuadCurve(to: CGPoint(x: ground.x + half * 0.2, y: ground.y - 12), control: CGPoint(x: ground.x - half * 0.2, y: ground.y - 14))
        context.stroke(highlight, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
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
