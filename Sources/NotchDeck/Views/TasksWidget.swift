import SwiftUI
import AppKit

struct TasksWidget: View {
    @EnvironmentObject var store: AppStore
    @State private var draft = ""
    @FocusState private var inputFocused: Bool
    /// The folder new tasks go into, set from a folder header's "+"; nil = unfiled.
    @State private var addTarget: TaskFolder.ID?

    // Drag-to-reorder state. The dragged row follows the pointer; the lines it
    // passes slide out of the way. The store is only updated on drop.
    @State private var draggingID: TodoItem.ID?
    /// A folder being dragged by its header (its tasks move with it).
    @State private var draggingFolderID: TaskFolder.ID?
    @State private var dragTranslation: CGFloat = 0

    // Inline task rename: double-click a title. Return or clicking away saves,
    // Escape cancels.
    @State private var editingID: TodoItem.ID?
    @State private var editDraft = ""
    @FocusState private var focusedEditID: TodoItem.ID?

    // Folder editor: double-click a header. Return or Done closes it, Escape
    // discards the name (and removes a just-created folder that is still empty).
    @State private var editingFolderID: TaskFolder.ID?
    @State private var folderNameDraft = ""
    @FocusState private var focusedFolderID: TaskFolder.ID?
    @State private var newFolderID: TaskFolder.ID?

    static let folderIndent: CGFloat = 16
    private static let listSpace = "taskList"

    private struct DragPosition {
        let origin: Int
        let slot: Int
    }

    private struct FolderDragPosition {
        let origin: Int
        let slot: Int
        let block: Range<Int>
    }

    private var isAnyDragging: Bool { draggingID != nil || draggingFolderID != nil }

    private var layout: TaskListLayout { TaskListLayout(tasks: store.tasks, folders: store.folders) }

    var body: some View {
        let layout = self.layout
        let drag = currentDrag(in: layout)
        let folderDrag = currentFolderDrag(in: layout)
        VStack(spacing: 8) {
            inputField
            if layout.items.isEmpty {
                emptyState
            } else {
                list(layout, drag: drag, folderDrag: folderDrag)
            }
            footer
        }
        // Losing focus (clicking elsewhere, the panel closing) saves a task rename.
        .onChange(of: focusedEditID) { old, new in
            if let old, old == editingID, new != old { commitEdit() }
        }
        // Losing focus saves a folder name but keeps the editor open, so the
        // color swatches stay usable.
        .onChange(of: focusedFolderID) { old, new in
            if let old, old == editingFolderID, new != old { store.renameFolder(old, to: folderNameDraft) }
        }
        .onChange(of: store.folders) { _, folders in
            if let target = addTarget, !folders.contains(where: { $0.id == target }) { addTarget = nil }
        }
        .onDisappear {
            commitEdit()
            finishFolderEdit(save: true)
            endDrag(commit: false)
            endFolderDrag(commit: false)
            addTarget = nil
        }
    }

    // MARK: - Sections

