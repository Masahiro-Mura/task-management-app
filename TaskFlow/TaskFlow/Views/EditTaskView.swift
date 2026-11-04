import SwiftUI

struct EditTaskView: View {
    
    @Environment(\.dismiss) private var dismiss

    let task: TaskItem
    let onSave: (TaskItem) -> Void
    
    @State private var title: String
    @State private var estimatedMinutes: Int
    @State private var priority: TaskPriority
    @State private var scheduledDate: Date
    @State private var hasScheduledDate: Bool
    @State private var deadline: Date
    @State private var hasDeadline: Bool
    
    init(
        task: TaskItem,
        onSave: @escaping (TaskItem) -> Void = { _ in }
    ) {
        self.task = task
        self.onSave = onSave
        
        _title = State(
            initialValue: task.title
        )
        _estimatedMinutes = State(
            initialValue: task.estimatedMinutes
        )
        _priority = State(
            initialValue: task.priority
        )
        _scheduledDate = State(
            initialValue: task.scheduledDate ?? Date()
        )
        _hasScheduledDate = State(
            initialValue: task.scheduledDate != nil
        )
        _deadline = State(
            initialValue: task.deadline ?? Date()
        )

        _hasDeadline = State(
            initialValue: task.deadline != nil
        )
    }

    var body: some View {
        Form {
            Section("タスク情報") {
                TextField("タスク名", text: $title)

                Stepper(
                    "所要時間：\(estimatedMinutes)分",
                    value: $estimatedMinutes,
                    in: 5...480,
                    step: 5
                )
            }
            
            Section("実施予定日") {
                Toggle(
                    "実施予定日を設定",
                    isOn: $hasScheduledDate
                )

                if hasScheduledDate {
                    DatePicker(
                        "日付",
                        selection: $scheduledDate,
                        displayedComponents: .date
                    )
                }
            }
            
            Section("期限") {
                Toggle(
                    "期限を設定",
                    isOn: $hasDeadline
                )

                if hasDeadline {
                    DatePicker(
                        "日時",
                        selection: $deadline,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
            }
        }
        .navigationTitle("タスク編集")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    let updatedTask = TaskItem(
                        id: task.id,
                        title: title,
                        isCompleted: task.isCompleted,
                        estimatedMinutes: estimatedMinutes,
                        scheduledDate: hasScheduledDate ? scheduledDate : nil,
                        deadline: hasDeadline ? deadline : nil,
                        prerequisiteIDs: task.prerequisiteIDs
                    )
                    
                    onSave(updatedTask)
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        EditTaskView(
            task: TaskItem(
                title: "論文を読む",
                estimatedMinutes: 30,
                scheduledDate: Date()
            )
        )
    }
}
