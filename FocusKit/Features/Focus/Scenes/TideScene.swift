import SwiftUI

struct TideScene: View {
    let state: SceneState
    let palette: ModePalette
    var variant = TideVariant(boat: .sailboat, sky: .day)

    private struct Wave {
        let amplitude: CGFloat
        let length: CGFloat
        let speed: Double
        let offset: CGFloat
    }

    private static let waves = [
        Wave(amplitude: 14, length: 520, speed: 0.35, offset: -22),
        Wave(amplitude: 11, length: 380, speed: -0.5, offset: -8),
        Wave(amplitude: 9, length: 300, speed: 0.7, offset: 6),
    ]

    private static let bubbles: [(x: CGFloat, speed: Double, phase: Double, size: CGFloat)] = {
        var generator = SeededGenerator(seed: 19)
        return (0..<22).map { _ in
            (
                x: .random(in: 0...1, using: &generator),
                speed: .random(in: 10...26, using: &generator),
                phase: .random(in: 0...1, using: &generator),
                size: .random(in: 3...9, using: &generator)
            )
        }
    }()

    var body: some View {
        Canvas { context, size in
            let stage = state.stage
            let level = stage.maxY + 60 - (stage.height + 60) * CGFloat(0.1 + 0.62 * state.progress)
            let calm = state.isPaused ? 0.35 : 1.0

            drawSun(in: &context, size: size, stage: stage)
            drawClouds(in: &context, size: size, stage: stage)
            drawGulls(in: &context, size: size, stage: stage)
            drawIsland(in: &context, size: size, level: level)
            for (index, wave) in Self.waves.enumerated() {
                let path = surface(wave, level: level, width: size.width, height: size.height, calm: calm)
                let opacity = [0.35, 0.5, 0.85][index]
                context.fill(path, with: .linearGradient(
                    Gradient(colors: [palette.mid.opacity(opacity), palette.deep.opacity(opacity)]),
                    startPoint: CGPoint(x: 0, y: level),
                    endPoint: CGPoint(x: 0, y: size.height)
                ))
                if index == 1 {
                    drawWake(in: &context, wave: wave, level: level, x: stage.midX, calm: calm)
                    drawBoat(in: &context, wave: wave, level: level, x: stage.midX, calm: calm)
                }
            }
            drawGlitter(in: &context, size: size, stage: stage, level: level)
            drawBubbles(in: &context, size: size, level: level)
        }
    }

    private func height(of wave: Wave, at x: CGFloat, calm: Double) -> CGFloat {
        let phase = Double(x / wave.length) * 2 * .pi + state.time * wave.speed
        return CGFloat(sin(phase)) * wave.amplitude * CGFloat(calm) + wave.offset
    }

