import SwiftUI

/// 詳しく入れてタスクを追加する画面
struct AddTaskView: View {

    /// 入力された内容
    struct NewTask {
        var title: String
        var estimatedMinutes: Int
        var priority: TaskPriority
        var scheduledDate: Date?
        var deadline: Date?
        var isLight: Bool

        /// 優先度「高」の上限のために「中」に戻すタスク
        var lowering: UUID?
    }

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var estimatedMinutes = 30
    @State private var priority: TaskPriority = .medium
    @State private var lowering: UUID?
    @State private var isLight = false

    @State private var hasScheduledDate = false
    @State private var scheduledDate = Date()

    @State private var hasDeadline = false
    @State private var deadline = Date()

    /// 優先度「高」の上限を確かめるための、ほかの「高」のタスク
    var otherHighPriorityTasks: [TaskItem] = []

    let onSave: (NewTask) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("タスク") {
                    TextField("タスク名", text: $title)

                    Toggle("頭を使わない軽い作業", isOn: $isLight)
                }

                Section("所要時間") {
                    Stepper(
                        "\(estimatedMinutes)分",
                        value: $estimatedMinutes,
                        in: 5...240,
                        step: 5
                    )
                }

                PrioritySection(
                    priority: $priority,
                    lowering: $lowering,
                    otherHighPriorityTasks: otherHighPriorityTasks
                )

                Section {
                    Toggle("実施予定日を設定する", isOn: $hasScheduledDate)

                    if hasScheduledDate {
                        DatePicker(
                            "実施予定日",
                            selection: $scheduledDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                } header: {
                    Text("実施予定日（なくても大丈夫）")
                } footer: {
                    Text("「このころやりたい」の目安です。過ぎても今日に流れてくるだけで、選び直さなくて大丈夫です。")
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
                        onSave(
                            NewTask(
                                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                estimatedMinutes: estimatedMinutes,
                                priority: priority,
                                scheduledDate: hasScheduledDate ? scheduledDate : nil,
                                deadline: hasDeadline ? deadline : nil,
                                isLight: isLight,
                                lowering: priority == .high ? lowering : nil
                            )
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
    AddTaskView { _ in }
}
