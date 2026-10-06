import SwiftUI

struct FocusSetup: View {
    @Environment(FocusEngine.self) private var engine
    @Environment(Library.self) private var library
    @AppStorage(Preference.focusMode) private var mode = FocusMode.flight
    @AppStorage(Preference.persona) private var persona = Persona.personal
    @AppStorage(Preference.name) private var name = ""
    @AppStorage(Preference.homeAirport) private var homeCode = Airport.fallback.code
    @AppStorage("rounds") private var rounds = 1
    @AppStorage("breakMinutes") private var breakMinutes = 5
    @AppStorage("destination") private var destinationCode = ""
    @AppStorage("sessionKind") private var kindValue = ""
    @AppStorage("skipsRituals") private var skipsRituals = false
    @State private var minutes = 45
    @State private var intention = ""
    @State private var goalID: Goal.ID?
    @State private var tasks: [SessionTask] = []
    @State private var documentID: StudyDocument.ID?
    @State private var ritual: FocusPlan?
    @State private var showsOptions = false
    @State private var importsDocument = false
    @State private var isDropTarget = false
    @FocusState private var intentionFocused: Bool

    private var origin: Airport {
        Airport.named(homeCode) ?? .fallback
    }

    private var destination: Airport {
        Airport.named(destinationCode).flatMap { $0 == origin ? nil : $0 }
            ?? origin.routes(closestTo: TimeInterval(minutes * 60))[0]
    }

    private var kinds: [SessionKind] {
        SessionKind.options(for: persona)
    }

    private var kind: SessionKind {
        SessionKind(rawValue: kindValue).flatMap { kinds.contains($0) ? $0 : nil } ?? kinds[0]
    }

    private var document: StudyDocument? {
        library.documents.first { $0.id == documentID }
    }

    private var plan: FocusPlan {
        FocusPlan(
            mode: mode,
            intention: intention.trimmingCharacters(in: .whitespacesAndNewlines),
            goalID: goalID,
            focusDuration: TimeInterval(minutes * 60),
            rounds: rounds,
            breakDuration: rounds > 1 ? TimeInterval(breakMinutes * 60) : 0,
            route: mode == .flight ? Session.Route(origin: origin.code, destination: destination.code) : nil,
            kind: kind,
            tasks: kind.plansTasks ? tasks : [],
            documentID: document?.id
        )
    }

