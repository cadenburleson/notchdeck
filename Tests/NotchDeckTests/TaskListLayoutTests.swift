import XCTest
@testable import NotchDeck

/// Fixture, top to bottom:
///   u1, u2            (unfiled)
///   [Work]  w1, w2    (expanded)
///   [Home]            (collapsed; h1 hidden)
final class TaskListLayoutTests: XCTestCase {
    private let work = TaskFolder(name: "Work", color: .blue)
    private let home = TaskFolder(name: "Home", color: .orange, isCollapsed: true)
    private var tasks: [TodoItem] = []
    private var layout: TaskListLayout!

    override func setUp() {
        super.setUp()
        tasks = [
            TodoItem(title: "w1", folderID: work.id),
            TodoItem(title: "u1"),
            TodoItem(title: "h1", folderID: home.id),
            TodoItem(title: "w2", folderID: work.id),
            TodoItem(title: "u2"),
        ]
        layout = TaskListLayout(tasks: tasks, folders: [work, home])
    }

    private func id(_ title: String) -> UUID { tasks.first { $0.title == title }!.id }

    private func names(_ layout: TaskListLayout) -> [String] {
        layout.items.map {
            switch $0 {
            case .task(let task): return task.title
            case .header(let folder): return "[\(folder.name)]"
            }
        }
    }

    func testFlattensUnfiledFirstThenFoldersAndHidesCollapsedTasks() {
        XCTAssertEqual(names(layout), ["u1", "u2", "[Work]", "w1", "w2", "[Home]"])
        XCTAssertEqual(TaskListLayout.tops(of: layout.items), [0, 32, 64, 94, 126, 158])
    }

    func testDraggingAnUnfiledTaskJustUnderAFolderHeader() {
        let origin = layout.index(ofTask: id("u1"))!
        XCTAssertEqual(origin, 0)
        let slot = layout.dropSlot(origin: origin, translation: 60)
        XCTAssertEqual(slot, 2)

        let destination = layout.destination(origin: origin, slot: slot)
        XCTAssertEqual(destination.folderID, work.id)
        XCTAssertEqual(destination.beforeTaskID, id("w1"))

        // u2 and the Work header slide up to open the gap under the header.
        let offsets = layout.items.indices.map { layout.offset(ofItemAt: $0, origin: origin, slot: slot) }
        XCTAssertEqual(offsets, [0, -32, -32, 0, 0, 0])
        XCTAssertEqual(layout.landingShift(origin: origin, slot: slot), 62)
    }

    func testDraggingPastTheEndFilesIntoTheCollapsedFolder() {
        let translation = layout.clampedTranslation(500, origin: 0)
        XCTAssertEqual(translation, 156)
        let slot = layout.dropSlot(origin: 0, translation: translation)
        XCTAssertEqual(slot, 5)

        let destination = layout.destination(origin: 0, slot: slot)
        XCTAssertEqual(destination.folderID, home.id)
        XCTAssertNil(destination.beforeTaskID)
    }

    func testDraggingAFolderTaskToTheTopUnfilesIt() {
        let origin = layout.index(ofTask: id("w2"))!
        XCTAssertEqual(origin, 4)
        XCTAssertEqual(layout.clampedTranslation(-500, origin: origin), -126)
        let slot = layout.dropSlot(origin: origin, translation: -130)
        XCTAssertEqual(slot, 0)

        let destination = layout.destination(origin: origin, slot: slot)
        XCTAssertNil(destination.folderID)
        XCTAssertEqual(destination.beforeTaskID, id("u1"))

        let offsets = layout.items.indices.map { layout.offset(ofItemAt: $0, origin: origin, slot: slot) }
        XCTAssertEqual(offsets, [32, 32, 32, 32, 0, 0])
        XCTAssertEqual(layout.landingShift(origin: origin, slot: slot), -126)
    }

    func testTheSlotAboveTheFirstFolderIsTheEndOfUnfiled() {
        let slot = layout.dropSlot(origin: 0, translation: 32)
        XCTAssertEqual(slot, 1)
        let destination = layout.destination(origin: 0, slot: slot)
        XCTAssertNil(destination.folderID)
        XCTAssertNil(destination.beforeTaskID)
    }

