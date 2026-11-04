import SwiftUI

struct AddTaskView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var estimatedMinutes = 30
    @State private var priority: TaskPriority = .medium
    
    @State private var hasScheduledDate = false
    @State private var scheduledDate = Date()
    
    @State private var hasDeadline = false
    @State private var deadline = Date()

    let onSave: (String, Int, TaskPriority, Date?, Date?) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("タスク") {
                    TextField("タスク名", text: $title)
                }

                Section("所要時間") {
                    Stepper(
                        "\(estimatedMinutes)分",
                        value: $estimatedMinutes,
                        in: 5...240,
                        step: 5
                    )
                }
                
                Section("優先度") {
                    Picker("優先度", selection: $priority) {
                        ForEach(TaskPriority.allCases, id: \.self) { priority in
                            Text(priority.displayName)
                                .tag(priority)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("実施予定日") {
                    Toggle("実施予定日を設定する", isOn: $hasScheduledDate)

                    if hasScheduledDate {
                        DatePicker(
                            "実施予定日",
                            selection: $scheduledDate,
                            displayedComponents: [.date]
                        )
                    }
                }

                Section("期限") {
                    Toggle("期限を設定する", isOn: $hasDeadline)

                    if hasDeadline {
                        DatePicker(
                            "期限",
                            selection: $deadline,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                }
            }
            .navigationTitle("タスクを追加")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let trimmedTitle = title.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )

                        onSave(
                            trimmedTitle,
                            estimatedMinutes,
                            priority,
                            hasScheduledDate ? scheduledDate : nil,
                            hasDeadline ? deadline : nil
                        )

                        dismiss()
                    }
                    .disabled(
                        title.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                }
            }
        }
    }
}

#Preview {
    AddTaskView { _, _, _, _, _ in }
}
