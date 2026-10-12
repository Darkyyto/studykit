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
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: RunLoop.main)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private func figure(side s: CGFloat, time t: Double) -> some View {
        let asleep = mood == .asleep
        let breath = sin(t * 2 * .pi / (asleep ? 4.4 : 3.2))
        let blinkPhase = t.truncatingRemainder(dividingBy: 4.2)
        let blink = blinkPhase < 0.14 ? max(0.08, abs(blinkPhase - 0.07) / 0.07) : 1
        let look = mood == .awake ? sin(t * 0.55) * 0.7 + sin(t * 1.7) * 0.3 : 0
        let sway = sin(t * 1.9) * (asleep ? 4 : 10)

        return ZStack {
            Ellipse()
                .fill(.black.opacity(0.22))
                .frame(width: s * 0.58 * (1 - breath * 0.04), height: s * 0.07)
                .offset(y: s * 0.44)

            ZStack {
                sprout(side: s)
                    .rotationEffect(.degrees(sway), anchor: .bottom)
                    .offset(y: -s * 0.31)

                RoundedRectangle(cornerRadius: s * 0.32, style: .continuous)
                    .fill(LinearGradient(colors: [palette.mid, palette.deep], startPoint: .top, endPoint: .bottom))
                    .overlay {
                        RoundedRectangle(cornerRadius: s * 0.32, style: .continuous)
                            .fill(RadialGradient(colors: [.white.opacity(0.5), .clear], center: UnitPoint(x: 0.28, y: 0.18), startRadius: 0, endRadius: s * 0.42))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: s * 0.32, style: .continuous)
                            .strokeBorder(.white.opacity(0.28), lineWidth: s * 0.014)
                    }
                    .frame(width: s * 0.78, height: s * 0.66)
                    .offset(y: s * 0.1)

                HStack(spacing: s * 0.3) {
                    Ellipse().fill(Color(hex: 0xFF6F8A).opacity(0.45))
                    Ellipse().fill(Color(hex: 0xFF6F8A).opacity(0.45))
                }
                .frame(width: s * 0.52, height: s * 0.055)
                .offset(y: s * 0.19)

                HStack(spacing: s * 0.12) {
                    eye(side: s, open: blink, look: look)
                    eye(side: s, open: blink, look: look)
                }
                .offset(y: s * 0.06)

                mouth(side: s)
                    .offset(y: s * 0.22)

                if asleep {
                    sleepy(side: s, time: t)
                }
            }
            .scaleEffect(x: 1 - breath * 0.015, y: 1 + breath * 0.03, anchor: .bottom)
        }
        .frame(width: s, height: s)
    }

    private func sprout(side s: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            Capsule()
                .fill(Color(hex: 0x2FA35E))
                .frame(width: s * 0.035, height: s * 0.13)
            Ellipse()
                .fill(LinearGradient(colors: [Color(hex: 0x9BE7B4), Color(hex: 0x2FA35E)], startPoint: .top, endPoint: .bottom))
                .frame(width: s * 0.15, height: s * 0.075)
                .rotationEffect(.degrees(-28))
                .offset(x: -s * 0.065, y: -s * 0.1)
            Ellipse()
                .fill(LinearGradient(colors: [Color(hex: 0x9BE7B4), Color(hex: 0x2FA35E)], startPoint: .top, endPoint: .bottom))
                .frame(width: s * 0.13, height: s * 0.065)
                .rotationEffect(.degrees(26))
                .offset(x: s * 0.06, y: -s * 0.115)
        }
        .frame(width: s * 0.32, height: s * 0.18, alignment: .bottom)
    }

    @ViewBuilder
    private func eye(side s: CGFloat, open: Double, look: Double) -> some View {
        let ink = Color(hex: 0x1C1C22)
        switch mood {
        case .asleep:
            MascotArc(bulge: 1)
                .stroke(ink, style: StrokeStyle(lineWidth: s * 0.03, lineCap: .round))
                .frame(width: s * 0.13, height: s * 0.045)
                .frame(width: s * 0.17, height: s * 0.2)
        case .awake, .focused:
            let height = s * 0.2 * (mood == .focused ? 0.78 : 1) * open
            ZStack {
                Ellipse().fill(.white)
                Circle()
                    .fill(ink)
                    .frame(width: s * 0.1, height: s * 0.1)
                    .overlay(alignment: .topLeading) {
                        Circle()
                            .fill(.white)
                            .frame(width: s * 0.034, height: s * 0.034)
                            .offset(x: s * 0.018, y: s * 0.016)
                    }
                    .offset(x: look * s * 0.028, y: s * 0.012)
            }
            .frame(width: s * 0.17, height: max(s * 0.012, height))
            .clipShape(.ellipse)
            .frame(width: s * 0.17, height: s * 0.2)
        }
    }

    @ViewBuilder
    private func mouth(side s: CGFloat) -> some View {
        let ink = Color(hex: 0x1C1C22)
        switch mood {
        case .awake:
            MascotArc(bulge: 1)
                .stroke(ink, style: StrokeStyle(lineWidth: s * 0.028, lineCap: .round))
                .frame(width: s * 0.11, height: s * 0.045)
        case .focused:
            Capsule()
                .fill(ink)
                .frame(width: s * 0.08, height: s * 0.026)
        case .asleep:
            Ellipse()
                .fill(ink.opacity(0.85))
                .frame(width: s * 0.05, height: s * 0.04)
        }
    }

    private func sleepy(side s: CGFloat, time t: Double) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                let phase = (t / 2.6 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                Text("z")
                    .font(.system(size: s * (0.1 + phase * 0.06), weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .opacity(sin(phase * .pi))
                    .offset(x: s * (0.3 + phase * 0.1), y: -s * (0.12 + phase * 0.3))
            }
        }
    }
}

private struct MascotArc: Shape {
    let bulge: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.minY + rect.height * 2 * bulge))
        return path
    }
}