    private var inputField: some View {
        let target = store.folder(withID: addTarget)
        return HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(target?.color.color ?? Theme.accent(for: .tasks))
            TextField(target.map { "Add a task to \($0.name)" } ?? "Add a task and press return", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .focused($inputFocused)
                .onSubmit(addTask)
            if let target {
                Button { addTarget = nil } label: {
                    HStack(spacing: 4) {
                        FolderDot(color: target.color.color, size: 7)
                        Text(target.name)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(target.color.color.opacity(0.2), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Add to no folder instead")
            }
            IconButton(symbol: "folder.badge.plus", help: "New folder", size: 12, action: createFolder)
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(height: 34)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 26, weight: .light))
            Text("Nothing to do. Nice.")
                .font(.system(size: 12))
        }
        .foregroundStyle(Theme.tertiaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func list(_ layout: TaskListLayout, drag: DragPosition?, folderDrag: FolderDragPosition?) -> some View {
        ScrollView {
            VStack(spacing: TaskListLayout.spacing) {
                ForEach(Array(layout.items.enumerated()), id: \.element.id) { index, item in
                    let isDragged = drag?.origin == index || folderDrag?.block.contains(index) == true
                    let offset: CGFloat = {
                        if isDragged { return dragTranslation }
                        if let drag { return layout.offset(ofItemAt: index, origin: drag.origin, slot: drag.slot) }
                        if let folderDrag {
                            return layout.folderOffset(ofItemAt: index, origin: folderDrag.origin, slot: folderDrag.slot)
                        }
                        return 0
                    }()
                    Group {
                        switch item {
                        case .task(let task):
                            taskRow(task, layout: layout, drag: drag, isDragged: drag?.origin == index)
                        case .header(let folder):
                            folderHeader(folder, isDragged: isDragged)
                        }
                    }
                    .offset(y: offset)
                    // Only the lines being pushed aside animate; the dragged row tracks the pointer 1:1.
                    .animation(isDragged ? nil : .spring(response: 0.25, dampingFraction: 0.86), value: offset)
                    .zIndex(isDragged ? 1 : 0)
                }
            }
            .coordinateSpace(name: Self.listSpace)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.never)
    }

    private var footer: some View {
        HStack {
            Text(store.pendingTaskCount == 1 ? "1 task left" : "\(store.pendingTaskCount) tasks left")
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

    // MARK: - Rows

    private func taskRow(_ task: TodoItem, layout: TaskListLayout, drag: DragPosition?, isDragged: Bool) -> some View {
        let isEditing = editingID == task.id
        // A dragged row takes the indentation of wherever it would land.
        let inFolder: Bool = {
            if isDragged, let drag {
                return layout.destination(origin: drag.origin, slot: drag.slot).folderID != nil
            }
            return task.folderID != nil
        }()
        return TaskRow(task: task,
                       isDragged: isDragged,
                       isAnyDragging: isAnyDragging,
                       isEditing: isEditing,
                       editDraft: $editDraft,
                       editFocus: $focusedEditID,
                       toggle: { withAnimation(.easeOut(duration: 0.18)) { store.toggleTask(task.id) } },
                       remove: { withAnimation(.easeOut(duration: 0.18)) { store.removeTask(task.id) } },
                       beginEdit: { beginEdit(task) },
                       commitEdit: commitEdit,
                       cancelEdit: cancelEdit)
            .padding(.leading, inFolder ? Self.folderIndent : 0)
            .animation(.easeOut(duration: 0.15), value: inFolder)
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.listSpace))
                    .onChanged { value in
                        if draggingID != task.id { startDrag(task.id) }
                        let layout = self.layout
                        guard let origin = layout.index(ofTask: task.id) else { return }
                        dragTranslation = layout.clampedTranslation(value.translation.height, origin: origin)
                    }
                    .onEnded { _ in endDrag(commit: true) },
                // While renaming, mouse drags select text instead of moving the row.
                including: isEditing ? .subviews : .all
            )
    }

    private func folderHeader(_ folder: TaskFolder, isDragged: Bool) -> some View {
        let isEditing = editingFolderID == folder.id
        return FolderHeader(folder: folder,
                     pendingCount: store.pendingTaskCount(inFolder: folder.id),
                     isEditing: isEditing,
                     isDragged: isDragged,
                     isAnyDragging: isAnyDragging,
                     nameDraft: $folderNameDraft,
                     nameFocus: $focusedFolderID,
                     toggleCollapsed: {
                         withAnimation(.easeOut(duration: 0.2)) { store.setFolderCollapsed(folder.id, !folder.isCollapsed) }
                     },
                     addTask: { aimInput(at: folder) },
                     beginEdit: { beginFolderEdit(folder) },
                     finishEdit: { finishFolderEdit(save: $0) },
                     setColor: { store.setFolderColor(folder.id, $0) },
                     delete: { deleteFolder(folder) })
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.listSpace))
                    .onChanged { value in
                        if draggingFolderID != folder.id { startFolderDrag(folder.id) }
                        let layout = self.layout
                        guard let origin = layout.folderIndex(of: folder.id) else { return }
                        dragTranslation = layout.clampedFolderTranslation(value.translation.height, origin: origin)
                    }
                    .onEnded { _ in endFolderDrag(commit: true) },
                // While renaming, mouse drags select text instead of moving the folder.
                including: isEditing ? .subviews : .all
            )
    }

    // MARK: - Adding

    private func addTask() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let target = store.folder(withID: addTarget)
        withAnimation(.easeOut(duration: 0.18)) {
            store.addTask(draft, folderID: target?.id)
            if let target, target.isCollapsed { store.setFolderCollapsed(target.id, false) }
        }
        draft = ""
    }

    private func aimInput(at folder: TaskFolder) {
        addTarget = folder.id
        NotchPanel.makeKeyForTyping()
        DispatchQueue.main.async { inputFocused = true }
    }

    // MARK: - Folders

    private func createFolder() {
        commitEdit()
        finishFolderEdit(save: true)
        guard let folder = withAnimation(.easeOut(duration: 0.18), { store.addFolder("New folder") }) else { return }
        newFolderID = folder.id
        beginFolderEdit(folder)
    }

    private func beginFolderEdit(_ folder: TaskFolder) {
        guard !isAnyDragging, editingFolderID != folder.id else { return }
        commitEdit()
        finishFolderEdit(save: true)
        editingFolderID = folder.id
        // A brand-new folder starts with an empty field; its placeholder says what to type.
        folderNameDraft = folder.id == newFolderID ? "" : folder.name
        NotchPanel.makeKeyForTyping()
        DispatchQueue.main.async {
            if editingFolderID == folder.id { focusedFolderID = folder.id }
        }
    }

    private func finishFolderEdit(save: Bool) {
        guard let id = editingFolderID else { return }
        editingFolderID = nil
        if save {
            store.renameFolder(id, to: folderNameDraft)
        } else if id == newFolderID, store.tasks(inFolder: id).isEmpty {
            withAnimation(.easeOut(duration: 0.18)) { store.deleteFolder(id) }
        }
        newFolderID = nil
        folderNameDraft = ""
        if focusedFolderID == id { focusedFolderID = nil }
    }

    private func deleteFolder(_ folder: TaskFolder) {
        if editingFolderID == folder.id {
            editingFolderID = nil
            newFolderID = nil
            folderNameDraft = ""
            focusedFolderID = nil
        }
        withAnimation(.easeOut(duration: 0.2)) { store.deleteFolder(folder.id) }
    }

    // MARK: - Rename

    private func beginEdit(_ task: TodoItem) {
        guard !isAnyDragging, editingID != task.id else { return }
        commitEdit()
        finishFolderEdit(save: true)
        editDraft = task.title
        editingID = task.id
        NotchPanel.makeKeyForTyping()
        DispatchQueue.main.async {
            if editingID == task.id { focusedEditID = task.id }
        }
    }

    private func commitEdit() {
        guard let id = editingID else { return }
        editingID = nil
        store.renameTask(id, to: editDraft)
        if focusedEditID == id { focusedEditID = nil }
    }

    private func cancelEdit() {
        guard let id = editingID else { return }
        editingID = nil
        if focusedEditID == id { focusedEditID = nil }
    }

    // MARK: - Dragging

    private func currentDrag(in layout: TaskListLayout) -> DragPosition? {
        guard let id = draggingID, let origin = layout.index(ofTask: id) else { return nil }
        return DragPosition(origin: origin, slot: layout.dropSlot(origin: origin, translation: dragTranslation))
    }

    private func startDrag(_ id: TodoItem.ID) {
        commitEdit()
        finishFolderEdit(save: true)
        draggingID = id
        dragTranslation = 0
    }

    private func currentFolderDrag(in layout: TaskListLayout) -> FolderDragPosition? {
        guard let id = draggingFolderID, let origin = layout.folderIndex(of: id) else { return nil }
        return FolderDragPosition(origin: origin,
                                  slot: layout.folderDropSlot(origin: origin, translation: dragTranslation),
                                  block: layout.folderBlocks[origin])
    }

    private func startFolderDrag(_ id: TaskFolder.ID) {
        commitEdit()
        finishFolderEdit(save: true)
        draggingFolderID = id
        dragTranslation = 0
    }

    /// Same landing as a task drag: reorder instantly, keep the leftover distance, then settle.
    private func endFolderDrag(commit: Bool) {
        guard let id = draggingFolderID else { return }
        let layout = self.layout
        guard commit, let origin = layout.folderIndex(of: id) else {
            draggingFolderID = nil
            dragTranslation = 0
            return
        }
        let slot = layout.folderDropSlot(origin: origin, translation: dragTranslation)
        let shift = layout.folderLandingShift(origin: origin, slot: slot)
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            store.moveFolder(id, to: slot)
            dragTranslation -= shift
        }
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                dragTranslation = 0
            } completion: {
                if draggingFolderID == id { draggingFolderID = nil }
            }
        }
    }

    private func endDrag(commit: Bool) {
        guard let id = draggingID else { return }
        let layout = self.layout
        guard commit, let origin = layout.index(ofTask: id) else {
            draggingID = nil
            dragTranslation = 0
            return
        }
        let slot = layout.dropSlot(origin: origin, translation: dragTranslation)
        let destination = layout.destination(origin: origin, slot: slot)

        // Dropped onto a collapsed folder: the row files away out of sight.
        if store.folder(withID: destination.folderID)?.isCollapsed == true {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                store.moveTask(id, toFolder: destination.folderID, before: destination.beforeTaskID)
                draggingID = nil
                dragTranslation = 0
            }
            return
        }

        // Reorder without animation. The lines that were pushed aside already sit
        // at their new places, so they don't move; the dragged row keeps only the
        // leftover distance to its slot...
        let shift = layout.landingShift(origin: origin, slot: slot)
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            store.moveTask(id, toFolder: destination.folderID, before: destination.beforeTaskID)
            dragTranslation -= shift
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
}

