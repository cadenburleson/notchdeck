import Foundation
import Combine

/// Single source of truth for user data. Persists to
/// ~/Library/Application Support/NotchDeck/state.json (debounced).
final class AppStore: ObservableObject {
    @Published var notes: String
    @Published var tasks: [TodoItem]
    @Published var settings: AppSettings
    @Published var totalFocusSessions: Int

    private let fileURL: URL
    private var cancellables = Set<AnyCancellable>()

    init(state: PersistedState = PersistedState(), fileURL: URL = AppStore.defaultFileURL) {
        self.notes = state.notes
        self.tasks = state.tasks
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

    func addTask(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tasks.insert(TodoItem(title: trimmed), at: 0)
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
