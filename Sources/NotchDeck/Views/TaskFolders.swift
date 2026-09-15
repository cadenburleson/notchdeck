import SwiftUI

struct FolderDot: View {
    let color: Color
    var size: CGFloat = 8

    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

/// A folder's section header. Drag it to reorder folders, the chevron collapses
/// it, "+" (on hover) aims the add field at it, double-clicking opens the
/// rename / color / delete editor, and right-clicking offers the same actions.
struct FolderHeader: View {
    let folder: TaskFolder
    let pendingCount: Int
    let isEditing: Bool
    let isDragged: Bool
    let isAnyDragging: Bool
    @Binding var nameDraft: String
    var nameFocus: FocusState<TaskFolder.ID?>.Binding
    let toggleCollapsed: () -> Void
    let addTask: () -> Void
    let beginEdit: () -> Void
    /// Closes the editor; `true` saves the name, `false` discards it.
    let finishEdit: (Bool) -> Void
    let setColor: (FolderColor) -> Void
    let delete: () -> Void
    @State private var hovering = false

    var body: some View {
        Group {
            if isEditing {
                editor
            } else {
                label
            }
        }
        .frame(height: TaskListLayout.headerHeight)
        .onHover { hovering = $0 }
    }

    private var label: some View {
        HStack(spacing: 4) {
            Button(action: toggleCollapsed) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.tertiaryText)
                    .rotationEffect(.degrees(folder.isCollapsed ? 0 : 90))
                    .frame(width: 18, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(folder.isCollapsed ? "Expand" : "Collapse")

            HStack(spacing: 7) {
                FolderDot(color: folder.color.color, size: 8)
                Text(folder.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                if pendingCount > 0 {
                    Text("\(pendingCount)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(folder.color.color)
                        .padding(.horizontal, 6)
                        .frame(height: 16)
                        .background(folder.color.color.opacity(0.16), in: Capsule())
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: beginEdit)

            if hovering && !isAnyDragging {
                IconButton(symbol: "plus", help: "Add a task to \(folder.name)", size: 10, action: addTask)
                    .transition(.opacity)
            }
            if (hovering && !isAnyDragging) || isDragged {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(width: 22)
                    .help("Drag to reorder folders")
                    .transition(.opacity)
            }
        }
        .padding(.trailing, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Add Task to \(folder.name)", action: addTask)
            Button("Rename…", action: beginEdit)
            Picker("Color", selection: Binding(get: { folder.color }, set: setColor)) {
                ForEach(FolderColor.allCases) { color in
                    Text(color.title).tag(color)
                }
            }
            .pickerStyle(.menu)
            Button(folder.isCollapsed ? "Expand" : "Collapse", action: toggleCollapsed)
            Divider()
            Button("Delete Folder", role: .destructive, action: delete)
        }
        .background {
            if isDragged {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.surfaceHover)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
            }
        }
    }

    private var editor: some View {
        HStack(spacing: 8) {
            FolderDot(color: folder.color.color, size: 9)
            TextField("Folder name", text: $nameDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.text)
                .focused(nameFocus, equals: folder.id)
                .onSubmit { finishEdit(true) }
                .onExitCommand { finishEdit(false) }
                .frame(maxWidth: .infinity)
            HStack(spacing: 2) {
                ForEach(FolderColor.allCases) { color in
                    Button { setColor(color) } label: {
                        Circle()
                            .fill(color.color)
                            .frame(width: 12, height: 12)
                            .padding(2)
                            .overlay(Circle().strokeBorder(color == folder.color ? Theme.text : .clear, lineWidth: 1.5))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help(color.title)
                }
            }
            IconButton(symbol: "trash", help: "Delete folder (its tasks are kept)", size: 11, action: delete)
            IconButton(symbol: "checkmark", help: "Done", tint: Theme.text, size: 11) { finishEdit(true) }
        }
        .padding(.leading, 9)
        .padding(.trailing, 2)
        .background(Theme.surface, in: Capsule())
    }
}
