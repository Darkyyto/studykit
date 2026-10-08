import SwiftUI

struct BoardingPassCard: View {
    let name: String
    let flight: String
    let path: TicketRoute
    let seat: String
    let gate: String
    let duration: TimeInterval
    let tint: Color

    private let stubWidth: CGFloat = 170

    var body: some View {
        HStack(spacing: 0) {
            main
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            stub
                .padding(22)
                .frame(width: stubWidth, alignment: .leading)
        }
        .background {
            TicketShape(stubWidth: stubWidth)
                .fill(Palette.surface)
        }
        .overlay(alignment: .top) {
            TicketShape(stubWidth: stubWidth)
                .fill(tint)
                .frame(height: 8)
                .mask(alignment: .top) { Rectangle().frame(height: 8) }
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(.clear)
                .frame(width: 1)
                .overlay {
                    Line()
                        .stroke(Palette.inkTertiary.opacity(0.6), style: StrokeStyle(lineWidth: 1.2, dash: [3, 5]))
                }
                .padding(.vertical, 18)
                .padding(.trailing, stubWidth)
        }
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("FocusKit Air", systemImage: "airplane")
                    .font(.rounded(13, weight: .bold))
                    .foregroundStyle(tint)
                Spacer()
                Text("BOARDING PASS")
                    .font(.rounded(11, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(Palette.inkTertiary)
            }

            HStack(alignment: .center) {
                endpoint(path.origin.code, path.origin.city, alignment: .leading)
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: "airplane")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(duration.compactDuration)
                        .font(.rounded(11, weight: .semibold))
                        .foregroundStyle(Palette.inkSecondary)
                }
                Spacer()
                endpoint(path.destination.code, path.destination.city, alignment: .trailing)
            }

            HStack(spacing: 26) {
                field("Passenger", name)
                field("Flight", flight)
                field("Gate", gate)
                field("Boards", Date.now.formatted(date: .omitted, time: .shortened))
            }
        }
    }

    private var stub: some View {
        VStack(alignment: .leading, spacing: 12) {
            field("Seat", seat, size: 30, tint: tint)
            field("Zone", "\(1 + abs(seat.hashStable) % 4)")
            Spacer(minLength: 0)
            Barcode(seed: flight + seat)
                .fill(Palette.ink)
                .frame(height: 38)
        }
    }

    private func endpoint(_ code: String, _ city: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(code)
                .font(.rounded(44, weight: .heavy))
                .displayTracking(44)
                .foregroundStyle(Palette.ink)
            Text(city)
                .font(.rounded(14, weight: .medium))
                .foregroundStyle(Palette.inkSecondary)
        }
    }

    private func field(_ label: String, _ value: String, size: CGFloat = 16, tint: Color = Palette.ink) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.rounded(10, weight: .bold))
                .tracking(1)
                .foregroundStyle(Palette.inkTertiary)
            Text(value)
                .font(.rounded(size, weight: .bold))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
    }
}

private struct TicketShape: Shape {
    let stubWidth: CGFloat
    private let radius: CGFloat = 22
    private let notch: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        let cut = rect.maxX - stubWidth
        var path = Path(roundedRect: rect, cornerRadius: radius)
        path.addEllipse(in: CGRect(x: cut - notch, y: rect.minY - notch, width: notch * 2, height: notch * 2))
        path.addEllipse(in: CGRect(x: cut - notch, y: rect.maxY - notch, width: notch * 2, height: notch * 2))
        return path.subtracting(Path(ellipseIn: CGRect(x: cut - notch, y: rect.minY - notch, width: notch * 2, height: notch * 2)))
            .subtracting(Path(ellipseIn: CGRect(x: cut - notch, y: rect.maxY - notch, width: notch * 2, height: notch * 2)))
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
    }
}

private struct Barcode: Shape {
    let seed: String

    func path(in rect: CGRect) -> Path {
        var generator = SeededGenerator(seed: UInt64(seed.hashStable))
        var path = Path()
        var x = rect.minX
        while x < rect.maxX {
            let width = CGFloat(Int.random(in: 1...3, using: &generator))
            if Bool.random(using: &generator) {
                path.addRect(CGRect(x: x, y: rect.minY, width: min(width, rect.maxX - x), height: rect.height))
            }
            x += width + 1
        }
        return path
    }
}