    func testSmallMovesLandBackInPlace() {
        let origin = layout.index(ofTask: id("w1"))!
        let slot = layout.dropSlot(origin: origin, translation: 10)
        XCTAssertEqual(slot, 3)
        let destination = layout.destination(origin: origin, slot: slot)
        XCTAssertEqual(destination.folderID, work.id)
        XCTAssertEqual(destination.beforeTaskID, id("w2"))      // where it already was
        XCTAssertTrue(layout.items.indices.allSatisfy { layout.offset(ofItemAt: $0, origin: origin, slot: slot) == 0 })
        XCTAssertEqual(layout.landingShift(origin: origin, slot: slot), 0)
    }

    func testDropsMatchTheStoreResult() {
        // Dropping u1 under the Work header, then rebuilding the list, puts u1 exactly there.
        let store = AppStore(state: {
            var state = PersistedState()
            state.tasks = tasks
            state.folders = [work, home]
            return state
        }(), fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("layout-\(UUID()).json"))
        let destination = layout.destination(origin: 0, slot: 2)
        store.moveTask(id("u1"), toFolder: destination.folderID, before: destination.beforeTaskID)
        let rebuilt = TaskListLayout(tasks: store.tasks, folders: store.folders)
        XCTAssertEqual(names(rebuilt), ["u2", "[Work]", "u1", "w1", "w2", "[Home]"])
        XCTAssertEqual(rebuilt.index(ofTask: id("u1")), 2)
    }

    // MARK: Folder dragging

    func testFolderBlocksCoverEachHeaderAndItsVisibleTasks() {
        XCTAssertEqual(layout.folderBlocks, [2..<5, 5..<6])
        XCTAssertEqual(layout.folderIndex(of: work.id), 0)
        XCTAssertEqual(layout.folderIndex(of: home.id), 1)
        XCTAssertNil(layout.folderIndex(of: UUID()))
    }

    func testDraggingAnExpandedFolderBelowAnother() {
        // Work's block is its header plus two rows: 30 + 32 + 32 = 94 including gaps.
        XCTAssertEqual(layout.clampedFolderTranslation(500, origin: 0), 30)
        XCTAssertEqual(layout.clampedFolderTranslation(-500, origin: 0), 0)
        let slot = layout.folderDropSlot(origin: 0, translation: 40)
        XCTAssertEqual(slot, 1)

        // Home's header slides up by Work's whole block; unfiled tasks stay put.
        let offsets = layout.items.indices.map { layout.folderOffset(ofItemAt: $0, origin: 0, slot: slot) }
        XCTAssertEqual(offsets, [0, 0, 0, 0, 0, -94])
        XCTAssertEqual(layout.folderLandingShift(origin: 0, slot: slot), 30)
    }

    func testDraggingACollapsedFolderToTheTopOfTheFolders() {
        XCTAssertEqual(layout.clampedFolderTranslation(-500, origin: 1), -94)
        let slot = layout.folderDropSlot(origin: 1, translation: -100)
        XCTAssertEqual(slot, 0)

        // Work's header and rows slide down by Home's collapsed header (30).
        let offsets = layout.items.indices.map { layout.folderOffset(ofItemAt: $0, origin: 1, slot: slot) }
        XCTAssertEqual(offsets, [0, 0, 30, 30, 30, 0])
        XCTAssertEqual(layout.folderLandingShift(origin: 1, slot: slot), -94)

        // After the store applies it, Home's header sits exactly where it was dropped.
        var state = PersistedState()
        state.tasks = tasks
        state.folders = [work, home]
        let store = AppStore(state: state, fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("layout-\(UUID()).json"))
        store.moveFolder(home.id, to: slot)
        let rebuilt = TaskListLayout(tasks: store.tasks, folders: store.folders)
        XCTAssertEqual(names(rebuilt), ["u1", "u2", "[Home]", "[Work]", "w1", "w2"])
        XCTAssertEqual(TaskListLayout.tops(of: rebuilt.items)[2], 64)          // 158 + (-94)
    }

    func testASmallFolderDragLandsBackInPlace() {
        let slot = layout.folderDropSlot(origin: 0, translation: 8)
        XCTAssertEqual(slot, 0)
        XCTAssertTrue(layout.items.indices.allSatisfy { layout.folderOffset(ofItemAt: $0, origin: 0, slot: slot) == 0 })
        XCTAssertEqual(layout.folderLandingShift(origin: 0, slot: slot), 0)
    }

    func testTasksInMissingFoldersShowAsUnfiled() {
        let stray = TaskListLayout(tasks: [TodoItem(title: "x", folderID: UUID())], folders: [])
        XCTAssertEqual(names(stray), ["x"])
        guard case .task(let task) = stray.items[0] else { return XCTFail("expected a task") }
        XCTAssertNil(task.folderID)
    }
}
