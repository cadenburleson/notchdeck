import XCTest
@testable import NotchDeck

final class FolderTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("notchdeck-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("state.json")
    }

    func testAddFolderTrimsAndPicksDistinctColors() {
        let store = AppStore(fileURL: tempURL())
        XCTAssertNil(store.addFolder("   "))
        let work = store.addFolder("  Work ")!
        let home = store.addFolder("Home")!
        XCTAssertEqual(work.name, "Work")
        XCTAssertNotEqual(work.color, home.color)
        XCTAssertFalse(work.isCollapsed)
        XCTAssertEqual(store.folders.map(\.name), ["Work", "Home"])
    }

    func testColorsWrapAroundOnceThePaletteIsUsed() {
        let store = AppStore(fileURL: tempURL())
        for i in 0..<FolderColor.allCases.count { store.addFolder("f\(i)") }
        XCTAssertEqual(Set(store.folders.map(\.color)).count, FolderColor.allCases.count)
        XCTAssertNotNil(store.addFolder("one more"))
    }

    func testAddingTasksIntoFolders() {
        let store = AppStore(fileURL: tempURL())
        let work = store.addFolder("Work")!
        store.addTask("loose")
        store.addTask("report", folderID: work.id)
        store.addTask("ghost", folderID: UUID())                     // unknown folder: unfiled

        XCTAssertEqual(store.tasks(inFolder: nil).map(\.title), ["ghost", "loose"])
        XCTAssertEqual(store.tasks(inFolder: work.id).map(\.title), ["report"])

        store.toggleTask(store.tasks(inFolder: work.id)[0].id)
        XCTAssertEqual(store.pendingTaskCount(inFolder: work.id), 0)
        XCTAssertEqual(store.pendingTaskCount, 2)
    }

    func testMovingTasksBetweenFolders() {
        let store = AppStore(fileURL: tempURL())
        let work = store.addFolder("Work")!
        let home = store.addFolder("Home")!
        let seed: [(String, UUID?)] = [("h1", home.id), ("w2", work.id), ("w1", work.id), ("u2", nil), ("u1", nil)]
        for (title, folder) in seed { store.addTask(title, folderID: folder) }   // u1 u2 w1 w2 h1
        let id = { (title: String) in store.tasks.first { $0.title == title }!.id }

        store.moveTask(id("u1"), toFolder: work.id, before: id("w2"))          // into Work, between w1 and w2
        XCTAssertEqual(store.tasks(inFolder: work.id).map(\.title), ["w1", "u1", "w2"])
        XCTAssertEqual(store.tasks(inFolder: nil).map(\.title), ["u2"])

        store.moveTask(id("w1"), toFolder: nil)                                // out of Work, end of unfiled
        XCTAssertEqual(store.tasks(inFolder: nil).map(\.title), ["u2", "w1"])

        store.moveTask(id("w2"), toFolder: home.id)                            // end of Home
        XCTAssertEqual(store.tasks(inFolder: home.id).map(\.title), ["h1", "w2"])

        store.moveTask(id("u2"), toFolder: home.id, before: id("u1"))          // "before" is in another folder: end of Home
        XCTAssertEqual(store.tasks(inFolder: home.id).map(\.title), ["h1", "w2", "u2"])
        XCTAssertEqual(store.tasks(inFolder: work.id).map(\.title), ["u1"])
    }

    func testMovingFolders() {
        let url = tempURL()
        let store = AppStore(fileURL: url)
        let a = store.addFolder("A")!, b = store.addFolder("B")!, c = store.addFolder("C")!
        store.addTask("in b", folderID: b.id)

        store.moveFolder(a.id, to: 2)
        XCTAssertEqual(store.folders.map(\.name), ["B", "C", "A"])
        store.moveFolder(a.id, to: -3)                                         // clamped to the top
        XCTAssertEqual(store.folders.map(\.name), ["A", "B", "C"])
        store.moveFolder(c.id, to: 99)                                         // already last: no-op
        store.moveFolder(UUID(), to: 0)                                        // unknown: no-op
        XCTAssertEqual(store.folders.map(\.name), ["A", "B", "C"])

        store.moveFolder(b.id, to: 0)
        XCTAssertEqual(store.tasks[0].folderID, b.id)                          // tasks stay with their folder
        store.saveNow()
        XCTAssertEqual(AppStore.load(from: url).folders.map(\.name), ["B", "A", "C"])
    }

    func testRenameRecolorAndCollapse() {
        let store = AppStore(fileURL: tempURL())
        let work = store.addFolder("Work")!
        store.renameFolder(work.id, to: "  Job ")
        XCTAssertEqual(store.folders[0].name, "Job")
        store.renameFolder(work.id, to: "  ")                                  // empty keeps the old name
        XCTAssertEqual(store.folders[0].name, "Job")
        store.setFolderColor(work.id, .pink)
        XCTAssertEqual(store.folders[0].color, .pink)
        store.setFolderCollapsed(work.id, true)
        XCTAssertTrue(store.folders[0].isCollapsed)
    }

    func testDeletingAFolderKeepsItsTasksAsUnfiled() {
        let store = AppStore(fileURL: tempURL())
        let work = store.addFolder("Work")!
        store.addTask("loose")
        store.addTask("report", folderID: work.id)

        store.deleteFolder(work.id)
        XCTAssertTrue(store.folders.isEmpty)
        XCTAssertEqual(store.tasks(inFolder: nil).map(\.title), ["report", "loose"])
    }

    func testFoldersPersistAndStaleReferencesAreDropped() {
        let url = tempURL()
        let store = AppStore(fileURL: url)
        let work = store.addFolder("Work")!
        store.setFolderCollapsed(work.id, true)
        store.addTask("report", folderID: work.id)
        store.saveNow()

        let loaded = AppStore.load(from: url)
        XCTAssertEqual(loaded.folders, store.folders)
        XCTAssertEqual(loaded.tasks[0].folderID, work.id)

        var orphaned = loaded.snapshot
        orphaned.folders = []
        XCTAssertNil(AppStore(state: orphaned, fileURL: tempURL()).tasks[0].folderID)
    }

    func testOlderStateFilesAndUnknownColorsStillLoad() throws {
        let json = #"""
        {"tasks":[{"id":"1D0C1E2E-0000-4000-8000-000000000001","title":"old","isDone":false,"createdAt":"2026-09-14T08:00:00Z"}],
         "folders":[{"id":"1D0C1E2E-0000-4000-8000-0000000000AA","name":"Weird","color":"chartreuse"}]}
        """#.data(using: .utf8)!
        let state = try JSONDecoder.notchDeck.decode(PersistedState.self, from: json)
        XCTAssertEqual(state.tasks[0].title, "old")
        XCTAssertNil(state.tasks[0].folderID)
        XCTAssertEqual(state.folders[0].name, "Weird")
        XCTAssertEqual(state.folders[0].color, .gray)
        XCTAssertFalse(state.folders[0].isCollapsed)
    }
}
