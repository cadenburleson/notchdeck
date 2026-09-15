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

        store.moveTask(ids["a"]!, toFolder: nil, before: ids["d"]!)   // down
        XCTAssertEqual(store.tasks.map(\.title), ["b", "c", "a", "d"])

        store.moveTask(ids["d"]!, toFolder: nil, before: ids["b"]!)   // up to the top
        XCTAssertEqual(store.tasks.map(\.title), ["d", "b", "c", "a"])

        store.moveTask(ids["b"]!, toFolder: nil)                      // to the end
        XCTAssertEqual(store.tasks.map(\.title), ["d", "c", "a", "b"])

        store.moveTask(UUID(), toFolder: nil)                         // unknown task: no-op
        store.moveTask(ids["a"]!, toFolder: nil, before: ids["a"]!)   // before itself: no-op
        store.moveTask(ids["a"]!, toFolder: UUID())                   // unknown folder: no-op
        XCTAssertEqual(store.tasks.map(\.title), ["d", "c", "a", "b"])
    }

    func testRenameTask() {
        let url = tempURL()
        let store = AppStore(fileURL: url)
        store.addTask("buy milk")
        let id = store.tasks[0].id

        store.renameTask(id, to: "  buy oat milk \n")
        XCTAssertEqual(store.tasks[0].title, "buy oat milk")      // trimmed

        store.renameTask(id, to: "   ")
        XCTAssertEqual(store.tasks[0].title, "buy oat milk")      // empty keeps the old title

        store.renameTask(UUID(), to: "nope")
        XCTAssertEqual(store.tasks.map(\.title), ["buy oat milk"]) // unknown id: no-op

        store.saveNow()
        XCTAssertEqual(AppStore.load(from: url).tasks[0].title, "buy oat milk")
    }

    func testMovedOrderPersists() {
        let url = tempURL()
        let store = AppStore(fileURL: url)
        for title in ["c", "b", "a"] { store.addTask(title) }         // a, b, c
        store.moveTask(store.tasks[0].id, toFolder: nil)              // a to the end
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
