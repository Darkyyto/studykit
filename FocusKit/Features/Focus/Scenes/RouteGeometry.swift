import SwiftUI

struct RouteGeometry {
    let start: CGPoint
    let end: CGPoint
    let control: CGPoint
    let samples: [CGPoint]
    let scale: CGFloat
    let center: CGPoint
    let anchor: CGPoint
    private let cumulative: [CGFloat]
    private let parallelScale: CGFloat

    init(from origin: Airport, to destination: Airport, in rect: CGRect) {
        var destinationLongitude = destination.longitude
        if destinationLongitude - origin.longitude > 180 { destinationLongitude -= 360 }
        if destinationLongitude - origin.longitude < -180 { destinationLongitude += 360 }

        let meanLatitude = (origin.latitude + destination.latitude) / 2
        parallelScale = CGFloat(max(0.2, cos(meanLatitude * .pi / 180)))

        let a = CGPoint(x: origin.longitude * parallelScale, y: -origin.latitude)
        let b = CGPoint(x: destinationLongitude * parallelScale, y: -destination.latitude)
        let span = max(abs(b.x - a.x), abs(b.y - a.y), 0.6)
        let width = max(abs(b.x - a.x), span * 0.45)
        let height = max(abs(b.y - a.y), span * 0.45)

        scale = min(rect.width / width, rect.height / height) * 0.82
        center = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        anchor = CGPoint(x: rect.midX, y: rect.midY)

        let project: (CGPoint) -> CGPoint = { [scale, center, anchor] point in
            CGPoint(
                x: anchor.x + (point.x - center.x) * scale,
                y: anchor.y + (point.y - center.y) * scale
            )
        }

        let start = project(a)
        let end = project(b)
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(hypot(dx, dy), 1)
        var normal = CGPoint(x: -dy / length, y: dx / length)
        if normal.y > 0 { normal = CGPoint(x: -normal.x, y: -normal.y) }
        let control = CGPoint(x: mid.x + normal.x * length * 0.16, y: mid.y + normal.y * length * 0.16)

        let count = 120
        let samples = (0...count).map { index in
            Self.bezier(start, control, end, CGFloat(index) / CGFloat(count))
        }
        var running: CGFloat = 0
        var cumulative: [CGFloat] = [0]
        for index in 1..<samples.count {
            running += hypot(samples[index].x - samples[index - 1].x, samples[index].y - samples[index - 1].y)
            cumulative.append(running)
        }
        self.start = start
        self.end = end
        self.control = control
        self.samples = samples
        self.cumulative = cumulative
    }

    var length: CGFloat {
        cumulative.last ?? 0
    }

    func position(at progress: Double) -> (point: CGPoint, heading: Angle) {
        let target = CGFloat(min(1, max(0, progress))) * length
        let index = cumulative.firstIndex { $0 >= target } ?? samples.count - 1
        guard index > 0 else {
            return (samples[0], heading(from: samples[0], to: samples[1]))
        }
        let previous = samples[index - 1]
        let next = samples[index]
        let segment = cumulative[index] - cumulative[index - 1]
        let fraction = segment > 0 ? (target - cumulative[index - 1]) / segment : 0
        let point = CGPoint(x: previous.x + (next.x - previous.x) * fraction, y: previous.y + (next.y - previous.y) * fraction)
        return (point, heading(from: previous, to: next))
    }

    func path(through progress: Double = 1) -> CGPath {
        let path = CGMutablePath()
        path.move(to: samples[0])
        let target = CGFloat(min(1, max(0, progress))) * length
        for index in 1..<samples.count where cumulative[index] <= target {
            path.addLine(to: samples[index])
        }
        path.addLine(to: position(at: progress).point)
        return path
    }

    func screen(latitude: Double, longitude: Double) -> CGPoint {
        CGPoint(
            x: anchor.x + (CGFloat(longitude) * parallelScale - center.x) * scale,
            y: anchor.y + (CGFloat(-latitude) - center.y) * scale
        )
    }

    func coordinate(at point: CGPoint) -> (latitude: Double, longitude: Double) {
        let x = (point.x - anchor.x) / scale + center.x
        let y = (point.y - anchor.y) / scale + center.y
        return (Double(-y), Double(x / parallelScale))
    }

    private func heading(from a: CGPoint, to b: CGPoint) -> Angle {
        .radians(atan2(b.y - a.y, b.x - a.x))
    }

    private static func bezier(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u * u * p0.x + 2 * u * t * p1.x + t * t * p2.x,
            y: u * u * p0.y + 2 * u * t * p1.y + t * t * p2.y
        )
    }
}
