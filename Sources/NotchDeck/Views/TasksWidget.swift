import SwiftUI

struct TasksWidget: View {
    @EnvironmentObject var store: AppStore
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

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
                        store.addTask(draft)
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
                    LazyVStack(spacing: 2) {
                        ForEach(store.tasks) { task in
                            TaskRow(task: task,
                                    toggle: { store.toggleTask(task.id) },
                                    remove: { store.removeTask(task.id) })
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.never)
                .animation(.easeOut(duration: 0.18), value: store.tasks)
            }

            HStack {
                Text(footerLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiaryText)
                Spacer()
                if store.tasks.contains(where: \.isDone) {
                    PillButton(title: "Clear done", symbol: "checkmark", tint: Theme.secondaryText) {
                        store.clearCompletedTasks()
                    }
                }
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
    let toggle: () -> Void
    let remove: () -> Void
    @State private var hovering = false

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

            if hovering {
                IconButton(symbol: "xmark", help: "Delete", size: 10, action: remove)
                    .transition(.opacity)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: 30)
        .background(hovering ? Theme.surface : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
