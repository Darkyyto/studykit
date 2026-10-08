import MapKit
import SwiftUI

enum FlightMapStyle: String, CaseIterable, Identifiable {
    case map
    case satellite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .map: "Map"
        case .satellite: "Satellite"
        }
    }
}

struct FlightMapScene: View {
    let origin: Airport
    let destination: Airport
    let progressAt: (Date) -> Double
    let isPaused: Bool
    let isArrived: Bool
    let tick: Date

    private var progress: Double {
        progressAt(tick)
    }

    @AppStorage("flightMapStyle") private var style = FlightMapStyle.map
    @Environment(\.chromeInset) private var chromeInset
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.isOnScreen) private var isOnScreen
    @State private var position: MapCameraPosition = .automatic
    @State private var follows = false
    @State private var cruiseTrigger = 0

    private let palette = FocusMode.flight.palette

    private var route: [CLLocationCoordinate2D] {
        origin.path(towards: destination)
    }

    private var plane: CLLocationCoordinate2D {
        origin.coordinate(towards: destination, fraction: progress)
    }

    private var heading: Double {
        origin.heading(towards: destination, fraction: progress)
    }

    private var routeKilometers: Double {
        origin.distance(to: destination)
    }

    var body: some View {
        ZStack(alignment: .top) {
            map
                .safeAreaPadding(.bottom, 250)
            BottomFade(start: 0.48)
            VStack(spacing: 0) {
                ZStack {
                    if follows {
                        Cruise(tint: palette.deep, isPaused: isPaused || isArrived)
                            .allowsHitTesting(false)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Color.clear
                    .frame(height: 250)
            }

            HStack(alignment: .center) {
                RouteChip(origin: origin, destination: destination, kilometersLeft: routeKilometers * (1 - progress), isArrived: isArrived)
                Spacer()
                styleButton
            }
            .padding(.top, chromeInset)
            .padding(.horizontal, 20)
        }
        .onAppear(perform: introduce)
        .onChange(of: isPaused) { cruiseTrigger += 1 }
        .onChange(of: isOnScreen) { cruiseTrigger += 1 }
        .onChange(of: isArrived) { _, arrived in
            cruiseTrigger += 1
            if arrived { overview(animated: true) }
        }
    }

    private var styleButton: some View {
            Button {
                withAnimation(Motion.standard) { style = style == .map ? .satellite : .map }
            } label: {
                Image(systemName: style == .map ? "globe.europe.africa.fill" : "map.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 40, height: 40)
                    .contentShape(.circle)
            }
            .buttonStyle(.pressable)
            .glassEffect(.regular.interactive(), in: .circle)
            .help(style == .map ? "Satellite view" : "Map view")
    }

    private var map: some View {
        Map(position: $position, interactionModes: []) {
            MapPolyline(coordinates: route)
                .stroke(palette.deep.opacity(0.35), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 8]))
            MapPolyline(coordinates: origin.path(towards: destination, through: max(0.001, progress)))
                .stroke(palette.deep, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

            Annotation(origin.city, coordinate: origin.coordinate, anchor: .center) {
                CityPin(code: origin.code, city: origin.city, isDestination: false)
            }
            .annotationTitles(.hidden)
            Annotation(destination.city, coordinate: destination.coordinate, anchor: .center) {
                CityPin(code: destination.code, city: destination.city, isDestination: true)
            }
            .annotationTitles(.hidden)

            if !follows {
                Annotation("", coordinate: plane) {
                    Airliner(tint: palette.deep, altitude: 0.5)
                        .frame(width: 34, height: 34)
                        .rotationEffect(.degrees(heading))
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(style == .map
            ? .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll)
            : .imagery(elevation: .flat))
        .mapControlVisibility(.hidden)
        .mapCameraKeyframeAnimator(trigger: cruiseTrigger) { _ in
            let steps = cruiseSteps()
            KeyframeTrack(\MapCamera.centerCoordinate) {
                for step in steps {
                    LinearKeyframe(step.camera.centerCoordinate, duration: step.duration)
                }
            }
            KeyframeTrack(\MapCamera.heading) {
                for step in steps {
                    LinearKeyframe(step.camera.heading, duration: step.duration)
                }
            }
            KeyframeTrack(\MapCamera.distance) {
                for step in steps {
                    LinearKeyframe(step.camera.distance, duration: step.duration)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var followCamera: MapCamera {
        camera(at: tick)
    }

    private func camera(at date: Date, zoom: Double = 1) -> MapCamera {
        let fraction = min(1, max(0, progressAt(date)))
        let distance = min(900_000, max(30_000, routeKilometers * 1000 * 0.38)) * zoom
        return MapCamera(
            centerCoordinate: origin.coordinate(towards: destination, fraction: fraction),
            distance: distance,
            heading: origin.heading(towards: destination, fraction: fraction),
            pitch: 0
        )
    }

    private func introduce() {
        guard !isArrived else {
            overview(animated: false)
            return
        }
        follows = true
        guard !reduceMotion else {
            position = .camera(camera(at: .now))
            return
        }
        position = .camera(camera(at: .now, zoom: 3))
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeInOut(duration: 2.6)) {
                position = .camera(camera(at: .now.addingTimeInterval(2.6)))
            }
            try? await Task.sleep(for: .seconds(2.7))
            cruiseTrigger += 1
        }
    }

    private func cruiseSteps() -> [(camera: MapCamera, duration: Double)] {
        let now = Date.now
        let start = (camera: camera(at: now), duration: 0.35)
        guard follows, !isArrived, !isPaused, isOnScreen, !reduceMotion else { return [start] }
        var steps = [start]
        var date = now
        for _ in 0..<720 {
            date = date.addingTimeInterval(30)
            steps.append((camera(at: date), 30))
            if progressAt(date) >= 1 { break }
        }
        return steps
    }

    private func overview(animated: Bool) {
        let rect = route.reduce(MKMapRect.null) { rect, coordinate in
            rect.union(MKMapRect(origin: MKMapPoint(coordinate), size: MKMapSize(width: 1, height: 1)))
        }
        let padded = rect.insetBy(dx: -rect.width * 0.35 - 20_000, dy: -rect.height * 0.6 - 20_000)
        follows = false
        withAnimation(animated ? .easeInOut(duration: 2.4) : nil) {
            position = .rect(padded)
        }
    }
}

private struct Cruise: View {
    let tint: Color
    let isPaused: Bool

    var body: some View {
        ZStack {
            Contrails()
                .frame(width: 84, height: 150)
                .offset(y: 92)
            Airliner(tint: tint, altitude: 1)
                .frame(width: 84, height: 84)
        }
    }
}

private struct Contrails: View {
    var body: some View {
        Canvas { context, size in
            for x in [size.width * 0.3, size.width * 0.7] {
                let gradient = Gradient(stops: [
                    .init(color: .white.opacity(0), location: 0),
                    .init(color: .white.opacity(0.55), location: 0.08),
                    .init(color: .white.opacity(0.15), location: 0.45),
                    .init(color: .white.opacity(0), location: 1),
                ])
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(
                    path,
                    with: .linearGradient(
                        gradient,
                        startPoint: .zero,
                        endPoint: CGPoint(x: 0, y: size.height)
                    ),
                    style: StrokeStyle(lineWidth: 1.75, lineCap: .round)
                )
            }
        }
        .shadow(color: .black.opacity(0.12), radius: 2)
    }
}

private struct Airliner: View {
    let tint: Color
    let altitude: Double

    var body: some View {
        ZStack {
            AirlinerShape()
                .fill(.black.opacity(0.16))
                .blur(radius: 1.5 + altitude * 2.5)
                .offset(x: 4 + altitude * 10, y: 6 + altitude * 16)
                .scaleEffect(0.94)
            AirlinerShape()
                .fill(LinearGradient(colors: [.white, Color(white: 0.9)], startPoint: .leading, endPoint: .trailing))
            AirlinerShape()
                .stroke(Palette.ink.opacity(0.18), lineWidth: 0.75)
            AirlinerEngines()
                .fill(tint)
            AirlinerTail()
                .fill(tint)
        }
    }
}

private struct AirlinerShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: rect.minX + x * w, y: rect.minY + y * h) }
        var path = Path()
        path.move(to: p(0.5, 0.0))
        path.addQuadCurve(to: p(0.56, 0.11), control: p(0.56, 0.02))
        path.addLine(to: p(0.56, 0.36))
        path.addLine(to: p(0.98, 0.58))
        path.addLine(to: p(0.98, 0.63))
        path.addLine(to: p(0.56, 0.555))
        path.addLine(to: p(0.545, 0.84))
        path.addLine(to: p(0.76, 0.93))
        path.addLine(to: p(0.76, 0.975))
        path.addLine(to: p(0.515, 0.955))
        path.addQuadCurve(to: p(0.485, 0.955), control: p(0.5, 1.0))
        path.addLine(to: p(0.24, 0.975))
        path.addLine(to: p(0.24, 0.93))
        path.addLine(to: p(0.455, 0.84))
        path.addLine(to: p(0.44, 0.555))
        path.addLine(to: p(0.02, 0.63))
        path.addLine(to: p(0.02, 0.58))
        path.addLine(to: p(0.44, 0.36))
        path.addLine(to: p(0.44, 0.11))
        path.addQuadCurve(to: p(0.5, 0.0), control: p(0.44, 0.02))
        path.closeSubpath()
        return path
    }
}

private struct AirlinerEngines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for x in [0.3, 0.7] {
            path.addRoundedRect(
                in: CGRect(x: rect.minX + (x - 0.035) * rect.width, y: rect.minY + 0.42 * rect.height, width: 0.07 * rect.width, height: 0.12 * rect.height),
                cornerSize: CGSize(width: 0.035 * rect.width, height: 0.035 * rect.width)
            )
        }
        return path
    }
}

