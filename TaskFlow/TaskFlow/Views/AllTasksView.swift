import SwiftUI

struct AllTasksView: View {
    
    @State private var taskToDelete: TaskItem?
    @State private var showingDeleteConfirmation = false

    let tasks: [TaskItem]
    var dormantTaskIDs: Set<UUID> = []
    let onToggleCompletion: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void
    let onUpdate: (TaskItem) -> Void
    var onWake: (TaskItem) -> Void = { _ in }

    var body: some View {
        List(tasks) { task in
            NavigationLink {
                EditTaskView(task: task) { updatedTask in
                    onUpdate(updatedTask)
                }
            } label: {
                TaskRowView(
                    task: task,
                    note: dormantTaskIDs.contains(task.id)
                        ? "冬眠中（右へスワイプで起こす）"
                        : nil,
                    onToggleCompletion: {
                        onToggleCompletion(task)
                    }
                )
            }
            .swipeActions(edge: .leading) {
                if dormantTaskIDs.contains(task.id) {
                    Button {
                        onWake(task)
                    } label: {
                        Label("起こす", systemImage: "sun.max")
                    }
                    .tint(.orange)
                }
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    taskToDelete = task
                    showingDeleteConfirmation = true
                } label: {
                    Label("削除", systemImage: "trash")
                }
            }
        }
        .navigationTitle("すべてのタスク")
        .alert(
            "このタスクを削除しますか？",
            isPresented: $showingDeleteConfirmation,
            presenting: taskToDelete
        ) { task in
            Button("削除", role: .destructive) {
                onDelete(task)
                taskToDelete = nil
            }

            Button("キャンセル", role: .cancel) {
                taskToDelete = nil
            }
        } message: { task in
            Text("「\(task.title)」は元に戻せません。")
        }
    }
}

#Preview {
    NavigationStack {
        AllTasksView(
            tasks: [
                TaskItem(
                    title: "論文を読む",
                    estimatedMinutes: 30,
                    scheduledDate: Date()
                )
            ],
            onToggleCompletion: { _ in },
            onDelete: { _ in },
            onUpdate: { _ in }
        )
    }
}
