import CoreGraphics
import Foundation

/// One line of the task list: a task row or a folder header.
enum TaskListItem: Identifiable, Equatable {
    case task(TodoItem)
    case header(TaskFolder)

    var id: String {
        switch self {
        case .task(let task): return "task-\(task.id.uuidString)"
        case .header(let folder): return "folder-\(folder.id.uuidString)"
        }
    }

    var height: CGFloat {
        switch self {
        case .task: return TaskListLayout.rowHeight
        case .header: return TaskListLayout.headerHeight
        }
    }

    var taskID: UUID? {
        if case .task(let task) = self { return task.id }
        return nil
    }
}

/// The task list flattened into rows, plus the geometry for dragging a task
/// through it. Pure value logic so it can be unit-tested; the view only renders it.
struct TaskListLayout {
    static let rowHeight: CGFloat = 30
    static let headerHeight: CGFloat = 28
    static let spacing: CGFloat = 2
    /// The space one task row takes, which is the gap other lines open for it.
    static var rowPitch: CGFloat { rowHeight + spacing }

    let items: [TaskListItem]

    init(items: [TaskListItem]) {
        self.items = items
    }

    /// Unfiled tasks first, then each folder's header followed by its tasks
    /// (none while collapsed). Tasks keep their order from `tasks`.
    init(tasks: [TodoItem], folders: [TaskFolder]) {
        let folderIDs = Set(folders.map(\.id))
        var items: [TaskListItem] = tasks.compactMap { task in
            guard let id = task.folderID else { return .task(task) }
            guard !folderIDs.contains(id) else { return nil }
            var unfiled = task
            unfiled.folderID = nil
            return .task(unfiled)
        }
        for folder in folders {
            items.append(.header(folder))
            if !folder.isCollapsed {
                items += tasks.filter { $0.folderID == folder.id }.map(TaskListItem.task)
            }
        }
        self.items = items
    }

    func index(ofTask id: UUID) -> Int? {
        items.firstIndex { $0.taskID == id }
    }

    /// The top edge of each item, measured from the top of the first one.
    static func tops(of items: [TaskListItem]) -> [CGFloat] {
        var tops: [CGFloat] = []
        var y: CGFloat = 0
        for item in items {
            tops.append(y)
            y += item.height + spacing
        }
        return tops
    }

    // MARK: - Dragging the task at `origin`

    /// Every item except the dragged one.
    private func others(excluding origin: Int) -> [TaskListItem] {
        var rest = items
        rest.remove(at: origin)
        return rest
    }

    /// Where the dragged row's top would sit for each drop slot. Slot `s` means
    /// "just before the s-th of the other items"; the last slot is the very end.
    private func slotTops(excluding origin: Int) -> [CGFloat] {
        let rest = others(excluding: origin)
        let tops = Self.tops(of: rest)
        var slots: [CGFloat] = [0]
        for index in rest.indices {
            let bottom: CGFloat = tops[index] + rest[index].height
            slots.append(bottom + Self.spacing)
        }
        return slots
    }

    /// Keeps the dragged row between the first and last drop slots.
    func clampedTranslation(_ translation: CGFloat, origin: Int) -> CGFloat {
        let slots = slotTops(excluding: origin)
        let originTop = Self.tops(of: items)[origin]
        return min(max(translation, slots[0] - originTop), slots[slots.count - 1] - originTop)
    }

    /// The drop slot nearest to where the dragged row currently is.
    func dropSlot(origin: Int, translation: CGFloat) -> Int {
        let slots = slotTops(excluding: origin)
        let target = Self.tops(of: items)[origin] + translation
        var best = 0
        for (slot, top) in slots.enumerated() where abs(top - target) < abs(slots[best] - target) {
            best = slot
        }
        return best
    }

