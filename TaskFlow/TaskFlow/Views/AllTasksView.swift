import SwiftUI

/// ホームの「ほかのタスク」から開く一覧
///
/// ホームには今やる1つだけを出すので、ここで全体を見渡せるようにする。
/// 今日・あとで・ほか・冬眠中・完了済み に分け、右へスワイプすると「今やる」ですぐ始められる。
struct AllTasksView: View {

    @State private var isSelecting = false
    @State private var selection: Set<UUID> = []
    @State private var isShowingCarryOver = false

    let tasks: [TaskItem]
    var dormantTaskIDs: Set<UUID> = []
    var tomorrowTaskIDs: Set<UUID> = []
    var pinnedTaskIDs: Set<UUID> = []
    var recurringTasks: [RecurringTask] = []

    /// 完了して7日たち、一覧から隠しているもの
    var hiddenCompletedTasks: [TaskItem] = []

    /// 今日の欄に入るタスク（予定日・期限が今日、今日やりたい、持ち越し）
    var todayTaskIDs: Set<UUID> = []

    /// 「あとで」にしているタスク
    var skippedTaskIDs: Set<UUID> = []

    /// いまホームのカードに出ているタスク（一歩なら、その元のタスク）
    var currentTaskID: UUID?

    /// 持ち越しているタスク（まとめて整理できる）
    var carriedOverTasks: [TaskItem] = []

    /// 一歩ずつ進めているタスクに添える「一歩ずつ・1/3 済み」
    var stepNotes: [UUID: String] = [:]
    let onToggleCompletion: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void

    /// 「今やる」。そのタスクにすぐ取りかかる
    var onStartNow: (TaskItem) -> Void = { _ in }

    /// 2つ目は、優先度「高」を付けるために「中」に戻すタスク（なければ nil）
    let onUpdate: (TaskItem, UUID?) -> Void
    var onWake: (TaskItem) -> Void = { _ in }
    var onSplit: (TaskItem, [TaskSplitPart]) -> Void = { _, _ in }
    var onTogglePin: (TaskItem) -> Void = { _ in }
    var onReschedule: (Set<UUID>, HomeViewModel.RescheduleOption) -> Void = { _, _ in }
    var onAddFirstStep: (TaskItem, String, Int) -> Void = { _, _, _ in }
    var onUpdateRecurring: (RecurringTask) -> Void = { _ in }
    var onDeleteRecurring: (RecurringTask) -> Void = { _ in }

    // MARK: - 欄の分け方

    private var openTasks: [TaskItem] {
        tasks.filter { !$0.isCompleted }
    }

    private var todayTasks: [TaskItem] {
        openTasks.filter { todayTaskIDs.contains($0.id) && !skippedTaskIDs.contains($0.id) && !dormantTaskIDs.contains($0.id) }
    }

    private var skippedTasks: [TaskItem] {
        openTasks.filter { skippedTaskIDs.contains($0.id) }
    }

    private var dormantTasks: [TaskItem] {
        openTasks.filter { dormantTaskIDs.contains($0.id) && !skippedTaskIDs.contains($0.id) }
    }

    private var otherTasks: [TaskItem] {
        openTasks.filter {
            !todayTaskIDs.contains($0.id) && !skippedTaskIDs.contains($0.id) && !dormantTaskIDs.contains($0.id)
        }
    }

    private var completedTasks: [TaskItem] {
        tasks.filter(\.isCompleted)
    }

    private func note(for task: TaskItem) -> String? {
        if task.id == currentTaskID {
            return String(localized: "いまホームに出ています")
        }

        if carriedOverTasks.contains(where: { $0.id == task.id }) {
            return String(localized: "持ち越し")
        }

        if pinnedTaskIDs.contains(task.id) {
            return String(localized: "今日やりたい")
        }

        if tomorrowTaskIDs.contains(task.id) {
            return String(localized: "明日")
        }

        if let stepNote = stepNotes[task.id] {
            return stepNote
        }

        if task.recurringID != nil {
            return String(localized: "くり返し")
        }

        return nil
    }

    // MARK: - 画面

