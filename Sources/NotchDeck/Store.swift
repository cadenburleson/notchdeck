import Foundation
import Combine

/// Single source of truth for user data. Persists to
/// ~/Library/Application Support/NotchDeck/state.json (debounced).
final class AppStore: ObservableObject {
    @Published var notes: String
    @Published var tasks: [TodoItem]
    @Published var folders: [TaskFolder]
    @Published var settings: AppSettings
    @Published var totalFocusSessions: Int

    private let fileURL: URL
    private var cancellables = Set<AnyCancellable>()

    init(state: PersistedState = PersistedState(), fileURL: URL = AppStore.defaultFileURL) {
        let folderIDs = Set(state.folders.map(\.id))
        self.notes = state.notes
        self.folders = state.folders
        // Tasks pointing at a folder that no longer exists become unfiled.
        self.tasks = state.tasks.map { task in
            var task = task
            if let id = task.folderID, !folderIDs.contains(id) { task.folderID = nil }
            return task
        }
        self.settings = state.settings
        self.totalFocusSessions = state.totalFocusSessions
        self.fileURL = fileURL

        objectWillChange
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.saveNow() }
            .store(in: &cancellables)
    }

    static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("NotchDeck", isDirectory: true).appendingPathComponent("state.json")
    }

    static func load(from url: URL = defaultFileURL) -> AppStore {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder.notchDeck.decode(PersistedState.self, from: data)
        else { return AppStore(fileURL: url) }
        return AppStore(state: state, fileURL: url)
    }

    var snapshot: PersistedState {
        var s = PersistedState()
        s.notes = notes
        s.tasks = tasks
        s.folders = folders
        s.settings = settings
        s.totalFocusSessions = totalFocusSessions
        return s
    }

    func saveNow() {
        do {
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder.notchDeck.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("NotchDeck: failed to save state: \(error)")
        }
    }

    // MARK: - Tasks

    var pendingTaskCount: Int { tasks.filter { !$0.isDone }.count }

    /// Adds a task at the top of the list, optionally into a folder (unfiled if the folder doesn't exist).
    func addTask(_ title: String, folderID: TaskFolder.ID? = nil) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tasks.insert(TodoItem(title: trimmed, folderID: folder(withID: folderID)?.id), at: 0)
    }

    func toggleTask(_ id: TodoItem.ID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].isDone.toggle()
    }

    func removeTask(_ id: TodoItem.ID) {
        tasks.removeAll { $0.id == id }
    }

    func clearCompletedTasks() {
        tasks.removeAll { $0.isDone }
    }

    /// Renames a task. The title is trimmed; an empty result leaves the task unchanged.
    func renameTask(_ id: TodoItem.ID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let i = tasks.firstIndex(where: { $0.id == id }),
              tasks[i].title != trimmed
        else { return }
        tasks[i].title = trimmed
    }

    /// Moves a task into `folderID` (nil = unfiled), placed just before `beforeID`
    /// when that task is in the same folder, otherwise at the end of the folder.
    /// Unknown tasks or folders are ignored.
    func moveTask(_ id: TodoItem.ID, toFolder folderID: TaskFolder.ID?, before beforeID: TodoItem.ID? = nil) {
        guard let from = tasks.firstIndex(where: { $0.id == id }), beforeID != id else { return }
        if folderID != nil, folder(withID: folderID) == nil { return }

        var reordered = tasks
        var item = reordered.remove(at: from)
        item.folderID = folderID
        if let beforeID, let i = reordered.firstIndex(where: { $0.id == beforeID }), reordered[i].folderID == folderID {
            reordered.insert(item, at: i)
        } else if let last = reordered.lastIndex(where: { $0.folderID == folderID }) {
            reordered.insert(item, at: last + 1)
        } else {
            reordered.append(item)
        }
        guard reordered != tasks else { return }
        tasks = reordered
    }

    // MARK: - Folders

    func folder(withID id: TaskFolder.ID?) -> TaskFolder? {
        guard let id else { return nil }
        return folders.first { $0.id == id }
    }

    /// The tasks in a folder, in list order; nil gives the unfiled tasks.
    func tasks(inFolder folderID: TaskFolder.ID?) -> [TodoItem] {
        tasks.filter { $0.folderID == folderID }
    }

    func pendingTaskCount(inFolder folderID: TaskFolder.ID?) -> Int {
        tasks(inFolder: folderID).filter { !$0.isDone }.count
    }

    /// The first palette color no folder uses yet; wraps around once all are taken.
    var nextFolderColor: FolderColor {
        let used = Set(folders.map(\.color))
        let palette = FolderColor.allCases
        return palette.first { !used.contains($0) } ?? palette[folders.count % palette.count]
    }

    @discardableResult
    func addFolder(_ name: String) -> TaskFolder? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let folder = TaskFolder(name: trimmed, color: nextFolderColor)
        folders.append(folder)
        return folder
    }

    /// Renames a folder. The name is trimmed; an empty result keeps the old name.
    func renameFolder(_ id: TaskFolder.ID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let i = folders.firstIndex(where: { $0.id == id }),
              folders[i].name != trimmed
        else { return }
        folders[i].name = trimmed
    }

    func setFolderColor(_ id: TaskFolder.ID, _ color: FolderColor) {
        guard let i = folders.firstIndex(where: { $0.id == id }), folders[i].color != color else { return }
        folders[i].color = color
    }

    func setFolderCollapsed(_ id: TaskFolder.ID, _ collapsed: Bool) {
        guard let i = folders.firstIndex(where: { $0.id == id }), folders[i].isCollapsed != collapsed else { return }
        folders[i].isCollapsed = collapsed
    }

    /// Moves a folder so it ends up at `destination` among the folders (clamped).
    func moveFolder(_ id: TaskFolder.ID, to destination: Int) {
        guard let from = folders.firstIndex(where: { $0.id == id }) else { return }
        let to = min(max(destination, 0), folders.count - 1)
        guard from != to else { return }
        var reordered = folders
        let folder = reordered.remove(at: from)
        reordered.insert(folder, at: to)
        folders = reordered
    }

    /// Deletes a folder. Its tasks are kept and become unfiled.
    func deleteFolder(_ id: TaskFolder.ID) {
        guard folders.contains(where: { $0.id == id }) else { return }
        folders.removeAll { $0.id == id }
        tasks = tasks.map { task in
            var task = task
            if task.folderID == id { task.folderID = nil }
            return task
        }
    }
}

extension JSONEncoder {
    static var notchDeck: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}

extension JSONDecoder {
    static var notchDeck: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
