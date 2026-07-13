import SwiftUI

struct AddTaskView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var estimatedMinutes = 30
    
    @State private var hasScheduledDate = false
    @State private var scheduledDate = Date()
    
    @State private var hasDeadline = false
    @State private var deadline = Date()

    let onSave: (String, Int, Date?, Date?) -> Void

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
    AddTaskView { _, _, _, _ in }
}
