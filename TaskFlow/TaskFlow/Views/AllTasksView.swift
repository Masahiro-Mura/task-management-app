import SwiftUI

struct AllTasksView: View {

    @State private var isSelecting = false
    @State private var selection: Set<UUID> = []

    let tasks: [TaskItem]
    var dormantTaskIDs: Set<UUID> = []
    var tomorrowTaskIDs: Set<UUID> = []
    var pinnedTaskIDs: Set<UUID> = []
    var recurringTasks: [RecurringTask] = []

    /// 完了して7日たち、一覧から隠しているもの
    var hiddenCompletedTasks: [TaskItem] = []

    /// 一歩ずつ進めているタスクに添える「一歩ずつ・1/3 済み」
    var stepNotes: [UUID: String] = [:]
    let onToggleCompletion: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void
    /// 2つ目は、優先度「高」を付けるために「中」に戻すタスク（なければ nil）
    let onUpdate: (TaskItem, UUID?) -> Void
    var onWake: (TaskItem) -> Void = { _ in }
    var onSplit: (TaskItem, [TaskSplitPart]) -> Void = { _, _ in }
    var onTogglePin: (TaskItem) -> Void = { _ in }
    var onReschedule: (Set<UUID>, HomeViewModel.RescheduleOption) -> Void = { _, _ in }
    var onAddFirstStep: (TaskItem, String, Int) -> Void = { _, _, _ in }
    var onUpdateRecurring: (RecurringTask) -> Void = { _ in }
    var onDeleteRecurring: (RecurringTask) -> Void = { _ in }

    private func note(for task: TaskItem) -> String? {
        if dormantTaskIDs.contains(task.id) {
            return String(localized: "冬眠中（右へスワイプで起こす）")
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

    var body: some View {
        List(selection: $selection) {
            ForEach(tasks) { task in
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
