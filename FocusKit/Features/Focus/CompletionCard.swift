import SwiftUI

struct CompletionCard: View {
    let session: Session
    var stopRecording: (() -> Void)?
    @Environment(FocusEngine.self) private var engine
    @Environment(Library.self) private var library
    @State private var note = ""
    @State private var celebrates = false

    var body: some View {
        ZStack {
            Color.white.opacity(0.25)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 76)
                    .background(session.mode.palette.deep.gradient, in: .circle)
                    .shadow(color: session.mode.palette.deep.opacity(0.4), radius: 18, y: 8)
                    .symbolEffect(.bounce, value: celebrates)

                VStack(spacing: 6) {
                    Text(title)
                        .font(.rounded(30, weight: .bold))
                        .displayTracking(30)
                        .foregroundStyle(Palette.ink)
                    Text(session.intention.isEmpty ? "Nicely done. Take a breath before the next one." : session.intention)
                        .font(.rounded(15, weight: .medium))
                        .foregroundStyle(Palette.inkSecondary)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 34) {
                    Stat(label: "Focused", value: "\(Int((session.focused / 60).rounded()))", unit: "min")
                    if session.roundsPlanned > 1 {
                        Stat(label: "Rounds", value: "\(session.roundsCompleted)/\(session.roundsPlanned)")
                    }
                    if let tasks = session.tasks, !tasks.isEmpty {
                        Stat(label: "Tasks", value: "\(tasks.count { $0.isDone })/\(tasks.count)")
                    }
                    if let pages = session.pages {
                        Stat(label: "Pages", value: "\(pages.count)")
                    }
                    if let goal = library.goal(session.goalID) {
                        Stat(label: "Goal", value: goal.title, size: 18)
                    }
                }

                if let parked = session.parked, !parked.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("You parked \(parked.count) thought\(parked.count == 1 ? "" : "s")", systemImage: "tray.and.arrow.down.fill")
                            .font(.rounded(13, weight: .bold))
                            .foregroundStyle(session.mode.palette.deep)
                        ForEach(parked.prefix(3), id: \.self) { thought in
                            Text("• \(thought)")
                                .font(.rounded(13, weight: .medium))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(session.mode.palette.light.opacity(0.7), in: .rect(cornerRadius: 18))
                }

                if let stopRecording {
                    RecordingStatus(tint: session.mode.palette.deep, stop: stopRecording)
                }

                TextField("Add a note for your journal", text: $note, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.rounded(15))
                    .lineLimit(1...3)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(.white.opacity(0.7), in: .rect(cornerRadius: 18))
                    .onSubmit { engine.finish(note: note) }

                Button {
                    engine.finish(note: note)
                } label: {
                    Text("Done")
                        .font(.rounded(16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(session.mode.palette.deep)
                .keyboardShortcut(.defaultAction)
            }
            .padding(32)
            .frame(width: 440)
            .glassEffect(.regular, in: .rect(cornerRadius: 36))
            .shadow(color: .black.opacity(0.08), radius: 40, y: 20)
        }
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            celebrates.toggle()
        }
    }

    private var icon: String {
        switch session.mode {
        case .flight: "airplane.arrival"
        case .orbit: "sparkles"
        case .bloom: "camera.macro"
        case .tide: "sailboat.fill"
        }
    }

    private var title: String {
        switch session.mode {
        case .flight:
            let city = session.route.flatMap { Airport.named($0.destination)?.city } ?? "your destination"
            return "Landed in \(city)"
        case .orbit: return "Orbit complete"
        case .bloom: return "In full bloom"
        case .tide: return "High tide"
        }
    }
}

private struct RecordingStatus: View {
    let tint: Color
    let stop: () -> Void
    @Environment(VoiceRecorder.self) private var recorder
    @State private var pulses = false

    var body: some View {
        HStack(spacing: 12) {
            indicator
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.rounded(14, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(subtitle)
                        .font(.rounded(12, weight: .medium))
                        .foregroundStyle(Palette.inkSecondary)
                        .contentTransition(.numericText())
                }
            }
            Spacer(minLength: 8)
            if case .recording = recorder.state {
                Button("Stop", action: stop)
                    .font(.rounded(13, weight: .semibold))
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .transition(.blurReplace)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
        .background(.white.opacity(0.7), in: .rect(cornerRadius: 18))
        .animation(Motion.standard, value: recorder.state)
        .onAppear { pulses = true }
    }

    @ViewBuilder
    private var indicator: some View {
        switch recorder.state {
        case .recording:
            Circle()
                .fill(Palette.record)
                .frame(width: 10, height: 10)
                .opacity(pulses ? 0.35 : 1)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulses)
                .frame(width: 22)
        case .finishing, .preparing, .downloadingModel:
            ProgressView()
                .controlSize(.small)
                .frame(width: 22)
        case .idle:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(tint)
                .frame(width: 22)
                .transition(.scale.combined(with: .opacity))
        }
    }

    private var title: String {
        switch recorder.state {
        case .recording: "Still recording"
        case .finishing, .preparing, .downloadingModel: "Saving the transcript"
        case .idle: "Transcript saved"
        }
    }

    private var subtitle: String {
        switch recorder.state {
        case .recording(let since):
            "\(Date.now.timeIntervalSince(since).clock) so far · keeps going until you stop"
        case .finishing, .preparing, .downloadingModel:
            "This takes a moment"
        case .idle:
            "Clean notes will appear in your journal"
        }
    }
}
