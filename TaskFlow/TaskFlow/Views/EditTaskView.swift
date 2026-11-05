import SwiftUI

struct EditTaskView: View {
    
    @Environment(\.dismiss) private var dismiss

    let task: TaskItem
    let onSave: (TaskItem) -> Void
    let onSplit: ([TaskSplitPart]) -> Void
    let onLowerPriority: (UUID) -> Void
    let onAddFirstStep: (String, Int) -> Void

    /// 前提として選べるタスク（自分自身と、循環するものを除く）
    private let selectablePrerequisites: [TaskItem]

    /// このタスク以外で、優先度「高」の未完了タスク
    private let otherHighPriorityTasks: [TaskItem]

    @State private var title: String
    @State private var estimatedMinutes: Int
    @State private var priority: TaskPriority
    @State private var scheduledDate: Date
    @State private var hasScheduledDate: Bool
    @State private var deadline: Date
    @State private var hasDeadline: Bool
    @State private var prerequisiteIDs: Set<UUID>
    @State private var isShowingSplit = false
    @State private var isShowingFirstStep = false
    @State private var lowering: UUID?
    @State private var isLight: Bool
    @State private var isPinnedForToday: Bool

    /// 分け方が決まったら、シートが閉じたあとに反映する
    @State private var pendingSplit: [TaskSplitPart]?

    /// - Parameters:
    ///   - allTasks: 前提タスクの候補を選ぶための全タスク
    ///   - onSplit: 「小さく分ける」で分け方が決まったときに呼ばれる
    init(
        task: TaskItem,
        allTasks: [TaskItem],
        onSave: @escaping (TaskItem) -> Void = { _ in },
        onSplit: @escaping ([TaskSplitPart]) -> Void = { _ in },
        onLowerPriority: @escaping (UUID) -> Void = { _ in },
        onAddFirstStep: @escaping (String, Int) -> Void = { _, _ in }
    ) {
        self.task = task
        self.onSave = onSave
        self.onSplit = onSplit
        self.onLowerPriority = onLowerPriority
        self.onAddFirstStep = onAddFirstStep
        self.selectablePrerequisites = PrerequisiteRules.selectablePrerequisites(
            for: task,
            in: allTasks
        )
        self.otherHighPriorityTasks = allTasks.filter {
            $0.priority == .high && !$0.isCompleted && $0.id != task.id
        }

        _isLight = State(initialValue: task.isLight)
        _isPinnedForToday = State(initialValue: task.isPinnedForToday(at: Date()))

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

                Toggle("頭を使わない軽い作業", isOn: $isLight)
            }

            if !task.isCompleted {
                Section {
                    Toggle("今日やりたい", isOn: $isPinnedForToday)
                } footer: {
                    Text("日付は変えずに、今日のおすすめで優先します。")
                }
            }

            PrioritySection(
                priority: $priority,
                lowering: $lowering,
                otherHighPriorityTasks: otherHighPriorityTasks
            )

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
                    Button("一歩を足す") {
                        isShowingFirstStep = true
                    }

                    Button("小さく分ける") {
                        isShowingSplit = true
                    }
                } footer: {
                    Text("全部を分けるのが面倒なら、最初の一歩だけ決めれば大丈夫です。全体を順番に分けたいときは「小さく分ける」。")
                }
            }
        }
        .navigationTitle("タスク編集")
        .sheet(isPresented: $isShowingFirstStep) {
            FirstStepView(task: task) { title, minutes in
                onAddFirstStep(title, minutes)
            }
        }
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
                    // 元のタスクを写して、この画面で変えるものだけ書き換える（ほかの項目は失わない）
                    var updatedTask = task
                    updatedTask.title = title
                    updatedTask.estimatedMinutes = estimatedMinutes
                    updatedTask.priority = priority
                    updatedTask.scheduledDate = hasScheduledDate ? scheduledDate : nil
                    updatedTask.deadline = hasDeadline ? deadline : nil
                    // 一覧の順に並べ、選べなくなった前提（削除・循環）は外す
                    updatedTask.prerequisiteIDs = selectablePrerequisites
                        .map(\.id)
                        .filter { prerequisiteIDs.contains($0) }
                    // すでに今日付けた印なら、その日時のまま残す
                    updatedTask.pinnedForTodayAt = isPinnedForToday
                        ? (task.isPinnedForToday(at: Date()) ? task.pinnedForTodayAt : Date())
                        : nil
                    updatedTask.isLight = isLight

                    if priority == .high, let lowering {
                        onLowerPriority(lowering)
                    }
                    
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
