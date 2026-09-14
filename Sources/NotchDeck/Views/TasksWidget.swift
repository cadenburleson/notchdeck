import SwiftUI

struct TasksWidget: View {
    @EnvironmentObject var store: AppStore
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    // Drag-to-reorder state. The dragged row follows the pointer; the rows it
    // passes slide one slot out of the way. The store is only updated on drop.
    @State private var draggingID: TodoItem.ID?
    @State private var dragTranslation: CGFloat = 0

    static let rowHeight: CGFloat = 30
    static let rowSpacing: CGFloat = 2
    private var pitch: CGFloat { Self.rowHeight + Self.rowSpacing }
    private static let listSpace = "taskList"

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.accent(for: .tasks))
                TextField("Add a task and press return", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .focused($inputFocused)
                    .onSubmit {
                        withAnimation(.easeOut(duration: 0.18)) { store.addTask(draft) }
                        draft = ""
                    }
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            if store.tasks.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 26, weight: .light))
                    Text("Nothing to do. Nice.")
                        .font(.system(size: 12))
                }
                .foregroundStyle(Theme.tertiaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: Self.rowSpacing) {
                        ForEach(Array(store.tasks.enumerated()), id: \.element.id) { index, task in
                            row(task, at: index)
                        }
                    }
                    .coordinateSpace(name: Self.listSpace)
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.never)
            }

            HStack {
                Text(footerLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiaryText)
                Spacer()
                if store.tasks.contains(where: \.isDone) {
                    PillButton(title: "Clear done", symbol: "checkmark", tint: Theme.secondaryText) {
                        withAnimation(.easeOut(duration: 0.18)) { store.clearCompletedTasks() }
                    }
                }
            }
        }
        .onDisappear { endDrag(commit: false) }
    }

    // MARK: - Rows

    private func row(_ task: TodoItem, at index: Int) -> some View {
        let isDragged = draggingID == task.id
        let offset = rowOffset(for: task.id, at: index)
        return TaskRow(task: task,
                       isDragged: isDragged,
                       isAnyDragging: draggingID != nil,
                       toggle: { withAnimation(.easeOut(duration: 0.18)) { store.toggleTask(task.id) } },
                       remove: { withAnimation(.easeOut(duration: 0.18)) { store.removeTask(task.id) } })
            .offset(y: offset)
            // Only the rows being pushed aside animate; the dragged row tracks the pointer 1:1.
            .animation(isDragged ? nil : .spring(response: 0.25, dampingFraction: 0.86), value: offset)
            .zIndex(isDragged ? 1 : 0)
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.listSpace))
                    .onChanged { value in
                        if draggingID != task.id { draggingID = task.id }
                        dragTranslation = clampedTranslation(value.translation.height, from: index)
                    }
                    .onEnded { _ in endDrag(commit: true) }
            )
    }

    // MARK: - Drag math

    private var dragOrigin: Int? {
        guard let draggingID else { return nil }
        return store.tasks.firstIndex { $0.id == draggingID }
    }

    /// The slot the dragged row would land in if dropped now.
    private func dropIndex(from origin: Int) -> Int {
        let shift = Int((dragTranslation / pitch).rounded())
        return min(max(origin + shift, 0), store.tasks.count - 1)
    }

    /// Keeps the dragged row within the list.
    private func clampedTranslation(_ y: CGFloat, from origin: Int) -> CGFloat {
        let up = -CGFloat(origin) * pitch
        let down = CGFloat(store.tasks.count - 1 - origin) * pitch
        return min(max(y, up), down)
    }

    private func rowOffset(for id: TodoItem.ID, at index: Int) -> CGFloat {
        guard let origin = dragOrigin else { return 0 }
        if id == draggingID { return dragTranslation }
        let target = dropIndex(from: origin)
        if origin < target, index > origin, index <= target { return -pitch }
        if origin > target, index >= target, index < origin { return pitch }
        return 0
    }

    private func endDrag(commit: Bool) {
        guard let id = draggingID else { return }
        guard commit, let origin = dragOrigin else {
            draggingID = nil
            dragTranslation = 0
            return
        }
        let target = dropIndex(from: origin)

        // Reorder without animation. The rows that were pushed aside already sit
        // at their new slots, so they don't move; the dragged row keeps only the
        // leftover distance to its slot...
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            store.moveTask(id, to: target)
            dragTranslation -= CGFloat(target - origin) * pitch
        }
        // ...which then settles on the next frame.
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                dragTranslation = 0
            } completion: {
                if draggingID == id { draggingID = nil }
            }
        }
    }

    private var footerLabel: String {
        let left = store.pendingTaskCount
        return left == 1 ? "1 task left" : "\(left) tasks left"
    }
}

private struct TaskRow: View {
    let task: TodoItem
    let isDragged: Bool
    let isAnyDragging: Bool
    let toggle: () -> Void
    let remove: () -> Void
    @State private var hovering = false

    private var highlighted: Bool { isDragged || (hovering && !isAnyDragging) }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: toggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(task.isDone ? Theme.accent(for: .tasks) : Theme.secondaryText)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            Text(task.title)
                .font(.system(size: 13))
                .foregroundStyle(task.isDone ? Theme.tertiaryText : Theme.text)
                .strikethrough(task.isDone, color: Theme.tertiaryText)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            if highlighted {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.tertiaryText)
                    .help("Drag to reorder")
                    .transition(.opacity)
            }
            if hovering && !isAnyDragging {
                IconButton(symbol: "xmark", help: "Delete", size: 10, action: remove)
                    .transition(.opacity)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: TasksWidget.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isDragged ? Theme.surfaceHover : (highlighted ? Theme.surface : .clear))
                .overlay {
                    if isDragged {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    }
                }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