private struct AirlinerTail: Shape {
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: CGRect(x: rect.minX + 0.488 * rect.width, y: rect.minY + 0.8 * rect.height, width: 0.024 * rect.width, height: 0.17 * rect.height), cornerRadius: 0.012 * rect.width)
    }
}

private struct RouteChip: View {
    let origin: Airport
    let destination: Airport
    let kilometersLeft: Double
    let isArrived: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: "\(origin.code)")
            Image(systemName: "airplane")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(FocusMode.flight.palette.deep)
            Text(verbatim: "\(destination.code)")
            Text(isArrived ? "Arrived" : "\(Int(kilometersLeft.rounded())) km to go")
                .foregroundStyle(Palette.inkSecondary)
                .contentTransition(.numericText(countsDown: true))
        }
        .font(.rounded(13, weight: .semibold))
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 16)
        .frame(height: 40)
        .glassEffect(.regular, in: .capsule)
        .animation(Motion.standard, value: Int(kilometersLeft))
    }
}

private struct CityPin: View {
    let code: String
    let city: String
    let isDestination: Bool

    var body: some View {
        Circle()
            .fill(isDestination ? FocusMode.flight.palette.deep : Palette.ink)
            .frame(width: 10, height: 10)
            .overlay(Circle().stroke(Palette.surface, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            .overlay(alignment: .top) {
                if isDestination {
                    HStack(spacing: 5) {
                        Text(code)
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(Palette.ink)
                        Text(city)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(.regularMaterial, in: .capsule)
                    .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                    .offset(y: 16)
                }
            }
    }
}