struct TaskRow: View {
    let task: TodoItem
    let isDragged: Bool
    let isAnyDragging: Bool
    let isEditing: Bool
    @Binding var editDraft: String
    var editFocus: FocusState<TodoItem.ID?>.Binding
    let toggle: () -> Void
    let remove: () -> Void
    let beginEdit: () -> Void
    let commitEdit: () -> Void
    let cancelEdit: () -> Void
    @State private var hovering = false

    private var highlighted: Bool { isDragged || (hovering && !isAnyDragging) }
    private var showsControls: Bool { hovering && !isAnyDragging && !isEditing }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: toggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(task.isDone ? Theme.accent(for: .tasks) : Theme.secondaryText)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .focusable(false)

            if isEditing {
                TextField("Task", text: $editDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .focused(editFocus, equals: task.id)
                    .onSubmit(commitEdit)
                    .onExitCommand(perform: cancelEdit)
            } else {
                Text(task.title)
                    .font(.system(size: 13))
                    .foregroundStyle(task.isDone ? Theme.tertiaryText : Theme.text)
                    .strikethrough(task.isDone, color: Theme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // The whole width right of the checkbox responds to a double-click.
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2, perform: beginEdit)
            }

            if showsControls || (isDragged && !isEditing) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.tertiaryText)
                    .help("Drag to reorder or move between folders")
                    .transition(.opacity)
            }
            if showsControls {
                IconButton(symbol: "xmark", help: "Delete", size: 10, action: remove)
                    .transition(.opacity)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: TaskListLayout.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isDragged ? Theme.surfaceHover : (highlighted || isEditing ? Theme.surface : .clear))
                .overlay {
                    if isDragged || isEditing {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isEditing ? Theme.accent(for: .tasks).opacity(0.45) : Color.white.opacity(0.1),
                                          lineWidth: 1)
                    }
                }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
