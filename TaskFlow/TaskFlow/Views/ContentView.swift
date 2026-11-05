import SwiftUI

struct ContentView: View {

    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var viewModel = HomeViewModel()
    @State private var isShowingAddTask = false
    @State private var isTodayExpanded = false
    @State private var editingTaskID: UUID?
    @State private var quickAddText = ""

    /// 推薦を計算し直す間隔。期限までの残り時間などを時間経過に合わせて更新する
    private let refreshInterval: Duration = .seconds(60)

    /// 完了後に「元に戻す」を出しておく時間
    private let undoDuration: Duration = .seconds(5)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if viewModel.tasks.isEmpty {
                        emptyState
                    } else {
                        availableMinutesPicker

                        Group {
                            if let recommendation = viewModel.recommendation {
                                recommendationCard(recommendation)
                                    .id(recommendation.task.id)
                                    .transition(.opacity)
                            } else if let summary = viewModel.noRecommendationSummary {
                                noRecommendationCard(summary)
                            }
                        }
                        .animation(.easeInOut(duration: 0.25), value: viewModel.recommendation?.task.id)

                        todaySection
                    }
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if let completed = viewModel.lastCompletedTask {
                        undoBanner(for: completed)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    quickAddBar
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                .animation(.easeInOut(duration: 0.2), value: viewModel.lastCompletedTask?.id)
            }
            .navigationTitle("今やること")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        allTasksView
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .accessibilityLabel("すべてのタスク")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingAddTask = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("詳しく入れて追加")
                }
            }
            .navigationDestination(item: $editingTaskID) { taskID in
                if let task = viewModel.tasks.first(where: { $0.id == taskID }) {
                    editView(for: task)
                }
            }
            .sheet(isPresented: $isShowingAddTask) {
                AddTaskView { title, estimatedMinutes, priority, scheduledDate, deadline in
                    viewModel.addTask(
                        title: title,
                        estimatedMinutes: estimatedMinutes,
                        priority: priority,
                        scheduledDate: scheduledDate,
                        deadline: deadline
                    )
                }
            }
            .fullScreenCover(
                isPresented: Binding(
                    get: { viewModel.focusSession != nil },
                    set: { isPresented in
                        if !isPresented {
                            viewModel.finishFocus(completing: false)
                        }
                    }
                )
            ) {
                if let task = viewModel.focusedTask,
                   let session = viewModel.focusSession {
                    FocusView(
                        task: task,
                        startedAt: session.startedAt,
                        onComplete: {
                            viewModel.finishFocus(completing: true)
                        },
                        onStop: {
                            viewModel.finishFocus(completing: false)
                        }
                    )
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    viewModel.updateRecommendation()
                }
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: refreshInterval)
                    viewModel.updateRecommendation()
                }
            }
            .task(id: viewModel.lastCompletedTask?.id) {
                guard viewModel.lastCompletedTask != nil else {
                    return
                }

                try? await Task.sleep(for: undoDuration)

                if !Task.isCancelled {
                    viewModel.dismissUndo()
                }
            }
        }
    }

    // MARK: - タスクがないとき

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("最初のタスクを入れましょう")
                .font(.headline)

            Text("下の入力欄に「請求書を送る 15分」のように書くと、所要時間つきで追加できます。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - 空き時間

    /// 今使える時間の選択
    private var availableMinutesPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("今使える時間")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker(
                "今使える時間",
                selection: Binding(
                    get: { viewModel.availableMinutes },
                    set: { viewModel.setAvailableMinutes($0) }
                )
            ) {
                ForEach(HomeViewModel.availableMinuteOptions, id: \.self) { minutes in
                    Text("\(minutes)分")
                        .tag(minutes)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - 推薦カード

    private func recommendationCard(
        _ recommendation: TaskRecommendation
    ) -> some View {
        let task = recommendation.task

        return VStack(alignment: .leading, spacing: 14) {
            Label("今はこれ", systemImage: "sparkles")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(details(for: task))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(recommendation.reason)
                .font(.body)

            Button {
                viewModel.startFocus()
            } label: {
                Label("始める", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            HStack(spacing: 12) {
                Button {
                    viewModel.completeRecommendation()
                } label: {
                    Label("完了", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }

                Button {
                    viewModel.skipRecommendation()
                } label: {
                    Text("今はやらない")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(.blue.opacity(0.4), lineWidth: 1)
        }
    }

    /// 所要時間と、中以外の優先度
    private func details(for task: TaskItem) -> String {
        var parts = ["所要時間 \(task.estimatedMinutes)分"]

        if task.priority != .medium {
            parts.append("優先度 \(task.priority.displayName)")
        }

        return parts.joined(separator: " · ")
    }

    /// 推薦できるタスクがないときに、その内訳と次の一手を示す
    private func noRecommendationCard(
        _ summary: NoRecommendationSummary
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if summary.allCompleted {
                Label("すべてのタスクが完了しています", systemImage: "checkmark.circle")
                    .font(.headline)
            } else {
                Label("今の空き時間で取りかかれるタスクはありません", systemImage: "clock")
                    .font(.headline)

                if summary.tooLongCount > 0,
                   let shortest = summary.shortestTooLongMinutes {
                    Text("空き時間\(viewModel.availableMinutes)分に収まらないタスクが\(summary.tooLongCount)件あります（最短\(shortest)分）")
                }

                if summary.waitingForPrerequisitesCount > 0 {
                    Text("前提タスクの完了を待っているタスクが\(summary.waitingForPrerequisitesCount)件あります")
                }

                if summary.skippedCount > 0 {
                    Text("「今はやらない」にしたタスクが\(summary.skippedCount)件あります（1時間たつと戻ります）")
                }

                if summary.dormantCount > 0 {
                    Text("冬眠中のタスクが\(summary.dormantCount)件あります（「すべてのタスク」から起こせます）")
                }

                if summary.tooLongCount > 0 {
                    Text("大きいタスクは、編集画面から小さく分けられます")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    if let suggested = viewModel.suggestedAvailableMinutes {
                        Button("空き時間を\(suggested)分にする") {
                            viewModel.setAvailableMinutes(suggested)
                        }
                    }

                    if summary.skippedCount > 0 {
                        Button("今はやらないを取り消す") {
                            viewModel.clearSkips()
                        }
                    }
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
        }
        .font(.subheadline)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 今日

    @ViewBuilder
    private var todaySection: some View {
        let todayTasks = viewModel.todayTasks

        if !todayTasks.isEmpty {
            let carriedOverCount = todayTasks.filter { viewModel.isCarriedOver($0) }.count
            let openCount = todayTasks.filter { !$0.isCompleted }.count

            DisclosureGroup(isExpanded: $isTodayExpanded) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(todayTasks) { task in
                        TaskRowView(
                            task: task,
                            note: viewModel.isCarriedOver(task) ? "持ち越し" : nil,
                            onToggleCompletion: {
                                viewModel.toggleCompletion(for: task)
                            }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingTaskID = task.id
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                // 完了したものは数えず、残りだけを示す
                Label(
                    openCount == 0
                        ? "今日の分は終わりました"
                        : carriedOverCount > 0
                            ? "今日 残り\(openCount)件（持ち越し \(carriedOverCount)）"
                            : "今日 残り\(openCount)件",
                    systemImage: "sun.max"
                )
                .font(.headline)
            }
            .padding()
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - 下部の入力欄

    private var quickAddBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.secondary)

            TextField("タスクを追加（例：請求書を送る 15分）", text: $quickAddText)
                .submitLabel(.done)
                .onSubmit(submitQuickAdd)

            if !quickAddText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("追加", action: submitQuickAdd)
                    .fontWeight(.semibold)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
    }

    private func submitQuickAdd() {
        if viewModel.quickAdd(quickAddText) {
            quickAddText = ""
        }
    }

    private func undoBanner(for task: TaskItem) -> some View {
        HStack(spacing: 12) {
            Text("「\(task.title)」を完了しました")
                .font(.subheadline)
                .lineLimit(1)

            Spacer()

            Button("元に戻す") {
                viewModel.undoLastCompletion()
            }
            .font(.subheadline)
            .fontWeight(.semibold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: Capsule())
    }

    // MARK: - 遷移先

    private var allTasksView: some View {
        AllTasksView(
            tasks: viewModel.allTasks,
            dormantTaskIDs: viewModel.dormantTaskIDs,
            tomorrowTaskIDs: Set(viewModel.tomorrowTasks.map(\.id)),
            onToggleCompletion: { task in
                viewModel.toggleCompletion(for: task)
            },
            onDelete: { task in
                viewModel.deleteTask(task)
            },
            onUpdate: { updatedTask in
                viewModel.updateTask(updatedTask)
            },
            onWake: { task in
                viewModel.wakeTask(task)
            },
            onSplit: { task, parts in
                viewModel.splitTask(task, into: parts)
            }
        )
    }

    private func editView(for task: TaskItem) -> some View {
        EditTaskView(
            task: task,
            allTasks: viewModel.allTasks,
            onSave: { updatedTask in
                viewModel.updateTask(updatedTask)
            },
            onSplit: { parts in
                viewModel.splitTask(task, into: parts)
            }
        )
    }
}

#Preview {
    ContentView()
}
