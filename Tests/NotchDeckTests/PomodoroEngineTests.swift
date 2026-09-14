import XCTest
@testable import NotchDeck

final class PomodoroEngineTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_000_000)

    private func makeEngine(_ settings: PomodoroSettings = PomodoroSettings()) -> PomodoroEngine {
        PomodoroEngine(settings: { settings }, now: { self.clock })
    }

    func testStartsIdleWithFocusDuration() {
        let engine = makeEngine()
        XCTAssertEqual(engine.phase, .focus)
        XCTAssertTrue(engine.isIdle)
        XCTAssertEqual(engine.remaining, 25 * 60)
        XCTAssertEqual(engine.remaining.clockString, "25:00")
    }

    func testCountsDownFromEndDate() {
        let engine = makeEngine()
        engine.start()
        clock = clock.addingTimeInterval(61)
        engine.tick()
        XCTAssertEqual(engine.remaining, 25 * 60 - 61, accuracy: 0.01)
        XCTAssertEqual(engine.remaining.clockString, "23:59")
        XCTAssertTrue(engine.isRunning)
    }

    func testFocusCompletionMovesToShortBreak() {
        let engine = makeEngine()
        var completed = 0
        engine.onFocusSessionCompleted = { completed += 1 }
        engine.start()
        clock = clock.addingTimeInterval(25 * 60 + 1)
        engine.tick()
        XCTAssertEqual(completed, 1)
        XCTAssertEqual(engine.phase, .shortBreak)
        XCTAssertEqual(engine.completedInCycle, 1)
        XCTAssertFalse(engine.isRunning)
        XCTAssertEqual(engine.remaining, 5 * 60)
    }

    func testLongBreakAfterConfiguredSessions() {
        var s = PomodoroSettings()
        s.sessionsBeforeLongBreak = 2
        let engine = makeEngine(s)

        for _ in 0..<2 {
            engine.start()
            clock = clock.addingTimeInterval(TimeInterval(s.focusMinutes * 60 + 1))
            engine.tick()
            if engine.phase == .shortBreak {
                engine.start()
                clock = clock.addingTimeInterval(TimeInterval(s.shortBreakMinutes * 60 + 1))
                engine.tick()
            }
        }
        XCTAssertEqual(engine.phase, .longBreak)

        engine.start()
        clock = clock.addingTimeInterval(TimeInterval(s.longBreakMinutes * 60 + 1))
        engine.tick()
        XCTAssertEqual(engine.phase, .focus)
        XCTAssertEqual(engine.completedInCycle, 0)
    }

    func testSkipDoesNotCountAsCompleted() {
        let engine = makeEngine()
        engine.start()
        engine.skip()
        XCTAssertEqual(engine.phase, .shortBreak)
        XCTAssertEqual(engine.completedInCycle, 0)
        XCTAssertFalse(engine.isRunning)
    }

    func testAutoStartNext() {
        var s = PomodoroSettings()
        s.autoStartNext = true
        let engine = makeEngine(s)
        engine.start()
        clock = clock.addingTimeInterval(25 * 60 + 1)
        engine.tick()
        XCTAssertEqual(engine.phase, .shortBreak)
        XCTAssertTrue(engine.isRunning)
    }

    func testPauseAndResume() {
        let engine = makeEngine()
        engine.start()
        clock = clock.addingTimeInterval(30)
        engine.pause()
        let paused = engine.remaining
        clock = clock.addingTimeInterval(600)
        engine.tick()
        XCTAssertEqual(engine.remaining, paused)
        engine.start()
        clock = clock.addingTimeInterval(30)
        engine.tick()
        XCTAssertEqual(engine.remaining, 25 * 60 - 60, accuracy: 0.01)
    }
}
