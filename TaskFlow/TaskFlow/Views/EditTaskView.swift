import SwiftUI

struct EditTaskView: View {
    
    @Environment(\.dismiss) private var dismiss

    let task: TaskItem
    let onSave: (TaskItem) -> Void
    let onSplit: ([TaskSplitPart]) -> Void

    /// 前提として選べるタスク（自分自身と、循環するものを除く）
    private let selectablePrerequisites: [TaskItem]

    @State private var title: String
    @State private var estimatedMinutes: Int
    @State private var priority: TaskPriority
    @State private var scheduledDate: Date
    @State private var hasScheduledDate: Bool
    @State private var deadline: Date
    @State private var hasDeadline: Bool
    @State private var prerequisiteIDs: Set<UUID>
    @State private var isShowingSplit = false

    /// 分け方が決まったら、シートが閉じたあとに反映する
    @State private var pendingSplit: [TaskSplitPart]?

    /// - Parameters:
    ///   - allTasks: 前提タスクの候補を選ぶための全タスク
    ///   - onSplit: 「小さく分ける」で分け方が決まったときに呼ばれる
    init(
        task: TaskItem,
        allTasks: [TaskItem],
        onSave: @escaping (TaskItem) -> Void = { _ in },
        onSplit: @escaping ([TaskSplitPart]) -> Void = { _ in }
    ) {
        self.task = task
        self.onSave = onSave
        self.onSplit = onSplit
        self.selectablePrerequisites = PrerequisiteRules.selectablePrerequisites(
            for: task,
            in: allTasks
        )

        _prerequisiteIDs = State(
            initialValue: Set(task.prerequisiteIDs)
        )

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
                Toggle(
                    "実施予定日を設定",
                    isOn: $hasScheduledDate
                )

                if hasScheduledDate {
                    DatePicker(
                        "日付",
                        selection: $scheduledDate,
                        displayedComponents: [.date, .hourAndMinute]
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

            Section {
                if selectablePrerequisites.isEmpty {
                    Text("選べるタスクがありません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(selectablePrerequisites) { candidate in
                        Toggle(
                            candidate.title,
                            isOn: Binding(
                                get: { prerequisiteIDs.contains(candidate.id) },
                                set: { isOn in
                                    if isOn {
                                        prerequisiteIDs.insert(candidate.id)
                                    } else {
                                        prerequisiteIDs.remove(candidate.id)
                                    }
                                }
                            )
                        )
                    }
                }
            } header: {
                Text("先に終わらせるタスク")
            } footer: {
                Text("選んだタスクが終わるまで、このタスクはおすすめに出ません。")
            }

            if !task.isCompleted {
                Section {
                    Button("小さく分ける") {
                        isShowingSplit = true
                    }
                } footer: {
                    Text("空き時間に収まらない大きいタスクは、順番に取りかかれる小さいタスクに分けられます。")
                }
            }
        }
        .navigationTitle("タスク編集")
        .sheet(
            isPresented: $isShowingSplit,
            onDismiss: {
                guard let parts = pendingSplit else {
                    return
                }

                pendingSplit = nil
                onSplit(parts)
                // 元のタスクはなくなるので、編集画面も閉じる
                dismiss()
            }
        ) {
            SplitTaskView(task: task) { parts in
                pendingSplit = parts
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    let updatedTask = TaskItem(
                        id: task.id,
                        title: title,
                        isCompleted: task.isCompleted,
                        estimatedMinutes: estimatedMinutes,
                        priority: priority,
                        scheduledDate: hasScheduledDate ? scheduledDate : nil,
                        deadline: hasDeadline ? deadline : nil,
                        // 一覧の順に並べ、選べなくなった前提（削除・循環）は外す
                        prerequisiteIDs: selectablePrerequisites
                            .map(\.id)
                            .filter { prerequisiteIDs.contains($0) },
                        completedAt: task.completedAt,
                        splitGroupID: task.splitGroupID
                    )
                    
                    onSave(updatedTask)
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    let task = TaskItem(
        title: "論文を読む",
        estimatedMinutes: 90,
        scheduledDate: Date()
    )

    NavigationStack {
        EditTaskView(
            task: task,
            allTasks: [
                task,
                TaskItem(title: "論文を印刷する", estimatedMinutes: 10)
            ]
        )
    }
}
