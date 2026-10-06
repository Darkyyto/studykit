import SwiftUI

struct GoalEditor: View {
    @State var goal: Goal
    @Environment(Library.self) private var library
    @Environment(\.closeCard) private var dismiss
    @FocusState private var titleFocused: Bool
    @AppStorage(Preference.persona) private var persona = Persona.personal

    private var isNew: Bool {
        library.goal(goal.id) == nil
    }

    private var canSave: Bool {
        !goal.title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text(isNew ? "New \(persona.goalNoun.capitalized)" : "Edit \(persona.goalNoun.capitalized)")
                    .font(.rounded(15, weight: .semibold))
                    .foregroundStyle(Palette.inkSecondary)
                Spacer()
                Circle()
                    .fill(goal.tint.color.gradient)
                    .frame(width: 14, height: 14)
            }

            VStack(alignment: .leading, spacing: 10) {
                TextField("Finish the thesis", text: $goal.title)
                    .textFieldStyle(.plain)
                    .font(.rounded(26, weight: .bold))
                    .focused($titleFocused)
                TextField("Why it matters to you", text: $goal.notes, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.rounded(15))
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1...4)
            }

            VStack(alignment: .leading, spacing: 12) {
                Eyebrow("Color")
                HStack(spacing: 12) {
                    ForEach(Goal.Tint.allCases) { tint in
                        Button {
                            withAnimation(Motion.quick) { goal.tint = tint }
                        } label: {
                            Circle()
                                .fill(tint.color.gradient)
                                .frame(width: 26, height: 26)
                                .overlay {
                                    Circle()
                                        .strokeBorder(.white, lineWidth: 3)
                                        .opacity(goal.tint == tint ? 1 : 0)
                                }
                                .shadow(color: tint.color.opacity(goal.tint == tint ? 0.5 : 0), radius: 6, y: 2)
                                .scaleEffect(goal.tint == tint ? 1.12 : 1)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel(tint.rawValue.capitalized)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Eyebrow("Weekly target")
                    Spacer()
                    Text(TimeInterval(goal.weeklyTargetMinutes * 60).compactDuration)
                        .font(.numeric(15, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText())
                }
                Slider(
                    value: Binding(
                        get: { Double(goal.weeklyTargetMinutes) },
                        set: { goal.weeklyTargetMinutes = Int($0) }
                    ),
                    in: 30...1800,
                    step: 30
                )
                .tint(goal.tint.color)
            }

            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { goal.deadline != nil },
                    set: { goal.deadline = $0 ? Calendar.current.date(byAdding: .day, value: 14, to: .now) : nil }
                )) {
                    Eyebrow(persona.deadlineLabel)
                }
                .toggleStyle(.switch)
                .tint(goal.tint.color)
                if let deadline = goal.deadline {
                    DatePicker(
                        persona.deadlineLabel,
                        selection: Binding(get: { deadline }, set: { goal.deadline = $0 }),
                        in: Date.now...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.field)
                    .labelsHidden()
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(Motion.standard, value: goal.deadline != nil)

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Create" : "Save") {
                    goal.title = goal.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    library.save(goal)
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(goal.tint.color)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(30)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { titleFocused = isNew }
    }
}