    /// How far a non-dragged item slides to open the gap at `slot`.
    func offset(ofItemAt index: Int, origin: Int, slot: Int) -> CGFloat {
        guard index != origin else { return 0 }
        let j = index < origin ? index : index - 1
        if slot <= j && j < origin { return Self.rowPitch }
        if origin <= j && j < slot { return -Self.rowPitch }
        return 0
    }

    /// How far the dragged row's resting position moves when it lands in `slot`.
    func landingShift(origin: Int, slot: Int) -> CGFloat {
        slotTops(excluding: origin)[slot] - Self.tops(of: items)[origin]
    }

    // MARK: - Dragging a whole folder

    /// Each folder's block of lines (its header plus its visible tasks), in folder order.
    var folderBlocks: [Range<Int>] {
        let headers = items.indices.filter { index in
            if case .header = items[index] { return true }
            return false
        }
        return headers.indices.map { n in
            let end = n + 1 < headers.count ? headers[n + 1] : items.count
            return headers[n]..<end
        }
    }

    /// The position of a folder among the folders.
    func folderIndex(of id: UUID) -> Int? {
        folderBlocks.firstIndex { block in
            if case .header(let folder) = items[block.lowerBound] { return folder.id == id }
            return false
        }
    }

    /// The space a block takes, including the gap after it.
    private func pitch(of block: Range<Int>) -> CGFloat {
        var total: CGFloat = 0
        for index in block { total += items[index].height + Self.spacing }
        return total
    }

    /// Where the dragged folder's header would sit for each final folder position.
    private func folderSlotTops(excluding origin: Int) -> [CGFloat] {
        let blocks = folderBlocks
        var slots: [CGFloat] = [Self.tops(of: items)[blocks[0].lowerBound]]
        for (n, block) in blocks.enumerated() where n != origin {
            slots.append(slots[slots.count - 1] + pitch(of: block))
        }
        return slots
    }

    private func folderTop(_ origin: Int) -> CGFloat {
        Self.tops(of: items)[folderBlocks[origin].lowerBound]
    }

    func clampedFolderTranslation(_ translation: CGFloat, origin: Int) -> CGFloat {
        let slots = folderSlotTops(excluding: origin)
        let top = folderTop(origin)
        return min(max(translation, slots[0] - top), slots[slots.count - 1] - top)
    }

    /// The folder position nearest to where the dragged folder currently is.
    func folderDropSlot(origin: Int, translation: CGFloat) -> Int {
        let slots = folderSlotTops(excluding: origin)
        let target = folderTop(origin) + translation
        var best = 0
        for (slot, top) in slots.enumerated() where abs(top - target) < abs(slots[best] - target) {
            best = slot
        }
        return best
    }

    /// How far a line outside the dragged folder slides to make room at `slot`.
    /// Unfiled tasks never move.
    func folderOffset(ofItemAt index: Int, origin: Int, slot: Int) -> CGFloat {
        let blocks = folderBlocks
        guard let block = blocks.firstIndex(where: { $0.contains(index) }), block != origin else { return 0 }
        let j = block < origin ? block : block - 1
        let gap = pitch(of: blocks[origin])
        if slot <= j && j < origin { return gap }
        if origin <= j && j < slot { return -gap }
        return 0
    }

    func folderLandingShift(origin: Int, slot: Int) -> CGFloat {
        folderSlotTops(excluding: origin)[slot] - folderTop(origin)
    }

    /// The folder a drop into `slot` files the task under, and the task it lands
    /// in front of (nil = the end of that folder).
    func destination(origin: Int, slot: Int) -> (folderID: UUID?, beforeTaskID: UUID?) {
        let rest = others(excluding: origin)
        let folderID: UUID?
        if slot > 0 {
            switch rest[slot - 1] {
            case .header(let folder): folderID = folder.id
            case .task(let task): folderID = task.folderID
            }
        } else {
            folderID = nil
        }
        if slot < rest.count, case .task(let next) = rest[slot], next.folderID == folderID {
            return (folderID, next.id)
        }
        return (folderID, nil)
    }
}
