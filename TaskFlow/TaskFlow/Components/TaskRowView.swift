import SwiftUI

struct TaskRowView: View {

    let task: TaskItem
    let onToggleCompletion: () -> Void
    
    init(
        task: TaskItem,
        onToggleCompletion: @escaping () -> Void = {}
    ) {
        self.task = task
        self.onToggleCompletion = onToggleCompletion
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onToggleCompletion()
            } label: {
                Image(
                    systemName: task.isCompleted
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                .foregroundStyle(
                    task.isCompleted ? .green : .secondary
                )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .strikethrough(task.isCompleted)

                Text("所要時間：\(task.estimatedMinutes)分")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    TaskRowView(
        task: TaskItem(
            title: "論文を読む",
            estimatedMinutes: 30,
            scheduledDate: Date()
        )
    )
}
