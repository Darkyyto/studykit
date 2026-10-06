import SwiftUI

struct CheckInFlow: View {
    let plan: FocusPlan
    let cancel: () -> Void
    let board: (String) -> Void

    @AppStorage(Preference.name) private var name = ""
    @State private var step = Step.seat
    @State private var seat: Seat?
    @State private var printed = false
    @State private var scanning = false
    @State private var cleared = false

    private let path: TicketRoute
    private let palette = FocusMode.flight.palette

    enum Step {
        case seat, pass, gate
    }

    init(plan: FocusPlan, cancel: @escaping () -> Void, board: @escaping (String) -> Void) {
        self.plan = plan
        self.cancel = cancel
        self.board = board
        let route = FlightRoute.resolve(plan.route)
        path = TicketRoute(origin: route.origin, destination: route.destination)
    }

    private var flightNumber: String {
        "FK \(100 + abs(path.destination.code.unicodeScalars.reduce(0) { $0 * 7 + Int($1.value) }) % 900)"
    }

    private var gate: String {
        let number = abs(flightNumber.hashStable) % 38 + 2
        return "\(["A", "B", "C"][number % 3])\(number)"
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                header
                Group {
                    switch step {
                    case .seat:
                        SeatMap(flight: flightNumber, selection: $seat)
                            .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity)))
                    case .pass, .gate:
                        passStage
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .frame(maxHeight: .infinity)
                footer
            }
            .padding(.horizontal, 44)
            .padding(.top, 76)
            .padding(.bottom, 32)
        }
        .animation(Motion.morph, value: step)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.rounded(34, weight: .bold))
                .displayTracking(34)
                .foregroundStyle(Palette.ink)
                .contentTransition(.interpolate)
            Text(subtitle)
                .font(.rounded(15, weight: .medium))
                .foregroundStyle(Palette.inkSecondary)
                .contentTransition(.interpolate)
        }
        .animation(Motion.standard, value: step)
    }

    private var title: String {
        switch step {
        case .seat: "Choose your seat"
        case .pass: "Your boarding pass"
        case .gate: cleared ? "Welcome aboard" : "Boarding at gate \(gate)"
        }
    }

    private var subtitle: String {
        switch step {
        case .seat: "\(flightNumber) · \(path.origin.city) to \(path.destination.city) · window seats get the window view"
        case .pass: "Printed and ready. Head to the gate when you are."
        case .gate: cleared ? "Find your seat, stow your phone, and focus." : "Scanning your pass…"
        }
    }

    private var passStage: some View {
        VStack(spacing: 22) {
            ZStack(alignment: .top) {
                ZStack(alignment: .top) {
                    BoardingPassCard(
                        name: name.isEmpty ? "Passenger" : name,
                        flight: flightNumber,
                        path: path,
                        seat: seat?.code ?? "",
                        gate: gate,
                        duration: plan.totalFocus,
                        tint: palette.deep
                    )
                    .frame(width: 620)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: .black.opacity(0.1), radius: 18, y: 10)
                    .offset(y: printed ? 20 : -300)
                }
                .frame(width: 700, height: 300, alignment: .top)
                .clipped()
                .padding(.top, 15)

                PrinterSlot()
                    .frame(width: 680, height: 30)
            }

            if step == .gate {
                Scanner(scanning: scanning, cleared: cleared, tint: palette.deep)
                    .frame(width: 320, height: 64)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            withAnimation(.spring(response: 1.1, dampingFraction: 0.86).delay(0.2)) { printed = true }
        }
    }

    private var footer: some View {
        HStack {
            Button(step == .seat ? "Not Now" : "Back") {
                if step == .seat {
                    cancel()
                } else {
                    printed = false
                    withAnimation(Motion.morph) { step = .seat }
                }
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .keyboardShortcut(.cancelAction)
            .disabled(scanning)

            Spacer()

            if let seat, step == .seat {
                Text("Seat \(seat.code) · \(seat.description)")
                    .font(.rounded(14, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .transition(.opacity)
            }

            Spacer()

            Button(action: primary) {
                Text(primaryTitle)
                    .font(.rounded(15, weight: .semibold))
                    .padding(.horizontal, 10)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(palette.deep)
            .keyboardShortcut(.defaultAction)
            .disabled((step == .seat && seat == nil) || scanning)
        }
        .animation(Motion.standard, value: seat)
    }

    private var primaryTitle: String {
        switch step {
        case .seat: "Check In"
        case .pass: "Go to Gate"
        case .gate: "Board"
        }
    }

    private func primary() {
        switch step {
        case .seat:
            printed = false
            withAnimation(Motion.morph) { step = .pass }
        case .pass:
            withAnimation(Motion.morph) { step = .gate }
            scan()
        case .gate:
            scan()
        }
    }

    private func scan() {
        guard !scanning, let seat else { return }
        scanning = true
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(Motion.settle) { cleared = true }
            NSSound(named: "Glass")?.play()
            try? await Task.sleep(for: .seconds(1.1))
            board(seat.code)
        }
    }
}

struct Seat: Hashable {
    let row: Int
    let letter: Character

    var code: String {
        "\(row)\(letter)"
    }

    var isWindow: Bool {
        letter == "A" || letter == "F"
    }

    var isOverWing: Bool {
        (10...17).contains(row)
    }

    var description: String {
        var parts: [String] = []
        parts.append(isWindow ? "Window" : (letter == "C" || letter == "D") ? "Aisle" : "Middle")
        if row <= 3 { parts.append("Business") }
        if row == 12 || row == 13 { parts.append("Extra legroom") }
        if isWindow && isOverWing { parts.append("Wing view") }
        return parts.joined(separator: " · ")
    }
}

private struct SeatMap: View {
    let flight: String
    @Binding var selection: Seat?

    private static let rows = 1...28
    private static let letters: [Character] = ["F", "E", "D", "C", "B", "A"]

    var body: some View {
        VStack(spacing: 18) {
            ScrollView(.horizontal) {
                ZStack(alignment: .leading) {
                    Wing()
                        .fill(LinearGradient(colors: [Color(hex: 0xDCE6F2), Color(hex: 0xC6D3E3)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: 330, height: 470)
                        .offset(x: 540)
                    CabinOutline()
                        .fill(.white.opacity(0.92))
                        .frame(height: 300)
                        .shadow(color: .black.opacity(0.08), radius: 20, y: 8)

                    HStack(alignment: .center, spacing: 6) {
                        ForEach(Self.rows, id: \.self) { row in
                            column(row)
                            if row == 3 || row == 11 || row == 13 {
                                Rectangle()
                                    .fill(.clear)
                                    .frame(width: 10)
                            }
                        }
                    }
                    .padding(.leading, 150)
                    .padding(.trailing, 90)
                }
                .frame(height: 470)
            }
            .scrollIndicators(.never)

            HStack(spacing: 22) {
                legend(Color(hex: 0xC9B8F5), "Business")
                legend(Color(hex: 0x9EE0C0), "Extra legroom")
                legend(FocusMode.flight.palette.mid.opacity(0.75), "Available")
                legend(Palette.ink.opacity(0.08), "Taken")
                legend(Color(hex: 0xDCE6F2), "Wing view")
            }
        }
    }

    private func legend(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: 14, height: 14)
            Text(title)
                .font(.rounded(12, weight: .semibold))
                .foregroundStyle(Palette.inkSecondary)
        }
    }

    private func column(_ row: Int) -> some View {
        let business = row <= 3
        let letters: [Character] = business ? ["F", "D", "C", "A"] : Self.letters
        return VStack(spacing: business ? 10 : 4) {
            ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
                let seat = Seat(row: row, letter: letter)
                SeatButton(
                    seat: seat,
                    isTaken: isTaken(seat),
                    isSelected: selection == seat,
                    isBusiness: business
                ) {
                    withAnimation(Motion.settle) { selection = seat }
                }
                if index == letters.count / 2 - 1 {
                    Text("\(row)")
                        .font(.numeric(10, weight: .semibold))
                        .foregroundStyle(Palette.inkTertiary)
                        .frame(height: 22)
                }
            }
        }
    }

    private func isTaken(_ seat: Seat) -> Bool {
        var generator = SeededGenerator(seed: UInt64(abs((flight + seat.code).hashStable)))
        return Double.random(in: 0...1, using: &generator) < 0.42
    }
}

private struct SeatButton: View {
    let seat: Seat
    let isTaken: Bool
    let isSelected: Bool
    let isBusiness: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(fill)
                RoundedRectangle(cornerRadius: 3)
                    .fill(.black.opacity(isTaken ? 0.05 : 0.08))
                    .frame(width: 5)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.vertical, 4)
                    .padding(.trailing, 3)
                if isSelected {
                    Text(String(seat.letter))
                        .font(.rounded(11, weight: .bold))
                        .foregroundStyle(.white)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: isBusiness ? 38 : 28, height: isBusiness ? 34 : 26)
            .scaleEffect(isSelected ? 1.15 : (isHovering && !isTaken ? 1.08 : 1))
            .shadow(color: isSelected ? FocusMode.flight.palette.deep.opacity(0.45) : .clear, radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(isTaken)
        .onHover { isHovering = $0 }
        .animation(Motion.quick, value: isHovering)
        .help(isTaken ? "Taken" : "\(seat.code) · \(seat.description)")
    }

    private var fill: Color {
        if isSelected { return FocusMode.flight.palette.deep }
        if isTaken { return Palette.ink.opacity(0.08) }
        if isBusiness { return Color(hex: 0xC9B8F5) }
        if seat.row == 12 || seat.row == 13 { return Color(hex: 0x9EE0C0) }
        return FocusMode.flight.palette.mid.opacity(0.75)
    }
}

