import Combine
import SwiftUI

struct Mascot: View {
    enum Mood {
        case awake
        case focused
        case asleep
    }

    let palette: ModePalette
    var mood: Mood = .awake
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var appeared = false

    private var isStill: Bool {
        reduceMotion || lowPower
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: mood == .asleep ? 1.0 / 12 : 1.0 / 24, paused: isStill)) { context in
            GeometryReader { proxy in
                figure(side: min(proxy.size.width, proxy.size.height), time: isStill ? 0 : context.date.timeIntervalSinceReferenceDate)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .drawingGroup()
        .scaleEffect(appeared ? 1 : 0.5)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.6).delay(0.15)) { appeared = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: RunLoop.main)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private func figure(side s: CGFloat, time t: Double) -> some View {
        let asleep = mood == .asleep
        let breath = sin(t * 2 * .pi / (asleep ? 5 : 3.2))
        let hopCycle = t.truncatingRemainder(dividingBy: 8)
        let hop = mood == .awake && hopCycle > 6.6 && hopCycle < 7.4 ? sin((hopCycle - 6.6) / 0.8 * .pi) : 0
        let squash = 1 + breath * 0.025 - hop * 0.04
        let blob = Blob(
            lobes: 6,
            depth: asleep ? 0.035 : 0.05,
            turn: t * (asleep ? 0.05 : 0.12),
            wobble: t * 1.3
        )

        return ZStack {
            Ellipse()
                .fill(.black.opacity(0.22))
                .frame(width: s * 0.56 * (1 - hop * 0.25), height: s * 0.07)
                .offset(y: s * 0.42)

            ZStack {
                blob
                    .fill(RadialGradient(colors: [Color(hex: 0xFFFFFF), Color(hex: 0xECEDF1), Color(hex: 0xB9BDC8)], center: UnitPoint(x: 0.36, y: 0.3), startRadius: 0, endRadius: s * 0.5))
                blob
                    .fill(RadialGradient(colors: [.clear, palette.mid.opacity(0.28)], center: UnitPoint(x: 0.4, y: 0.36), startRadius: s * 0.26, endRadius: s * 0.44))
                blob
                    .fill(RadialGradient(colors: [.white.opacity(0.9), .clear], center: UnitPoint(x: 0.32, y: 0.22), startRadius: 0, endRadius: s * 0.16))
                blob
                    .fill(RadialGradient(colors: [.clear, Color(hex: 0x5A5F6E).opacity(0.45)], center: UnitPoint(x: 0.44, y: 0.36), startRadius: s * 0.24, endRadius: s * 0.47))
                eyes(side: s, time: t)
                    .offset(y: -s * 0.02)
            }
            .frame(width: s * 0.8, height: s * 0.8)
            .scaleEffect(x: 2 - squash, y: squash, anchor: .bottom)
            .offset(y: -s * 0.02 - hop * s * 0.09)
        }
        .frame(width: s, height: s)
    }

    @ViewBuilder
    private func eyes(side s: CGFloat, time t: Double) -> some View {
        switch mood {
        case .asleep:
            HStack(spacing: s * 0.1) {
                Capsule().fill(Color(hex: 0x1C1C22).opacity(0.85))
                Capsule().fill(Color(hex: 0x1C1C22).opacity(0.85))
            }
            .frame(width: s * 0.28, height: s * 0.045)
            .offset(y: s * 0.03)
        case .focused:
            HStack(spacing: s * 0.11) {
                Capsule().fill(Color(hex: 0x1C1C22)).rotationEffect(.degrees(16))
                Capsule().fill(Color(hex: 0x1C1C22)).rotationEffect(.degrees(-16))
            }
            .frame(width: s * 0.27, height: s * 0.12)
        case .awake:
            let blinkPhase = t.truncatingRemainder(dividingBy: 3.8)
            let blink = blinkPhase < 0.16 ? max(0.12, abs(blinkPhase - 0.08) / 0.08) : 1
            let look = (sin(t * 0.5) * 0.65 + sin(t * 1.4) * 0.35) * s * 0.03
            HStack(spacing: s * 0.1) {
                Capsule().fill(Color(hex: 0x1C1C22)).rotationEffect(.degrees(-12))
                Capsule().fill(Color(hex: 0x1C1C22)).rotationEffect(.degrees(-12))
            }
            .frame(width: s * 0.25, height: s * 0.19 * blink)
            .offset(x: look)
        }
    }
}

private struct Blob: Shape {
    let lobes: Int
    let depth: Double
    let turn: Double
    let wobble: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 / (1 + depth + 0.02)
        let steps = 96
        var path = Path()
        for step in 0...steps {
            let angle = Double(step) / Double(steps) * 2 * .pi
            let lobe = cos(Double(lobes) * angle + turn) * depth
            let drift = sin(2 * angle + wobble) * 0.02
            let r = radius * (1 + lobe + drift)
            let point = CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}
