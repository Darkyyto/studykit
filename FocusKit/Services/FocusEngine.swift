import Foundation
import Observation

@MainActor
@Observable
final class FocusEngine {
    enum Phase: Equatable {
        case idle
        case running(endsAt: Date)
        case paused(remaining: TimeInterval)
        case complete(Session)
    }

    private(set) var phase: Phase = .idle
    private(set) var plan: FocusPlan?
    private(set) var segmentIndex = 0
    private(set) var now = Date.now
    let workspace = SessionWorkspace()
    private(set) var lastSessionID: Session.ID?

    @ObservationIgnored private let library: Library
    @ObservationIgnored private let notifier = SessionNotifier()
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var focusedInCompletedSegments: TimeInterval = 0
    @ObservationIgnored private var segmentTask: Task<Void, Never>?
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    @ObservationIgnored private var pendingRecording: Recording.ID?

    init(library: Library) {
        self.library = library
    }

    var isActive: Bool {
        switch phase {
        case .running, .paused: true
        case .idle, .complete: false
        }
    }

    var isPaused: Bool {
        if case .paused = phase { true } else { false }
    }

    var segment: FocusPlan.Segment? {
        guard let segments = plan?.segments, segments.indices.contains(segmentIndex) else { return nil }
        return segments[segmentIndex]
    }

    var isResting: Bool {
        segment?.kind == .rest && isActive
    }

    func remaining(at date: Date) -> TimeInterval {
        switch phase {
        case .idle: plan?.focusDuration ?? 0
        case .running(let endsAt): max(0, endsAt.timeIntervalSince(date))
        case .paused(let remaining): remaining
        case .complete: 0
        }
    }

    func segmentProgress(at date: Date) -> Double {
        guard let segment, segment.duration > 0 else { return phase.isComplete ? 1 : 0 }
        return min(1, max(0, 1 - remaining(at: date) / segment.duration))
    }

    func focused(at date: Date) -> TimeInterval {
        guard let segment, segment.kind == .focus, isActive else { return focusedInCompletedSegments }
        return focusedInCompletedSegments + segment.duration - remaining(at: date)
    }

    func focusProgress(at date: Date) -> Double {
        if phase.isComplete { return 1 }
        guard let plan, plan.totalFocus > 0 else { return 0 }
        return min(1, focused(at: date) / plan.totalFocus)
    }

    func start(_ plan: FocusPlan) {
        guard !isActive else { return }
        self.plan = plan
        workspace.reset(tasks: plan.tasks)
        lastSessionID = nil
        pendingRecording = nil
        startedAt = .now
        segmentIndex = 0
        focusedInCompletedSegments = 0
        run(for: plan.focusDuration)
    }

    func pause() {
        guard case .running = phase else { return }
        phase = .paused(remaining: remaining(at: .now))
        segmentTask?.cancel()
        notifier.cancel()
    }

    func resume() {
        guard case .paused(let remaining) = phase else { return }
        run(for: remaining)
    }

    func togglePause() {
        isPaused ? resume() : pause()
    }

    func skip() {
        guard isActive else { return }
        segmentTask?.cancel()
        notifier.cancel()
        advance()
    }

    func stop() {
        guard isActive, let plan else { return }
        segmentTask?.cancel()
        notifier.cancel()
        let focused = focused(at: .now)
        if focused >= 60 || plan.kind.recordsAudio {
            library.log(makeSession(from: plan, focused: focused, outcome: .stopped))
        }
        reset()
    }

    func finish(note: String) {
        guard case .complete(let completed) = phase else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, var session = library.sessions.first(where: { $0.id == completed.id }) {
            session.note = trimmed
            library.log(session)
        }
        reset()
    }

    private func reset() {
        heartbeat?.cancel()
        heartbeat = nil
        phase = .idle
        segmentIndex = 0
        focusedInCompletedSegments = 0
        startedAt = nil
    }

