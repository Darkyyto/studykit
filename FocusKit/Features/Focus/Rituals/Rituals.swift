import SwiftUI

struct RitualScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    let tint: Color
    let primaryTitle: String
    let isBusy: Bool
    let cancel: () -> Void
    let primary: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 26) {
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
                content
                    .frame(maxHeight: .infinity)
                HStack {
                    Button("Not Now", action: cancel)
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                        .keyboardShortcut(.cancelAction)
                        .disabled(isBusy)
                    Spacer()
                    Button(action: primary) {
                        Text(primaryTitle)
                            .font(.rounded(15, weight: .semibold))
                            .padding(.horizontal, 10)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .tint(tint)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isBusy)
                }
            }
            .padding(.horizontal, 44)
            .padding(.top, 76)
            .padding(.bottom, 32)
        }
    }
}

struct ChoiceCard<Preview: View>: View {
    let title: String
    let detail: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder var preview: Preview

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                preview
                    .frame(height: 120)
                    .clipShape(.rect(cornerRadius: 18))
                    .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.rounded(15, weight: .bold))
                        .foregroundStyle(Palette.ink)
                    Text(detail)
                        .font(.rounded(12, weight: .medium))
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 4)
            }
            .padding(8)
            .frame(width: 200)
            .contentShape(.rect(cornerRadius: 24))
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .glassEffect(isSelected ? .regular.tint(tint.opacity(0.2)).interactive() : .regular.interactive(), in: .rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(tint.opacity(isSelected ? 0.65 : 0), lineWidth: 2)
        }
        .scaleEffect(isSelected ? 1.03 : 1)
        .animation(Motion.settle, value: isSelected)
    }
}

struct MissionBriefing: View {
    let plan: FocusPlan
    let cancel: () -> Void
    let begin: (FocusPlan) -> Void
    @AppStorage("variant.orbit") private var stored = OrbitBody.neptune.rawValue
    @State private var countdown: Int?
    @State private var liftoff = false

    private var body_: OrbitBody {
        OrbitBody.resolve(stored)
    }

    var body: some View {
        RitualScaffold(
            title: countdown == nil ? "Mission briefing" : "Launch",
            subtitle: countdown == nil ? "Pick where this orbit takes you. \(plan.totalFocus.compactDuration) of deep work." : "Destination \(body_.title). Systems nominal.",
            tint: body_.palette.deep,
            primaryTitle: "Launch",
            isBusy: countdown != nil,
            cancel: cancel,
            primary: launch
        ) {
            if let countdown {
                ZStack {
                    Rocket(liftoff: liftoff, tint: body_.palette.deep)
                        .frame(width: 120, height: 260)
                    if countdown > 0 {
                        Text("\(countdown)")
                            .font(.numeric(120, weight: .heavy))
                            .foregroundStyle(Palette.ink)
                            .id(countdown)
                            .transition(.asymmetric(insertion: .scale(scale: 1.6).combined(with: .opacity), removal: .scale(scale: 0.6).combined(with: .opacity)))
                            .offset(x: 200)
                    }
                }
                .transition(.opacity)
            } else {
                HStack(spacing: 14) {
                    ForEach(OrbitBody.allCases) { item in
                        ChoiceCard(title: item.title, detail: item.detail, tint: item.palette.deep, isSelected: item == body_) {
                            stored = item.rawValue
                        } preview: {
                            OrbitScene(state: SceneState(progress: 0.4, time: 12, isPaused: false, stage: CGRect(x: 10, y: 10, width: 184, height: 100)), palette: item.palette, planet: item)
                                .background(item.palette.light)
                        }
                    }
                }
            }
        }
        .animation(Motion.morph, value: countdown)
    }

    private func launch() {
        Task {
            for value in [3, 2, 1, 0] {
                withAnimation(Motion.settle) { countdown = value }
                if value == 0 {
                    withAnimation(.easeIn(duration: 1.3)) { liftoff = true }
                    try? await Task.sleep(for: .seconds(1.3))
                } else {
                    try? await Task.sleep(for: .seconds(0.8))
                }
            }
            var plan = plan
            plan.variant = stored
            begin(plan)
        }
    }
}

private struct Rocket: View {
    let liftoff: Bool
    let tint: Color
    @State private var flicker = false

    var body: some View {
        VStack(spacing: -4) {
            ZStack {
                Capsule()
                    .fill(LinearGradient(colors: [.white, Color(hex: 0xDDE2EA)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 46, height: 140)
                Circle()
                    .fill(tint)
                    .frame(width: 20, height: 20)
                    .overlay(Circle().stroke(.white, lineWidth: 3))
                    .offset(y: -20)
                HStack(spacing: 44) {
                    Fin().fill(tint).frame(width: 22, height: 40).scaleEffect(x: -1)
                    Fin().fill(tint).frame(width: 22, height: 40)
                }
                .offset(y: 48)
            }
            Flame()
                .fill(LinearGradient(colors: [Color(hex: 0xFFE07A), Color(hex: 0xFF7A3D), .clear], startPoint: .top, endPoint: .bottom))
                .frame(width: 30, height: liftoff ? 90 : 34)
                .scaleEffect(x: flicker ? 0.85 : 1.1, y: flicker ? 0.9 : 1.05, anchor: .top)
        }
        .offset(y: liftoff ? -700 : 0)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.08).repeatForever(autoreverses: true)) { flicker = true }
        }
    }

    private struct Fin: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY * 0.8))
                path.closeSubpath()
            }
        }
    }

    private struct Flame: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: rect.minX, y: rect.maxY * 0.6))
                path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX, y: rect.maxY * 0.6))
                path.closeSubpath()
            }
        }
    }
}

