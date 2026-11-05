import SwiftUI

struct TaskRowView: View {

    let task: TaskItem

    /// 所要時間の横に添える補足（「持ち越し」「冬眠中」など）
    let note: String?
    let onToggleCompletion: () -> Void

    init(
        task: TaskItem,
        note: String? = nil,
        onToggleCompletion: @escaping () -> Void = {}
    ) {
        self.task = task
        self.note = note
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
                .font(.title3)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "「\(task.title)」を未完了に戻す" : "「\(task.title)」を完了にする")

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .strikethrough(task.isCompleted)

                HStack(spacing: 8) {
                    Text("所要時間：\(task.estimatedMinutes)分")

                    if let note {
                        Text(note)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

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