    private func run(for duration: TimeInterval) {
        let endsAt = Date.now.addingTimeInterval(duration)
        phase = .running(endsAt: endsAt)
        segmentTask?.cancel()
        segmentTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.segmentDidEnd()
        }
        scheduleNotification(at: endsAt)
        startHeartbeat()
    }

    private func startHeartbeat() {
        guard heartbeat == nil else { return }
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                self?.now = .now
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func segmentDidEnd() {
        guard case .running(let endsAt) = phase else { return }
        let remaining = endsAt.timeIntervalSinceNow
        guard remaining <= 0.5 else {
            run(for: remaining)
            return
        }
        advance()
    }

    private func advance() {
        guard let plan, let segment else { return }
        if segment.kind == .focus {
            focusedInCompletedSegments += segment.duration - remaining(at: .now)
        }

        let next = segmentIndex + 1
        guard plan.segments.indices.contains(next) else {
            var session = makeSession(from: plan, focused: focusedInCompletedSegments, outcome: .completed)
            if let pendingRecording {
                session.recordingID = pendingRecording
                self.pendingRecording = nil
            }
            library.log(session)
            heartbeat?.cancel()
            heartbeat = nil
            phase = .complete(session)
            return
        }
        segmentIndex = next
        run(for: plan.segments[next].duration)
    }

    private func scheduleNotification(at date: Date) {
        guard let plan, let segment else { return }
        let isLast = segmentIndex == plan.segments.count - 1
        let title: String
        let body: String
        switch (segment.kind, isLast) {
        case (.focus, true):
            title = "Session complete"
            body = plan.intention.isEmpty ? "Nice work. Take a moment before the next one." : "You finished: \(plan.intention)"
        case (.focus, false):
            title = "Time for a break"
            body = "Round \(segment.round + 1) of \(plan.rounds) done. Step away for a few minutes."
        case (.rest, _):
            title = "Back to focus"
            body = "Round \(segment.round + 2) of \(plan.rounds) is starting."
        }
        Task { await notifier.schedule(title: title, body: body, at: date) }
    }

    private func makeSession(from plan: FocusPlan, focused: TimeInterval, outcome: Session.Outcome) -> Session {
        let completedRounds = plan.segments.prefix(segmentIndex + (outcome == .completed ? 1 : 0)).count { $0.kind == .focus }
        let notes = workspace.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        var session = Session(
            mode: plan.mode,
            goalID: plan.goalID,
            intention: plan.intention,
            startedAt: startedAt ?? .now.addingTimeInterval(-focused),
            endedAt: .now,
            plannedFocus: plan.totalFocus,
            focused: focused,
            roundsPlanned: plan.rounds,
            roundsCompleted: completedRounds,
            outcome: outcome,
            route: plan.route
        )
        session.kind = plan.kind
        session.notes = notes.isEmpty ? nil : notes
        session.tasks = workspace.tasks.isEmpty ? nil : workspace.tasks
        session.parked = workspace.parked.isEmpty ? nil : workspace.parked
        session.documentID = plan.documentID
        session.pages = workspace.pages
        lastSessionID = session.id
        return session
    }

    func attachRecording(_ id: Recording.ID) {
        guard let sessionID = lastSessionID,
              var session = library.sessions.first(where: { $0.id == sessionID }) else {
            pendingRecording = id
            return
        }
        session.recordingID = id
        library.log(session)
    }
}

extension FocusEngine.Phase {
    var isComplete: Bool {
        if case .complete = self { true } else { false }
    }
}

@MainActor
@Observable
final class SessionWorkspace {
    var notes = ""
    var tasks: [SessionTask] = []
    var parked: [String] = []
    var pages: ClosedRange<Int>?

    func markRead(_ page: Int) {
        guard let pages else {
            self.pages = page...page
            return
        }
        self.pages = min(pages.lowerBound, page)...max(pages.upperBound, page)
    }

    func quote(_ text: String, page: Int) {
        let quote = "“\(text)” (p. \(page + 1))"
        notes = notes.isEmpty ? quote : notes + "\n\n" + quote
    }

    var wordCount: Int {
        notes.split { $0.isWhitespace || $0.isNewline }.count
    }

    func reset(tasks: [SessionTask]) {
        notes = ""
        parked = []
        pages = nil
        self.tasks = tasks
    }

    func addTask(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tasks.append(SessionTask(title: trimmed))
    }

    func toggle(_ task: SessionTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].isDone.toggle()
    }

    func park(_ thought: String) {
        let trimmed = thought.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        parked.insert(trimmed, at: 0)
    }
}