    var body: some View {
        List(selection: $selection) {
            if tasks.isEmpty {
                Text("タスクはまだありません")
                    .foregroundStyle(.secondary)
            }

            if !todayTasks.isEmpty {
                Section {
                    rows(todayTasks)

                    if !carriedOverTasks.isEmpty, !isSelecting {
                        Button {
                            isShowingCarryOver = true
                        } label: {
                            Label("持ち越し\(carriedOverTasks.count)件をまとめて整理する", systemImage: "arrow.uturn.forward")
                                .font(.subheadline)
                        }
                    }
                } header: {
                    Text("今日")
                }
            }

            if !skippedTasks.isEmpty {
                Section {
                    rows(skippedTasks)
                } header: {
                    Text("あとで")
                } footer: {
                    Text("1時間たつと、また出てきます。右へスワイプすると、今すぐ始められます。")
                }
            }

            if !otherTasks.isEmpty {
                Section {
                    rows(otherTasks)
                } header: {
                    Text("ほか")
                }
            }

            if !dormantTasks.isEmpty {
                Section {
                    rows(dormantTasks)
                } header: {
                    Text("冬眠中")
                } footer: {
                    Text("しばらく触れていないものです。右へスワイプで起こせます。")
                }
            }

            if !completedTasks.isEmpty {
                Section {
                    rows(completedTasks)
                } header: {
                    Text("完了済み")
                }
            }

            if !hiddenCompletedTasks.isEmpty, !isSelecting {
                Section {
                    NavigationLink {
                        TaskArchiveListView(
                            title: String(localized: "完了済み"),
                            emptyMessage: String(localized: "ありません"),
                            tasks: hiddenCompletedTasks
                        )
                        .undoBanner()
                    } label: {
                        LabeledContent(
                            "完了して\(HomeViewModel.completedHideDays)日たったもの",
                            value: String(localized: "\(hiddenCompletedTasks.count)件")
                        )
                    }
                }
            }
        }
        .environment(\.editMode, .constant(isSelecting ? .active : .inactive))
        .navigationTitle("すべてのタスク")
        .sheet(isPresented: $isShowingCarryOver) {
            CarryOverView(tasks: carriedOverTasks) { ids, option in
                onReschedule(ids, option)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    RecurringListView(
                        recurringTasks: recurringTasks,
                        onUpdate: onUpdateRecurring,
                        onDelete: onDeleteRecurring
                    )
                    .undoBanner()
                } label: {
                    Label("くり返し", systemImage: "repeat")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button(isSelecting ? "完了" : "選択") {
                    isSelecting.toggle()
                    selection = []
                }
            }

            if isSelecting {
                ToolbarItem(placement: .bottomBar) {
                    Menu {
                        ForEach(HomeViewModel.RescheduleOption.allCases, id: \.self) { option in
                            Button(option.title) {
                                onReschedule(selection, option)
                                selection = []
                                isSelecting = false
                            }
                        }
                    } label: {
                        Label("選んだ\(selection.count)件の日付を変える", systemImage: "calendar")
                    }
                    .disabled(selection.isEmpty)
                }
            }
        }
    }

    // MARK: - 行

    private func rows(_ sectionTasks: [TaskItem]) -> some View {
        ForEach(sectionTasks) { task in
            row(task)
        }
    }

    private func row(_ task: TaskItem) -> some View {
        NavigationLink {
            EditTaskView(
                task: task,
                allTasks: tasks,
                onSave: { updatedTask, lowering in
                    onUpdate(updatedTask, lowering)
                },
                onSplit: { parts in
                    onSplit(task, parts)
                },
                onAddFirstStep: { title, minutes in
                    onAddFirstStep(task, title, minutes)
                },
                onDelete: {
                    onDelete(task)
                }
            )
            .undoBanner()
        } label: {
            TaskRowView(
                task: task,
                note: note(for: task),
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
            } else if !task.isCompleted {
                // 推薦を待たずに、自分で選んで今すぐ始める
                Button {
                    onStartNow(task)
                } label: {
                    Label("今やる", systemImage: "play.fill")
                }
                .tint(.green)

                Button {
                    onTogglePin(task)
                } label: {
                    if pinnedTaskIDs.contains(task.id) {
                        Label("今日やりたいを外す", systemImage: "pin.slash")
                    } else {
                        Label("今日やりたい", systemImage: "pin")
                    }
                }
                .tint(.blue)
            }
        }
        .swipeActions(edge: .trailing) {
            // すぐ消して、画面の下の「元に戻す」で戻せるようにする（確かめの画面は出さない）
            Button(role: .destructive) {
                onDelete(task)
            } label: {
                Label("削除", systemImage: "trash")
            }
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
            onUpdate: { _, _ in }
        )
    }
}