    private func surface(_ wave: Wave, level: CGFloat, width: CGFloat, height: CGFloat, calm: Double) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: height))
            var x: CGFloat = 0
            while x <= width + 12 {
                path.addLine(to: CGPoint(x: x, y: level + self.height(of: wave, at: x, calm: calm)))
                x += 12
            }
            path.addLine(to: CGPoint(x: width, y: height))
            path.closeSubpath()
        }
    }

    private func drawSun(in context: inout GraphicsContext, size: CGSize, stage: CGRect) {
        let center = CGPoint(x: stage.maxX - stage.width * 0.12, y: stage.minY + stage.height * 0.18)
        let radius = min(stage.width, stage.height) * 0.11
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - radius * 2.4, y: center.y - radius * 2.4, width: radius * 4.8, height: radius * 4.8)),
            with: .radialGradient(Gradient(colors: [variant.sky.sun.0.opacity(0.7), .clear]), center: center, startRadius: radius, endRadius: radius * 2.4)
        )
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .linearGradient(Gradient(colors: [variant.sky.sun.0, variant.sky.sun.1]), startPoint: CGPoint(x: center.x, y: center.y - radius), endPoint: CGPoint(x: center.x, y: center.y + radius))
        )
    }

    private func drawBoat(in context: inout GraphicsContext, wave: Wave, level: CGFloat, x: CGFloat, calm: Double) {
        let y = level + height(of: wave, at: x, calm: calm)
        let slope = height(of: wave, at: x + 10, calm: calm) - height(of: wave, at: x - 10, calm: calm)
        let tilt = Angle.radians(Double(atan2(slope, 20)))

        var boat = context
        boat.translateBy(x: x, y: y - 4)
        boat.rotate(by: tilt)
        boat.scaleBy(x: state.unit * 1.35, y: state.unit * 1.35)
        boat.addFilter(.shadow(color: palette.deep.opacity(0.3), radius: 8, y: 4))

        switch variant.boat {
        case .sailboat:
            var hull = Path()
            hull.move(to: CGPoint(x: -38, y: -8))
            hull.addLine(to: CGPoint(x: 38, y: -8))
            hull.addQuadCurve(to: CGPoint(x: 24, y: 10), control: CGPoint(x: 34, y: 6))
            hull.addLine(to: CGPoint(x: -24, y: 10))
            hull.addQuadCurve(to: CGPoint(x: -38, y: -8), control: CGPoint(x: -34, y: 6))
            boat.fill(hull, with: .color(.white))
            boat.fill(Path(roundedRect: CGRect(x: -1.5, y: -64, width: 3, height: 58), cornerRadius: 1.5), with: .color(Palette.ink.opacity(0.7)))
            var sail = Path()
            sail.move(to: CGPoint(x: 3, y: -62))
            sail.addQuadCurve(to: CGPoint(x: 3, y: -14), control: CGPoint(x: 40, y: -26))
            sail.closeSubpath()
            boat.fill(sail, with: .color(.white))
            var jib = Path()
            jib.move(to: CGPoint(x: -3, y: -54))
            jib.addQuadCurve(to: CGPoint(x: -3, y: -14), control: CGPoint(x: -26, y: -22))
            jib.closeSubpath()
            boat.fill(jib, with: .color(Color(hex: 0xFF8F70)))
        case .paper:
            var hull = Path()
            hull.move(to: CGPoint(x: -40, y: -10))
            hull.addLine(to: CGPoint(x: 40, y: -10))
            hull.addLine(to: CGPoint(x: 26, y: 8))
            hull.addLine(to: CGPoint(x: -26, y: 8))
            hull.closeSubpath()
            boat.fill(hull, with: .color(Color(hex: 0xF4F1EA)))
            var fold = Path()
            fold.move(to: CGPoint(x: -24, y: -10))
            fold.addLine(to: CGPoint(x: 0, y: -46))
            fold.addLine(to: CGPoint(x: 24, y: -10))
            fold.closeSubpath()
            boat.fill(fold, with: .color(.white))
            var crease = Path()
            crease.move(to: CGPoint(x: 0, y: -46))
            crease.addLine(to: CGPoint(x: 0, y: -10))
            boat.stroke(crease, with: .color(Palette.ink.opacity(0.15)), lineWidth: 1)
        case .catamaran:
            for side in [-1.0, 1.0] {
                boat.fill(
                    Path(roundedRect: CGRect(x: -40, y: side < 0 ? -4 : 2, width: 80, height: 9), cornerRadius: 4.5),
                    with: .color(.white.opacity(side < 0 ? 0.85 : 1))
                )
            }
            boat.fill(Path(roundedRect: CGRect(x: -30, y: -10, width: 60, height: 8), cornerRadius: 3), with: .color(Color(hex: 0xE9EEF3)))
            boat.fill(Path(roundedRect: CGRect(x: -1.5, y: -70, width: 3, height: 62), cornerRadius: 1.5), with: .color(Palette.ink.opacity(0.7)))
            var sail = Path()
            sail.move(to: CGPoint(x: 3, y: -68))
            sail.addLine(to: CGPoint(x: 34, y: -14))
            sail.addLine(to: CGPoint(x: 3, y: -14))
            sail.closeSubpath()
            boat.fill(sail, with: .color(FocusMode.tide.palette.mid))
        }
    }

    private func drawClouds(in context: inout GraphicsContext, size: CGSize, stage: CGRect) {
        let clouds: [(y: CGFloat, scale: CGFloat, speed: Double, phase: Double)] = [(0.12, 1.0, 6, 0.1), (0.26, 0.7, 9, 0.55), (0.06, 0.55, 4, 0.8)]
        for cloud in clouds {
            let span = Double(size.width) + 300
            let x = CGFloat((cloud.phase * span + state.time * cloud.speed).truncatingRemainder(dividingBy: span)) - 150
            let y = stage.minY + stage.height * cloud.y
            let w = 120 * cloud.scale * state.unit
            var shape = Path()
            for (dx, dy, r) in [(-0.3, 0.1, 0.28), (0.0, -0.05, 0.36), (0.3, 0.08, 0.26), (0.05, 0.16, 0.3)] {
                let radius = w * CGFloat(r)
                shape.addEllipse(in: CGRect(x: x + w * CGFloat(dx) - radius, y: y + w * CGFloat(dy) - radius * 0.7, width: radius * 2, height: radius * 1.4))
            }
            context.fill(shape, with: .color(.white.opacity(0.75)))
        }
    }

    private func drawGulls(in context: inout GraphicsContext, size: CGSize, stage: CGRect) {
        for index in 0..<3 {
            let t = state.time * 0.05 + Double(index) * 0.13
            let x = CGFloat(t.truncatingRemainder(dividingBy: 1.2) / 1.2) * (size.width + 80) - 40
            let y = stage.minY + stage.height * CGFloat(0.22 + 0.06 * Double(index)) + CGFloat(sin(state.time * 0.6 + Double(index))) * 8
            let flap = CGFloat(sin(state.time * 5 + Double(index) * 2)) * 3
            let w = (9 - CGFloat(index) * 1.5) * state.unit
            var gull = Path()
            gull.move(to: CGPoint(x: x - w, y: y - flap))
            gull.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x - w * 0.5, y: y - w * 0.6 - flap))
            gull.addQuadCurve(to: CGPoint(x: x + w, y: y - flap), control: CGPoint(x: x + w * 0.5, y: y - w * 0.6 - flap))
            context.stroke(gull, with: .color(Palette.ink.opacity(0.45)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
    }

    private func drawIsland(in context: inout GraphicsContext, size: CGSize, level: CGFloat) {
        let base = level - 16
        let x = size.width * 0.2
        let w = 150 * state.unit
        var island = Path()
        island.move(to: CGPoint(x: x - w / 2, y: base + 6))
        island.addQuadCurve(to: CGPoint(x: x + w / 2, y: base + 6), control: CGPoint(x: x, y: base - 40 * state.unit))
        island.closeSubpath()
        context.fill(island, with: .color(palette.deep.opacity(0.28)))
        var trunk = Path()
        trunk.move(to: CGPoint(x: x + 6, y: base - 14 * state.unit))
        trunk.addQuadCurve(to: CGPoint(x: x + 16 * state.unit, y: base - 52 * state.unit), control: CGPoint(x: x + 4, y: base - 36 * state.unit))
        context.stroke(trunk, with: .color(palette.deep.opacity(0.32)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        let top = CGPoint(x: x + 16 * state.unit, y: base - 52 * state.unit)
        for angle in [-150.0, -110.0, -60.0, -20.0, 20.0] {
            let sway = sin(state.time * 0.8) * 4
            let radians = (angle + sway) * .pi / 180
            var frond = Path()
            frond.move(to: top)
            let end = CGPoint(x: top.x + CGFloat(cos(radians)) * 24 * state.unit, y: top.y + CGFloat(sin(radians)) * 14 * state.unit + 6)
            frond.addQuadCurve(to: end, control: CGPoint(x: (top.x + end.x) / 2, y: min(top.y, end.y) - 6))
            context.stroke(frond, with: .color(palette.deep.opacity(0.32)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        }
    }

    private func drawGlitter(in context: inout GraphicsContext, size: CGSize, stage: CGRect, level: CGFloat) {
        let sunX = stage.maxX - stage.width * 0.12
        for row in 0..<7 {
            let y = level + 8 + CGFloat(row) * 12
            guard y < size.height else { continue }
            let spread = 20 + CGFloat(row) * 10
            for dash in 0..<3 {
                let shimmer = 0.5 + 0.5 * sin(state.time * 2.2 + Double(row * 3 + dash))
                let x = sunX + CGFloat(dash - 1) * spread * 0.7 + CGFloat(sin(state.time * 0.7 + Double(row))) * 6
                let w = (18 - CGFloat(row)) * CGFloat(shimmer)
                context.fill(
                    Path(roundedRect: CGRect(x: x - w / 2, y: y, width: w, height: 2), cornerRadius: 1),
                    with: .color(.white.opacity(0.65 * shimmer))
                )
            }
        }
    }

    private func drawWake(in context: inout GraphicsContext, wave: Wave, level: CGFloat, x: CGFloat, calm: Double) {
        let y = level + height(of: wave, at: x, calm: calm) + 8 * state.unit
        for index in 0..<3 {
            let progress = (state.time * 0.6 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
            let length = CGFloat(30 + 70 * progress) * state.unit
            var line = Path()
            line.move(to: CGPoint(x: x - 40 * state.unit, y: y + CGFloat(index) * 3))
            line.addLine(to: CGPoint(x: x - 40 * state.unit - length, y: y + CGFloat(index) * 3 + 2))
            context.stroke(line, with: .color(.white.opacity(0.6 * (1 - progress))), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }

    private func drawBubbles(in context: inout GraphicsContext, size: CGSize, level: CGFloat) {
        let depth = size.height - level
        guard depth > 40 else { return }
        for bubble in Self.bubbles {
            let travel = (bubble.phase * Double(depth) + state.time * bubble.speed).truncatingRemainder(dividingBy: Double(depth))
            let y = size.height - CGFloat(travel)
            guard y > level + 20 else { continue }
            let x = bubble.x * size.width + CGFloat(sin(state.time + bubble.phase * 7)) * 6
            context.stroke(
                Path(ellipseIn: CGRect(x: x, y: y, width: bubble.size, height: bubble.size)),
                with: .color(.white.opacity(0.55)),
                lineWidth: 1.3
            )
        }
    }
}