struct SeedPicker: View {
    let plan: FocusPlan
    let cancel: () -> Void
    let begin: (FocusPlan) -> Void
    @AppStorage("variant.bloom") private var stored = FlowerKind.daisy.rawValue
    @State private var planting = false
    @State private var seedLanded = false
    @State private var watered = false

    private var flower: FlowerKind {
        FlowerKind.resolve(stored)
    }

    var body: some View {
        RitualScaffold(
            title: planting ? "Planting" : "Choose a seed",
            subtitle: planting ? "Water it with \(plan.totalFocus.compactDuration) of focus." : "It grows while you work and blooms when you finish.",
            tint: FocusMode.bloom.palette.deep,
            primaryTitle: "Plant",
            isBusy: planting,
            cancel: cancel,
            primary: plant
        ) {
            if planting {
                ZStack(alignment: .bottom) {
                    Ellipse()
                        .fill(LinearGradient(colors: [Color(hex: 0x9B6B43), Color(hex: 0x6E4A2C)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 280, height: 70)
                    Circle()
                        .fill(Color(hex: 0x5A3A1E))
                        .frame(width: 16, height: 16)
                        .offset(y: seedLanded ? -40 : -340)
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(FocusMode.tide.palette.mid)
                            .frame(width: 8, height: 16)
                            .offset(x: CGFloat(index - 1) * 26, y: watered ? -45 : -300)
                            .opacity(watered ? 0 : 1)
                            .animation(.easeIn(duration: 0.6).delay(Double(index) * 0.12), value: watered)
                    }
                    Capsule()
                        .fill(FocusMode.bloom.palette.deep)
                        .frame(width: 6, height: watered ? 46 : 0)
                        .offset(y: -50)
                        .animation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.8), value: watered)
                }
                .frame(height: 360)
                .transition(.opacity)
            } else {
                HStack(spacing: 14) {
                    ForEach(FlowerKind.allCases) { item in
                        ChoiceCard(title: item.title, detail: item.detail, tint: item.petal, isSelected: item == flower) {
                            stored = item.rawValue
                        } preview: {
                            BloomScene(state: SceneState(progress: 1, time: 12, isPaused: true, stage: CGRect(x: 10, y: 8, width: 184, height: 104)), palette: FocusMode.bloom.palette, flower: item)
                                .background(FocusMode.bloom.palette.light)
                        }
                    }
                }
            }
        }
        .animation(Motion.morph, value: planting)
    }

    private func plant() {
        Task {
            withAnimation(Motion.morph) { planting = true }
            try? await Task.sleep(for: .seconds(0.3))
            withAnimation(.spring(response: 0.7, dampingFraction: 0.55)) { seedLanded = true }
            try? await Task.sleep(for: .seconds(0.8))
            watered = true
            try? await Task.sleep(for: .seconds(1.6))
            var plan = plan
            plan.variant = stored
            begin(plan)
        }
    }
}

struct HarborDeparture: View {
    let plan: FocusPlan
    let cancel: () -> Void
    let begin: (FocusPlan) -> Void
    @AppStorage("variant.tide") private var stored = TideVariant(boat: .sailboat, sky: .day).rawValue
    @State private var departing = false

    private var variant: TideVariant {
        TideVariant.resolve(stored)
    }

    var body: some View {
        RitualScaffold(
            title: departing ? "Casting off" : "Choose your boat",
            subtitle: departing ? "The tide rises as you read." : "Pick a boat and the light you want to sail in.",
            tint: variant.sky.water.deep,
            primaryTitle: "Set Sail",
            isBusy: departing,
            cancel: cancel,
            primary: depart
        ) {
            VStack(spacing: 20) {
                HStack(spacing: 14) {
                    ForEach(BoatKind.allCases) { boat in
                        let option = TideVariant(boat: boat, sky: variant.sky)
                        ChoiceCard(title: boat.title, detail: variant.sky.title, tint: variant.sky.water.deep, isSelected: boat == variant.boat) {
                            stored = option.rawValue
                        } preview: {
                            TideScene(state: SceneState(progress: departing ? 0.55 : 0.35, time: departing ? 30 : 12, isPaused: false, stage: CGRect(x: 10, y: 8, width: 184, height: 104)), palette: option.sky.water, variant: option)
                                .background(option.sky.water.light)
                        }
                    }
                }
                GlassSegmented(options: SkyKind.allCases, selection: Binding(
                    get: { variant.sky },
                    set: { stored = TideVariant(boat: variant.boat, sky: $0).rawValue }
                ), tint: variant.sky.water.deep) { $0.title }
            }
            .offset(x: departing ? 900 : 0)
            .opacity(departing ? 0 : 1)
        }
        .animation(.easeIn(duration: 1.2), value: departing)
    }

    private func depart() {
        Task {
            departing = true
            try? await Task.sleep(for: .seconds(1.25))
            var plan = plan
            plan.variant = stored
            begin(plan)
        }
    }
}
