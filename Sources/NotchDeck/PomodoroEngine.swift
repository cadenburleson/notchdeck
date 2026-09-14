import Foundation
import Combine

enum PomodoroPhase: String, Codable {
    case focus, shortBreak, longBreak

    var title: String {
        switch self {
        case .focus: return "Focus"
        case .shortBreak: return "Short Break"
        case .longBreak: return "Long Break"
        }
    }

    var isBreak: Bool { self != .focus }
}

/// Drives the pomodoro cycle. Time is derived from an end date so the timer
/// stays accurate even if the run loop is throttled.
final class PomodoroEngine: ObservableObject {
    @Published private(set) var phase: PomodoroPhase = .focus
    @Published private(set) var isRunning = false
    @Published private(set) var remaining: TimeInterval
    /// Focus sessions completed in the current cycle (resets after a long break).
    @Published private(set) var completedInCycle = 0

    /// Called whenever a focus session finishes.
    var onFocusSessionCompleted: (() -> Void)?
    /// Called when any phase finishes, with the phase that is about to start.
    var onPhaseCompleted: ((PomodoroPhase, PomodoroPhase) -> Void)?

    private let settings: () -> PomodoroSettings
    private var endDate: Date?
    private var ticker: AnyCancellable?
    private let now: () -> Date

    init(settings: @escaping () -> PomodoroSettings, now: @escaping () -> Date = Date.init) {
        self.settings = settings
        self.now = now
        self.remaining = TimeInterval(settings().focusMinutes * 60)
    }

    var phaseDuration: TimeInterval {
        let s = settings()
        switch phase {
        case .focus: return TimeInterval(s.focusMinutes * 60)
        case .shortBreak: return TimeInterval(s.shortBreakMinutes * 60)
        case .longBreak: return TimeInterval(s.longBreakMinutes * 60)
        }
    }

    /// 0...1, how much of the current phase has elapsed.
    var progress: Double {
        guard phaseDuration > 0 else { return 0 }
        return min(1, max(0, 1 - remaining / phaseDuration))
    }

    var isIdle: Bool { !isRunning && remaining == phaseDuration }

    // MARK: - Controls

    func start() {
        guard !isRunning else { return }
        endDate = now().addingTimeInterval(remaining)
        isRunning = true
        ticker = Timer.publish(every: 0.25, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
        tick()
    }

    func pause() {
        guard isRunning else { return }
        tick()
        isRunning = false
        endDate = nil
        ticker = nil
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    /// Reset the current phase to its full duration.
    func reset() {
        pause()
        remaining = phaseDuration
    }

    /// Reset everything back to a fresh focus session.
    func resetCycle() {
        pause()
        phase = .focus
        completedInCycle = 0
        remaining = phaseDuration
    }

    /// Abandon the current phase and move on to the next one.
    func skip() {
        let wasRunning = isRunning
        pause()
        advance(countAsCompleted: false)
        if wasRunning && settings().autoStartNext { start() }
    }

    /// Re-syncs the remaining time when the user changes durations while idle.
    func settingsDidChange() {
        if !isRunning && remaining > phaseDuration { remaining = phaseDuration }
        if isIdle || (!isRunning && remaining == 0) { remaining = phaseDuration }
    }

    // MARK: - Internals

    func tick() {
        guard isRunning, let end = endDate else { return }
        let left = end.timeIntervalSince(now())
        if left <= 0 {
            remaining = 0
            isRunning = false
            endDate = nil
            ticker = nil
            advance(countAsCompleted: true)
            if settings().autoStartNext { start() }
        } else {
            remaining = left
        }
    }

    private func advance(countAsCompleted: Bool) {
        let finished = phase
        if finished == .focus && countAsCompleted {
            completedInCycle += 1
            onFocusSessionCompleted?()
        }

        let next: PomodoroPhase
        switch finished {
        case .focus:
            let target = max(1, settings().sessionsBeforeLongBreak)
            next = completedInCycle >= target ? .longBreak : .shortBreak
        case .shortBreak:
            next = .focus
        case .longBreak:
            completedInCycle = 0
            next = .focus
        }

        phase = next
        remaining = phaseDuration
        if countAsCompleted { onPhaseCompleted?(finished, next) }
    }
}

extension TimeInterval {
    /// "25:00" style formatting, rounding up so 24:59.4 shows as 25:00 at the start.
    var clockString: String {
        let total = Int(self.rounded(.up))
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}
