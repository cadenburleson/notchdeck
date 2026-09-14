import XCTest
@testable import NotchDeck

final class StoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("notchdeck-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("state.json")
    }

    func testRoundTrip() {
        let url = tempURL()
        let store = AppStore(fileURL: url)
        store.notes = "hello"
        store.addTask("  write tests ")
        store.addTask("")
        store.settings.pomodoro.focusMinutes = 50
        store.totalFocusSessions = 3
        store.saveNow()

        let loaded = AppStore.load(from: url)
        XCTAssertEqual(loaded.notes, "hello")
        XCTAssertEqual(loaded.tasks.map(\.title), ["write tests"])
        XCTAssertEqual(loaded.settings.pomodoro.focusMinutes, 50)
        XCTAssertEqual(loaded.totalFocusSessions, 3)
    }

    func testTaskOperations() {
        let store = AppStore(fileURL: tempURL())
        store.addTask("a")
        store.addTask("b")
        XCTAssertEqual(store.tasks.map(\.title), ["b", "a"])
        XCTAssertEqual(store.pendingTaskCount, 2)

        store.toggleTask(store.tasks[0].id)
        XCTAssertEqual(store.pendingTaskCount, 1)

        store.clearCompletedTasks()
        XCTAssertEqual(store.tasks.map(\.title), ["a"])

        store.removeTask(store.tasks[0].id)
        XCTAssertTrue(store.tasks.isEmpty)
    }

    func testMoveTask() {
        let store = AppStore(fileURL: tempURL())
        for title in ["d", "c", "b", "a"] { store.addTask(title) }   // a, b, c, d
        let ids = Dictionary(uniqueKeysWithValues: store.tasks.map { ($0.title, $0.id) })

        store.moveTask(ids["a"]!, to: 2)          // down
        XCTAssertEqual(store.tasks.map(\.title), ["b", "c", "a", "d"])

        store.moveTask(ids["d"]!, to: 0)          // up to top
        XCTAssertEqual(store.tasks.map(\.title), ["d", "b", "c", "a"])

        store.moveTask(ids["b"]!, to: 99)         // clamped to bottom
        XCTAssertEqual(store.tasks.map(\.title), ["d", "c", "a", "b"])

        store.moveTask(ids["c"]!, to: -5)         // clamped to top
        XCTAssertEqual(store.tasks.map(\.title), ["c", "d", "a", "b"])

        store.moveTask(UUID(), to: 0)             // unknown id: no-op
        store.moveTask(ids["a"]!, to: 2)          // same index: no-op
        XCTAssertEqual(store.tasks.map(\.title), ["c", "d", "a", "b"])
    }

    func testMovedOrderPersists() {
        let url = tempURL()
        let store = AppStore(fileURL: url)
        for title in ["c", "b", "a"] { store.addTask(title) }
        store.moveTask(store.tasks[0].id, to: 2)
        store.saveNow()
        XCTAssertEqual(AppStore.load(from: url).tasks.map(\.title), ["b", "c", "a"])
    }

    func testDecodingToleratesMissingKeys() throws {
        let json = #"{"notes":"x"}"#.data(using: .utf8)!
        let state = try JSONDecoder.notchDeck.decode(PersistedState.self, from: json)
        XCTAssertEqual(state.notes, "x")
        XCTAssertEqual(state.settings.pomodoro.focusMinutes, 25)
        XCTAssertTrue(state.tasks.isEmpty)
    }

    func testMissingFileGivesDefaults() {
        let store = AppStore.load(from: tempURL())
        XCTAssertEqual(store.notes, "")
        XCTAssertTrue(store.tasks.isEmpty)
    }
}
