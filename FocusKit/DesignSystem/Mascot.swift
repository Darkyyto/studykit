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
        .scaleEffect(appeared ? 1 : 0.6)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.62).delay(0.15)) { appeared = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: RunLoop.main)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private func figure(side s: CGFloat, time t: Double) -> some View {
        let asleep = mood == .asleep
        let float = sin(t * 2 * .pi / (asleep ? 5 : 3.4))
        let tilt = sin(t * 2 * .pi / 6.8) * (asleep ? 1.5 : 3)
        let glow = asleep ? 0.55 + 0.25 * sin(t * 2 * .pi / 5) : 1

        return ZStack {
            Ellipse()
                .fill(.black.opacity(0.24))
                .frame(width: s * 0.5 * (1 - float * 0.08), height: s * 0.06)
                .offset(y: s * 0.43)

            ZStack {
                antenna(side: s, time: t, glow: glow)
                    .offset(y: -s * 0.33)
                head(side: s)
                face(side: s, time: t, glow: glow)
                    .offset(y: s * 0.04)
            }
            .rotationEffect(.degrees(tilt))
            .offset(y: -float * s * 0.035)
        }
        .frame(width: s, height: s)
    }

    private func head(side s: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: s * 0.3, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0xFFFFFF), Color(hex: 0xDADDE5)], startPoint: .top, endPoint: .bottom))
            .overlay {
                RoundedRectangle(cornerRadius: s * 0.3, style: .continuous)
                    .fill(RadialGradient(colors: [.white.opacity(0.9), .clear], center: UnitPoint(x: 0.3, y: 0.12), startRadius: 0, endRadius: s * 0.36))
            }
            .overlay {
                RoundedRectangle(cornerRadius: s * 0.3, style: .continuous)
                    .strokeBorder(.black.opacity(0.08), lineWidth: s * 0.012)
            }
            .frame(width: s * 0.8, height: s * 0.62)
            .offset(y: s * 0.06)
    }

    private func face(side s: CGFloat, time t: Double, glow: Double) -> some View {
        let screen = RoundedRectangle(cornerRadius: s * 0.2, style: .continuous)
        return ZStack {
            screen.fill(LinearGradient(colors: [Color(hex: 0x23232B), Color(hex: 0x111116)], startPoint: .top, endPoint: .bottom))
            Ellipse()
                .fill(RadialGradient(colors: [palette.mid.opacity(0.35 * glow), .clear], center: .center, startRadius: 0, endRadius: s * 0.28))
                .frame(width: s * 0.6, height: s * 0.36)
            eyes(side: s, time: t, glow: glow)
            screen
                .fill(LinearGradient(colors: [.white.opacity(0.1), .clear], startPoint: .top, endPoint: .center))
        }
        .frame(width: s * 0.64, height: s * 0.42)
        .clipShape(screen)
    }

    @ViewBuilder
    private func eyes(side s: CGFloat, time t: Double, glow: Double) -> some View {
        let color = palette.mid
        switch mood {
        case .asleep:
            HStack(spacing: s * 0.15) {
                Capsule().fill(color.opacity(glow))
                Capsule().fill(color.opacity(glow))
            }
            .frame(width: s * 0.31, height: s * 0.028)
            .offset(y: s * 0.03)
        case .focused:
            let scan = sin(t * 2 * .pi / 4) * s * 0.012
            HStack(spacing: s * 0.13) {
                Capsule().fill(color)
                Capsule().fill(color)
            }
            .frame(width: s * 0.3, height: s * 0.07)
            .offset(x: scan)
        case .awake:
            let cycle = t.truncatingRemainder(dividingBy: 9)
            let happy = cycle > 6.4 && cycle < 7.6
            let blinkPhase = t.truncatingRemainder(dividingBy: 3.7)
            let blink = blinkPhase < 0.16 ? max(0.12, abs(blinkPhase - 0.08) / 0.08) : 1
            let look = (sin(t * 0.5) * 0.65 + sin(t * 1.4) * 0.35) * s * 0.035
            if happy {
                HStack(spacing: s * 0.12) {
                    HappyEye().stroke(color, style: StrokeStyle(lineWidth: s * 0.045, lineCap: .round))
                    HappyEye().stroke(color, style: StrokeStyle(lineWidth: s * 0.045, lineCap: .round))
                }
                .frame(width: s * 0.3, height: s * 0.06)
                .offset(y: -s * 0.005)
            } else {
                HStack(spacing: s * 0.14) {
                    Capsule().fill(color)
                    Capsule().fill(color)
                }
                .frame(width: s * 0.26, height: s * 0.15 * blink)
                .offset(x: look)
            }
        }
    }

    private func antenna(side s: CGFloat, time t: Double, glow: Double) -> some View {
        let pulse = 0.65 + 0.35 * sin(t * 2 * .pi / 2.2)
        return VStack(spacing: 0) {
            Circle()
                .fill(palette.mid)
                .frame(width: s * 0.075, height: s * 0.075)
                .background {
                    Circle()
                        .fill(palette.mid.opacity(0.35 * pulse * glow))
                        .frame(width: s * 0.17, height: s * 0.17)
                }
                .opacity(mood == .asleep ? glow : 1)
            Capsule()
                .fill(Color(hex: 0xC9CDD6))
                .frame(width: s * 0.028, height: s * 0.07)
        }
    }
}

private struct HappyEye: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.minY - rect.height))
        return path
    }
}
