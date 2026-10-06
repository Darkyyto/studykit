import SwiftUI

struct LaunchView: View {
    let finish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appears = false
    @State private var writing = 0.0
    @State private var leaves = false

    var body: some View {
        ZStack {
            Palette.canvas
                .opacity(leaves ? 0 : 1)
                .ignoresSafeArea()

            WritingLogo(progress: writing)
                .frame(width: 132, height: 132)
                .shadow(color: .black.opacity(0.12), radius: 24, y: 12)
                .scaleEffect(leaves ? 1.08 : (appears ? 1 : 0.9))
                .blur(radius: leaves ? 10 : 0)
                .opacity(leaves ? 0 : (appears ? 1 : 0))
        }
        .contentShape(.rect)
        .onTapGesture { leave() }
        .onKeyPress { _ in
            leave()
            return .ignored
        }
        .task { await play() }
    }

    private func play() async {
        if reduceMotion {
            appears = true
            writing = 1
            try? await Task.sleep(for: .milliseconds(450))
            leave()
            return
        }
        withAnimation(.spring(response: 0.42, dampingFraction: 1)) { appears = true }
        try? await Task.sleep(for: .milliseconds(140))
        withAnimation(.timingCurve(0.45, 0, 0.25, 1, duration: 0.78)) { writing = 1 }
        try? await Task.sleep(for: .milliseconds(1_000))
        leave()
    }

    private func leave() {
        guard !leaves else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.25) : .spring(response: 0.45, dampingFraction: 1)) {
            leaves = true
        }
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 260 : 420))
            finish()
        }
    }
}

private struct WritingLogo: View, @MainActor Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private static let wave: [CGPoint] = [
        CGPoint(x: 0.07, y: 0.64), CGPoint(x: 0.12, y: 0.54), CGPoint(x: 0.18, y: 0.74),
        CGPoint(x: 0.24, y: 0.47), CGPoint(x: 0.29, y: 0.77), CGPoint(x: 0.34, y: 0.55),
        CGPoint(x: 0.39, y: 0.69), CGPoint(x: 0.44, y: 0.59), CGPoint(x: 0.49, y: 0.66),
        CGPoint(x: 0.56, y: 0.64),
    ]

    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width
            let tip = point(at: progress, side: side)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
                    .fill(LinearGradient(colors: [.white, Color(white: 0.955)], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
                    .strokeBorder(.black.opacity(0.06), lineWidth: 1)

                WavePath(points: Self.wave)
                    .trim(from: 0, to: progress)
                    .stroke(Color(hex: 0x2B3550), style: StrokeStyle(lineWidth: side * 0.042, lineCap: .round, lineJoin: .round))

                Pencil()
                    .frame(width: side * 0.14, height: side * 0.6)
                    .rotationEffect(.degrees(40), anchor: .bottom)
                    .offset(x: tip.x - side * 0.07, y: tip.y - side * 0.6)
                    .opacity(min(1, progress * 6))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func point(at fraction: Double, side: CGFloat) -> CGPoint {
        let points = Self.wave.map { CGPoint(x: $0.x * side, y: $0.y * side) }
        let lengths = zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        var remaining = lengths.reduce(0, +) * min(1, max(0, fraction))
        for (index, length) in lengths.enumerated() {
            if remaining <= length {
                let t = length > 0 ? remaining / length : 0
                return CGPoint(
                    x: points[index].x + (points[index + 1].x - points[index].x) * t,
                    y: points[index].y + (points[index + 1].y - points[index].y) * t
                )
            }
            remaining -= length
        }
        return points.last ?? .zero
    }
}

private struct WavePath: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: rect.minX + first.x * rect.width, y: rect.minY + first.y * rect.height))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height))
        }
        return path
    }
}

private struct Pencil: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: w * 0.28)
                    .fill(Color(hex: 0x2B3550))
                    .frame(width: w * 1.08, height: h * 0.12)
                Rectangle()
                    .fill(Color(hex: 0xC9CED8))
                    .frame(width: w, height: h * 0.06)
                    .offset(y: h * 0.1)
                LinearGradient(colors: [Color(hex: 0xF26B55), Color(hex: 0xE83A22)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: w, height: h * 0.56)
                    .offset(y: h * 0.16)
                PencilTip()
                    .fill(Color(hex: 0xEACDA3))
                    .frame(width: w, height: h * 0.22)
                    .offset(y: h * 0.72)
                PencilTip()
                    .fill(Color(hex: 0x2B3550))
                    .frame(width: w * 0.36, height: h * 0.08)
                    .offset(y: h * 0.92)
            }
            .frame(width: w, height: h, alignment: .top)
        }
    }
}

private struct PencilTip: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
