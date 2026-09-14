import Foundation

struct TodoItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var isDone: Bool = false
    var createdAt: Date = Date()
}

struct PomodoroSettings: Codable, Equatable {
    var focusMinutes: Int = 25
    var shortBreakMinutes: Int = 5
    var longBreakMinutes: Int = 15
    var sessionsBeforeLongBreak: Int = 4
    var autoStartNext: Bool = false
    var playSound: Bool = true
}

/// Where the panel lives on screen.
enum NotchEdge: String, Codable, CaseIterable, Identifiable {
    case top, left, right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .top: return "Top (notch)"
        case .left: return "Left edge"
        case .right: return "Right edge"
        }
    }

    var symbol: String {
        switch self {
        case .top: return "rectangle.topthird.inset.filled"
        case .left: return "rectangle.leadinghalf.inset.filled"
        case .right: return "rectangle.trailinghalf.inset.filled"
        }
    }

    var isSide: Bool { self != .top }
}

struct AppSettings: Codable, Equatable {
    var pomodoro = PomodoroSettings()
    var showTaskCountInNotch: Bool = true
    var showTimerInNotch: Bool = true
    var openOnHover: Bool = true
    var edge: NotchEdge = .top
    /// 0...1 position along a side edge (0 = top of screen, 1 = bottom). Ignored for `.top`.
    var edgeOffset: Double = 0.5
    /// Seconds for the panel to open / close.
    var openDuration: Double = AppSettings.defaultOpenDuration
    var closeDuration: Double = AppSettings.defaultCloseDuration

    static let defaultOpenDuration = 0.32
    static let defaultCloseDuration = 0.30
    static let durationRange = 0.1...1.0

    // Tolerate missing keys when the schema grows.
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pomodoro = try c.decodeIfPresent(PomodoroSettings.self, forKey: .pomodoro) ?? PomodoroSettings()
        showTaskCountInNotch = try c.decodeIfPresent(Bool.self, forKey: .showTaskCountInNotch) ?? true
        showTimerInNotch = try c.decodeIfPresent(Bool.self, forKey: .showTimerInNotch) ?? true
        openOnHover = try c.decodeIfPresent(Bool.self, forKey: .openOnHover) ?? true
        edge = try c.decodeIfPresent(NotchEdge.self, forKey: .edge) ?? .top
        edgeOffset = try c.decodeIfPresent(Double.self, forKey: .edgeOffset) ?? 0.5
        openDuration = try c.decodeIfPresent(Double.self, forKey: .openDuration) ?? AppSettings.defaultOpenDuration
        closeDuration = try c.decodeIfPresent(Double.self, forKey: .closeDuration) ?? AppSettings.defaultCloseDuration
    }
}

struct PersistedState: Codable {
    var notes: String = ""
    var tasks: [TodoItem] = []
    var settings = AppSettings()
    var totalFocusSessions: Int = 0

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        tasks = try c.decodeIfPresent([TodoItem].self, forKey: .tasks) ?? []
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        totalFocusSessions = try c.decodeIfPresent(Int.self, forKey: .totalFocusSessions) ?? 0
    }
}

enum NotchTab: String, CaseIterable, Identifiable {
    case notes, tasks, pomodoro

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notes: return "Notes"
        case .tasks: return "Tasks"
        case .pomodoro: return "Pomodoro"
        }
    }

    var symbol: String {
        switch self {
        case .notes: return "note.text"
        case .tasks: return "checklist"
        case .pomodoro: return "timer"
        }
    }
}