private struct CabinOutline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let nose = rect.height * 0.9
        path.move(to: CGPoint(x: rect.minX + nose, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - 60, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - 60, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + nose, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.minX + nose, y: rect.minY),
            control1: CGPoint(x: rect.minX - nose * 0.1, y: rect.maxY),
            control2: CGPoint(x: rect.minX - nose * 0.1, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

private struct Wing: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY - rect.height * 0.3))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.8, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY - rect.height * 0.3))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY + rect.height * 0.3))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.8, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.3))
        path.closeSubpath()
        return path
    }
}

private struct PrinterSlot: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(LinearGradient(colors: [Color(hex: 0x3A4250), Color(hex: 0x1D222B)], startPoint: .top, endPoint: .bottom))
            Capsule()
                .fill(.black.opacity(0.6))
                .frame(height: 6)
                .padding(.horizontal, 24)
        }
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
    }
}

private struct Scanner: View {
    let scanning: Bool
    let cleared: Bool
    let tint: Color
    @State private var sweep = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(LinearGradient(colors: [Color(hex: 0x2A303B), Color(hex: 0x161A21)], startPoint: .top, endPoint: .bottom))
            if cleared {
                Label("Cleared", systemImage: "checkmark.circle.fill")
                    .font(.rounded(17, weight: .bold))
                    .foregroundStyle(Color(hex: 0x5BE38F))
                    .transition(.scale.combined(with: .opacity))
            } else {
                Capsule()
                    .fill(Color(hex: 0xFF4D4D))
                    .frame(width: 260, height: 3)
                    .shadow(color: Color(hex: 0xFF4D4D), radius: 6)
                    .offset(y: sweep ? 18 : -18)
                    .opacity(scanning ? 1 : 0.35)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(cleared ? Color(hex: 0x5BE38F) : .white.opacity(0.1), lineWidth: 2)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { sweep = true }
        }
        .animation(Motion.settle, value: cleared)
    }
}

extension String {
    var hashStable: Int {
        unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) } & 0x7FFFFFFF
    }
}

struct TicketRoute {
    let origin: Airport
    let destination: Airport
}