    var body: some View {
        ZStack {
            setup
                .blur(radius: ritual == nil ? 0 : 18)
                .allowsHitTesting(ritual == nil)
            if let ritual {
                RitualHost(plan: ritual) {
                    withAnimation(Motion.morph) { self.ritual = nil }
                } begin: { plan in
                    engine.start(plan)
                    self.ritual = nil
                }
                .transition(.opacity.combined(with: .scale(scale: 1.04)))
                .zIndex(1)
            }
        }
        .animation(Motion.morph, value: ritual != nil)
        .fileImporter(isPresented: $importsDocument, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result, let document = PDFImport.open(url, into: library) {
                withAnimation(Motion.standard) { documentID = document.id }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let document = urls.lazy.compactMap({ PDFImport.open($0, into: library) }).first else { return false }
            withAnimation(Motion.standard) { documentID = document.id }
            return true
        } isTargeted: { targeted in
            withAnimation(Motion.quick) { isDropTarget = targeted }
        }
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 32)
                    .strokeBorder(mode.palette.deep, style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
                    .background(mode.palette.light.opacity(0.4), in: .rect(cornerRadius: 32))
                    .overlay {
                        Label("Drop a PDF to study it", systemImage: "doc.badge.plus")
                            .font(.rounded(20, weight: .bold))
                            .foregroundStyle(mode.palette.deep)
                    }
                    .padding(24)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .onChange(of: library.pendingDocumentID, initial: true) { _, pending in
            guard let pending else { return }
            withAnimation(Motion.standard) { documentID = pending }
            library.pendingDocumentID = nil
        }
        .background {
            Button("") { importsDocument = true }
                .keyboardShortcut("o", modifiers: .command)
                .hidden()
        }
    }

    private var setup: some View {
        ZStack(alignment: .bottom) {
            FocusScene(
                mode: mode,
                progress: { _ in 0.6 },
                route: plan.route,
                insets: EdgeInsets(top: 46, leading: 140, bottom: 18, trailing: 140)
            )
            .frame(height: 180)
            .mask(LinearGradient(colors: [.clear, .black, .black], startPoint: .top, endPoint: .bottom))
            .opacity(0.9)
            .allowsHitTesting(false)
            .id(mode)
            .transition(.opacity)

            GeometryReader { proxy in
                ScrollView {
                    controls
                        .frame(maxWidth: 640)
                        .padding(.top, 72)
                        .padding(.bottom, 150)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollIndicators(.never)
                .scrollBounceBehavior(.basedOnSize)
            }

            if showsOptions {
                Rectangle()
                    .fill(Palette.canvas.opacity(0.55))
                    .ignoresSafeArea()
                    .onTapGesture { closeOptions() }
                    .transition(.opacity)

                CustomizeCard(
                    kinds: kinds,
                    kind: Binding(get: { kind }, set: { select($0) }),
                    rounds: $rounds,
                    breakMinutes: $breakMinutes,
                    goalID: $goalID,
                    documentID: $documentID,
                    tasks: $tasks,
                    tint: mode.palette.deep,
                    route: mode == .flight ? routePicker : nil,
                    openPDF: { importsDocument = true },
                    done: closeOptions
                )
                .frame(maxHeight: .infinity)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.94, anchor: .bottom).combined(with: .opacity),
                    removal: .scale(scale: 0.97, anchor: .bottom).combined(with: .opacity)
                ))
            }
        }
        .animation(Motion.settle, value: showsOptions)
        .animation(Motion.standard, value: mode)
        .onAppear(perform: loadMinutes)
        .onChange(of: mode) { loadMinutes() }
        .onChange(of: minutes) { UserDefaults.standard.set(minutes, forKey: Preference.minutes(for: mode)) }
    }

    private var controls: some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Text(greeting)
                    .font(.rounded(15, weight: .semibold))
                    .foregroundStyle(Palette.inkSecondary)
                Text(persona.focusQuestion)
                    .font(.rounded(40, weight: .bold))
                    .displayTracking(40)
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
            }

            TextField(persona.focusPlaceholder, text: $intention)
                .textFieldStyle(.plain)
                .font(.rounded(17, weight: .medium))
                .multilineTextAlignment(.center)
                .focused($intentionFocused)
                .onSubmit(start)
                .padding(.horizontal, 24)
                .frame(width: 520, height: 52)
                .glassEffect(.regular.interactive(), in: .capsule)

            ModePicker(selection: $mode)

            DurationControl(minutes: $minutes, tint: mode.palette.deep)

            VStack(spacing: 14) {
                Button(action: start) {
                    Label("Start \(mode.title)", systemImage: "play.fill")
                        .font(.rounded(17, weight: .semibold))
                        .frame(width: 240, height: 34)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(mode.palette.deep)
                .keyboardShortcut(.return, modifiers: .command)

                summary
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 6) {
            Text(summaryText)
                .font(.rounded(13, weight: .medium))
                .foregroundStyle(Palette.inkSecondary)
                .contentTransition(.interpolate)
            Button {
                withAnimation(Motion.settle) { showsOptions = true }
            } label: {
                Label("Customize", systemImage: "slider.horizontal.3")
                    .font(.rounded(13, weight: .semibold))
                    .foregroundStyle(mode.palette.deep)
            }
            .buttonStyle(.plain)
        }
        .animation(Motion.standard, value: summaryText)
    }

    private var summaryText: String {
        var parts = [kind.title]
        if rounds > 1 { parts.append("\(rounds) × \(minutes) min") }
        if let goal = library.goal(goalID) { parts.append(goal.title) }
        if let document { parts.append(document.title) }
        if mode == .flight { parts.append("\(origin.code) → \(destination.code)") }
        let end = Date.now.addingTimeInterval(plan.totalDuration).formatted(date: .omitted, time: .shortened)
        parts.append("ends \(end)")
        return parts.joined(separator: " · ")
    }

    private var routePicker: AnyView {
        AnyView(
            Menu {
                Section("Fits \(TimeInterval(minutes * 60).compactDuration)") {
                    ForEach(origin.routes(closestTo: TimeInterval(minutes * 60)).prefix(8)) { airport in
                        Button("\(airport.city) · \(origin.blockTime(to: airport).compactDuration)") {
                            destinationCode = airport.code
                        }
                    }
                }
                Section("Departing from") {
                    Picker("Home", selection: $homeCode) {
                        ForEach(Airport.catalog.sorted { $0.city < $1.city }) { airport in
                            Text(airport.city).tag(airport.code)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(origin.code).font(.rounded(15, weight: .bold))
                    Image(systemName: "airplane")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(mode.palette.deep)
                    Text(destination.code).font(.rounded(15, weight: .bold))
                    Text(destination.city)
                        .font(.rounded(13, weight: .medium))
                        .foregroundStyle(Palette.inkSecondary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Palette.inkTertiary)
                }
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .contentShape(.rect)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .background(Palette.ink.opacity(0.05), in: .capsule)
        )
    }

    private var greeting: String {
        let base = switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
        return name.isEmpty ? base : "\(base), \(name)"
    }

    private func closeOptions() {
        withAnimation(Motion.standard) { showsOptions = false }
    }

    private func select(_ item: SessionKind) {
        withAnimation(Motion.standard) {
            kindValue = item.rawValue
            minutes = item.defaults.minutes
            rounds = item.defaults.rounds
            if item.defaults.breakMinutes > 0 { breakMinutes = item.defaults.breakMinutes }
        }
    }

    private func loadMinutes() {
        let stored = UserDefaults.standard.integer(forKey: Preference.minutes(for: mode))
        minutes = stored > 0 ? stored : mode.suggestedMinutes
    }

    private func start() {
        intentionFocused = false
        if skipsRituals || NSEvent.modifierFlags.contains(.option) {
            engine.start(plan)
        } else {
            ritual = plan
        }
    }
}

private struct ModePicker: View {
    @Binding var selection: FocusMode
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(FocusMode.allCases) { mode in
                let isSelected = mode == selection
                Button {
                    withAnimation(Motion.standard) { selection = mode }
                } label: {
                    Label(mode.title, systemImage: mode.symbol)
                        .font(.rounded(14, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : Palette.inkSecondary)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(mode.palette.deep)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.pressable)
                .help(mode.tagline)
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
    }
}

private struct DurationControl: View {
    @Binding var minutes: Int
    let tint: Color

    private static let presets = [15, 25, 45, 60, 90]

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 22) {
                IconButton(symbol: "minus", size: 40) { change(by: -5) }
                    .disabled(minutes <= 5)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(minutes)")
                        .font(.numeric(64, weight: .bold))
                        .displayTracking(64)
                        .contentTransition(.numericText(value: Double(minutes)))
                    Text("min")
                        .font(.rounded(18, weight: .semibold))
                        .foregroundStyle(Palette.inkSecondary)
                }
                .foregroundStyle(Palette.ink)
                .frame(minWidth: 150)
                IconButton(symbol: "plus", size: 40) { change(by: 5) }
                    .disabled(minutes >= 240)
            }
            HStack(spacing: 14) {
                ForEach(Self.presets, id: \.self) { preset in
                    Button {
                        withAnimation(Motion.quick) { minutes = preset }
                    } label: {
                        Text("\(preset)")
                            .font(.rounded(13, weight: minutes == preset ? .bold : .medium))
                            .foregroundStyle(minutes == preset ? tint : Palette.inkTertiary)
                            .frame(width: 32, height: 24)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
    }

    private func change(by delta: Int) {
        withAnimation(Motion.quick) {
            minutes = min(240, max(5, minutes + delta))
        }
    }
}

private struct CustomizeCard: View {
    let kinds: [SessionKind]
    @Binding var kind: SessionKind
    @Binding var rounds: Int
    @Binding var breakMinutes: Int
    @Binding var goalID: Goal.ID?
    @Binding var documentID: StudyDocument.ID?
    @Binding var tasks: [SessionTask]
    let tint: Color
    let route: AnyView?
    let openPDF: () -> Void
    let done: () -> Void
    @Environment(Library.self) private var library
    @AppStorage(Preference.persona) private var persona = Persona.personal
    @State private var newTask = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Customize")
                    .font(.rounded(17, weight: .bold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Button("Done", action: done)
                    .font(.rounded(14, weight: .semibold))
                    .foregroundStyle(tint)
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.bottom, 18)

            row("Type") {
                VStack(alignment: .leading, spacing: 8) {
                    FlowLayout(spacing: 6) {
                        ForEach(kinds) { item in
                            Chip(title: item.title, symbol: item.symbol, isSelected: item == kind, tint: tint) {
                                kind = item
                            }
                        }
                    }
                    Text(kind.pitch)
                        .font(.rounded(12, weight: .medium))
                        .foregroundStyle(Palette.inkSecondary)
                        .contentTransition(.interpolate)
                }
            }

            row("Rounds") {
                HStack(spacing: 10) {
                    PillPicker(options: [1, 2, 3, 4], selection: $rounds, tint: tint) { $0 == 1 ? "Once" : "\($0)×" }
                    if rounds > 1 {
                        PillPicker(options: [5, 10, 15], selection: $breakMinutes, tint: tint) { "\($0)′" }
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                        Text("break")
                            .font(.rounded(12, weight: .medium))
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
            }

            if !library.activeGoals.isEmpty {
                row(persona.goalNoun.capitalized) {
                    FlowLayout(spacing: 6) {
                        Chip(title: "None", symbol: nil, isSelected: goalID == nil, tint: tint) { goalID = nil }
                        ForEach(library.activeGoals) { goal in
                            Chip(title: goal.title, dot: goal.tint.color, isSelected: goalID == goal.id, tint: tint) {
                                goalID = goal.id
                            }
                        }
                    }
                }
            }

            row("PDF") {
                documentRow
            }

            if kind.plansTasks {
                row(kind == .examPrep ? "Topics" : "Tasks") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(tasks) { task in
                            HStack(spacing: 8) {
                                Circle()
                                    .strokeBorder(Palette.inkTertiary, lineWidth: 1.5)
                                    .frame(width: 12, height: 12)
                                Text(task.title)
                                    .font(.rounded(13, weight: .medium))
                                    .foregroundStyle(Palette.ink)
                                Spacer()
                                Button {
                                    withAnimation(Motion.quick) { tasks.removeAll { $0.id == task.id } }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(Palette.inkTertiary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        TextField("Add a task and press Return", text: $newTask)
                            .textFieldStyle(.plain)
                            .font(.rounded(13, weight: .medium))
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(Palette.ink.opacity(0.05), in: .capsule)
                            .onSubmit {
                                let title = newTask.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !title.isEmpty else { return }
                                withAnimation(Motion.quick) { tasks.append(SessionTask(title: title)) }
                                newTask = ""
                            }
                    }
                }
            }

            if let route {
                row("Route", divider: false) { route }
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(.white, in: .rect(cornerRadius: 26))
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        .shadow(color: .black.opacity(0.14), radius: 40, y: 18)
        .animation(Motion.standard, value: kind)
        .animation(Motion.standard, value: rounds)
    }

    @ViewBuilder
    private var documentRow: some View {
        if let document = library.documents.first(where: { $0.id == documentID }) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(tint)
                Text(document.title)
                    .font(.rounded(13, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text("p. \(document.lastPage + 1)/\(document.pageCount)")
                    .font(.rounded(12, weight: .medium))
                    .foregroundStyle(Palette.inkTertiary)
                Spacer()
                Button {
                    withAnimation(Motion.quick) { documentID = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.inkTertiary)
                }
                .buttonStyle(.plain)
            }
        } else {
            HStack(spacing: 6) {
                Chip(title: "Choose a PDF…", symbol: "doc.badge.plus", isSelected: false, tint: tint, action: openPDF)
                ForEach(library.documents.sorted { $0.openedAt > $1.openedAt }.prefix(2)) { document in
                    Chip(title: document.title, symbol: nil, isSelected: false, tint: tint) {
                        documentID = document.id
                    }
                }
            }
        }
    }

    private func row<Content: View>(_ title: String, divider: Bool = true, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(title)
                    .font(.rounded(13, weight: .semibold))
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(width: 70, alignment: .leading)
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 14)
            if divider {
                Rectangle()
                    .fill(Palette.hairline)
                    .frame(height: 1)
            }
        }
    }
}

private struct Chip: View {
    let title: String
    var symbol: String?
    var dot: Color?
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button {
            withAnimation(Motion.quick, action)
        } label: {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                }
                if let dot {
                    Circle().fill(dot).frame(width: 7, height: 7)
                }
                Text(title)
                    .font(.rounded(13, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? .white : Palette.ink)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(isSelected ? AnyShapeStyle(tint) : AnyShapeStyle(Palette.ink.opacity(0.06)), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.pressable)
    }
}

private struct PillPicker<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let tint: Color
    let label: (Value) -> String
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(Motion.quick) { selection = option }
                } label: {
                    Text(label(option))
                        .font(.rounded(13, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : Palette.inkSecondary)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(tint)
                                    .matchedGeometryEffect(id: "pill", in: namespace)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Palette.ink.opacity(0.06), in: .capsule)
    }
}
