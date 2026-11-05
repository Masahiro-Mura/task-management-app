import SwiftUI

struct ContentView: View {

    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var viewModel = HomeViewModel()
    @State private var isShowingAddTask = false
    @State private var isTodayExpanded = false
    @State private var editingTaskID: UUID?
    @State private var quickAddText = ""
    @State private var ignoredQuickAddParts: Set<QuickAddParser.Part> = []
    @State private var celebration: Celebration?
    @State private var isShowingDoneToday = false
    @State private var isShowingCarryOver = false
    @State private var firstStepTask: TaskItem?

    /// 完了した瞬間に出すお祝いの表示
    private struct Celebration: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let showsConfetti: Bool
    }

    /// お祝いを出しておく時間
    private let celebrationDuration: Duration = .seconds(1.6)

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

                        if viewModel.isOfferingLightMode {
                            lightModeOffer
                                .transition(.opacity)
                        }

                        if let candidate = viewModel.nextStepCandidate {
                            nextStepOffer(for: candidate)
                                .transition(.opacity)
                        }

                        Group {
                            if viewModel.lightModeHasNoMatch {
                                lightModeNoMatchCard
                            } else if let recommendation = viewModel.recommendation {
                                recommendationCard(recommendation)
                                    .id(recommendation.task.id)
                                    .transition(.opacity)
                            } else if let summary = viewModel.noRecommendationSummary {
                                noRecommendationCard(summary)
                            }
                        }
                        .animation(.easeInOut(duration: 0.25), value: viewModel.recommendation?.task.id)

                        todaySection

                        doneTodayRow
                    }
                }
                .padding()
            }
            .overlay {
                if let celebration {
                    CelebrationView(
                        message: celebration.message,
                        showsConfetti: celebration.showsConfetti
                    )
                    .id(celebration.id)
                    .transition(.opacity)
                }
            }
            .sensoryFeedback(.success, trigger: celebration?.id) { _, newValue in
                newValue != nil
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
                AddTaskView(
                    otherHighPriorityTasks: viewModel.otherHighPriorityTasks(excluding: nil)
                ) { newTask in
                    if let lowering = newTask.lowering {
                        viewModel.lowerPriority(of: lowering)
                    }

                    if let recurrence = newTask.recurrence {
                        viewModel.addRecurring(
                            title: newTask.title,
                            estimatedMinutes: newTask.estimatedMinutes,
                            priority: newTask.priority,
                            isLight: newTask.isLight,
                            recurrence: recurrence
                        )
                        return
                    }

                    viewModel.addTask(
                        title: newTask.title,
                        estimatedMinutes: newTask.estimatedMinutes,
                        priority: newTask.priority,
                        scheduledDate: newTask.scheduledDate,
                        deadline: newTask.deadline,
                        isLight: newTask.isLight
                    )
                }
            }
            .sheet(item: $firstStepTask) { task in
                FirstStepView(task: task) { title, minutes in
                    viewModel.addFirstStep(for: task, title: title, minutes: minutes)
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
                        trialMinutes: session.trialMinutes,
                        onComplete: {
                            viewModel.finishFocus(completing: true)
                        },
                        onStop: {
                            viewModel.finishFocus(completing: false)
                        },
                        onContinue: {
                            viewModel.continueFocus()
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
            .onChange(of: viewModel.lastCompletedTask?.id) { _, newValue in
                guard newValue != nil, let task = viewModel.lastCompletedTask else {
                    return
                }

                let finishedGroup = viewModel.finishedWholeSplitGroup(of: task)
                celebration = Celebration(
                    message: CompletionMessages.message(for: task, finishedGroup: finishedGroup),
                    showsConfetti: finishedGroup
                )
            }
            .task(id: celebration?.id) {
                guard celebration != nil else {
                    return
                }

                try? await Task.sleep(for: celebrationDuration)

                if !Task.isCancelled {
                    withAnimation(.easeOut(duration: 0.3)) {
                        celebration = nil
                    }
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
            HStack {
                Text("今使える時間")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                lightModeToggle
            }

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

            // 大きいタスクは、全部やらなくても手をつけられる入り口を添える
            if task.estimatedMinutes >= Self.bigTaskMinutes {
                bigTaskShortcuts(for: task)
            }

            // くり返しの回は、その回だけ休める
            if task.recurringID != nil {
                Button {
                    viewModel.skipOccurrence(task)
                } label: {
                    Label("今回はお休み", systemImage: "moon.zzz")
                }
                .font(.subheadline)
                .buttonStyle(.borderless)
            }
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

                if summary.scheduledLaterCount > 0 {
                    Text("明日以降に予定しているタスクが\(summary.scheduledLaterCount)件あります（その日になったら出てきます）")
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

                // 時間に収まらなくても、最初の一歩か5分だけなら始められる
                if let taskID = summary.shortestTooLongTaskID,
                   let task = viewModel.tasks.first(where: { $0.id == taskID }) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("「\(task.title)」なら、こうして始められます")
                            .foregroundStyle(.secondary)

                        bigTaskShortcuts(for: task)
                    }
                    .padding(.top, 6)
                }
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
            let openTasks = todayTasks.filter { !$0.isCompleted }
            let openCount = openTasks.count
            let openMinutes = openTasks.reduce(0) { $0 + $1.estimatedMinutes }

            VStack(alignment: .leading, spacing: 12) {
            DisclosureGroup(isExpanded: $isTodayExpanded) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(todayTasks) { task in
                        TaskRowView(
                            task: task,
                            note: viewModel.isCarriedOver(task)
                                ? "持ち越し"
                                : viewModel.pinnedTaskIDs.contains(task.id) ? "今日やりたい" : nil,
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
                            ? "今日 残り\(openCount)件・約\(DoneTodayView.formatMinutes(openMinutes))（持ち越し \(carriedOverCount)）"
                            : "今日 残り\(openCount)件・約\(DoneTodayView.formatMinutes(openMinutes))",
                    systemImage: "sun.max"
                )
                .font(.headline)
            }

                if carriedOverCount > 0 {
                    Button {
                        isShowingCarryOver = true
                    } label: {
                        Label("持ち越し\(carriedOverCount)件をまとめて整理する", systemImage: "arrow.uturn.forward")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .sheet(isPresented: $isShowingCarryOver) {
                        CarryOverView(tasks: viewModel.carriedOverTasks) { ids, option in
                            viewModel.reschedule(ids, to: option)
                        }
                    }
                }
            }
            .padding()
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - 今日やったこと

    @ViewBuilder
    private var doneTodayRow: some View {
        let done = viewModel.completedToday

        if !done.isEmpty {
            let totalMinutes = done.reduce(0) { $0 + $1.estimatedMinutes }

            Button {
                isShowingDoneToday = true
            } label: {
                HStack {
                    Label(
                        "今日やったこと \(done.count)件・約\(DoneTodayView.formatMinutes(totalMinutes))",
                        systemImage: "checkmark.seal"
                    )
                    .font(.subheadline)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.green)
            .padding()
            .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            .sheet(isPresented: $isShowingDoneToday) {
                DoneTodayView(tasks: viewModel.completedToday)
            }
        }
    }

    // MARK: - 下部の入力欄

    private var quickAddBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            quickAddChips

            quickAddField
        }
    }

    /// 入力を読み取った結果。タップすると、その読み取りを外して文字のままタイトルに残す
    @ViewBuilder
    private var quickAddChips: some View {
        if let full = viewModel.previewQuickAdd(quickAddText) {
            let when = full.deadline.map { ("期限 " + viewModel.describeQuickAddDate($0, includesTime: full.includesTime), "flag") }
                ?? full.scheduledDate.map { (viewModel.describeQuickAddDate($0, includesTime: full.includesTime), "calendar") }

            if when != nil || full.durationWasWritten || full.isLight || full.recurrence != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if let when {
                            quickAddChip(when.0, systemImage: when.1, part: .when)
                        }

                        if full.durationWasWritten {
                            quickAddChip("\(full.estimatedMinutes)分", systemImage: "clock", part: .duration)
                        }

                        if full.isLight {
                            quickAddChip("軽い作業", systemImage: "leaf", part: .light)
                        }

                        if let recurrence = full.recurrence {
                            quickAddChip(recurrence.summary, systemImage: "repeat", part: .repeat)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private func quickAddChip(
        _ text: String,
        systemImage: String,
        part: QuickAddParser.Part
    ) -> some View {
        let isIgnored = ignoredQuickAddParts.contains(part)

        return Button {
            if isIgnored {
                ignoredQuickAddParts.remove(part)
            } else {
                ignoredQuickAddParts.insert(part)
            }
        } label: {
            Label(text, systemImage: isIgnored ? "xmark" : systemImage)
                .font(.footnote)
                .strikethrough(isIgnored)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(isIgnored ? Color.secondary : Color.blue)
                .background(
                    (isIgnored ? Color.secondary : Color.blue).opacity(0.12),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityHint(isIgnored ? "タップするとまた読み取ります" : "タップすると読み取らずに文字のまま残します")
    }

    private var quickAddField: some View {
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
        if viewModel.quickAdd(quickAddText, ignoring: ignoredQuickAddParts) {
            quickAddText = ""
            ignoredQuickAddParts = []
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
            pinnedTaskIDs: viewModel.pinnedTaskIDs,
            recurringTasks: viewModel.recurringTasks,
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
            },
            onTogglePin: { task in
                viewModel.togglePinnedForToday(task)
            },
            onLowerPriority: { taskID in
                viewModel.lowerPriority(of: taskID)
            },
            onReschedule: { ids, option in
                viewModel.reschedule(ids, to: option)
            },
            onAddFirstStep: { task, title, minutes in
                viewModel.addFirstStep(for: task, title: title, minutes: minutes)
            },
            onUpdateRecurring: { recurring in
                viewModel.updateRecurring(recurring)
            },
            onDeleteRecurring: { recurring in
                viewModel.deleteRecurring(recurring)
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
            },
            onLowerPriority: { taskID in
                viewModel.lowerPriority(of: taskID)
            },
            onAddFirstStep: { title, minutes in
                viewModel.addFirstStep(for: task, title: title, minutes: minutes)
            }
        )
    }

    // MARK: - 大きいタスクの入り口

    /// この所要時間以上のタスクには、「5分だけ」「最初の一歩」を添える
    private static let bigTaskMinutes = 30

    private func bigTaskShortcuts(for task: TaskItem) -> some View {
        HStack(spacing: 16) {
            Button {
                viewModel.startFocus(on: task.id, trialMinutes: HomeViewModel.trialFocusMinutes)
            } label: {
                Label("\(HomeViewModel.trialFocusMinutes)分だけやる", systemImage: "timer")
            }

            Button {
                firstStepTask = task
            } label: {
                Label("最初の一歩を決める", systemImage: "shoeprints.fill")
            }
        }
        .font(.subheadline)
        .buttonStyle(.borderless)
    }

    /// 一歩を終えたあとに出す「次の一歩を決めますか？」
    private func nextStepOffer(for task: TaskItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "shoeprints.fill")
                .foregroundStyle(.blue)

            Text("「\(CompletionMessages.baseTitle(of: task.title))」の次の一歩を決めますか？")
                .font(.subheadline)

            Spacer(minLength: 0)

            Button("決める") {
                firstStepTask = task
                viewModel.dismissNextStepOffer()
            }
            .font(.subheadline)
            .fontWeight(.semibold)

            Button {
                viewModel.dismissNextStepOffer()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("閉じる")
        }
        .padding(12)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 気が乗らないとき

    /// 軽い・短い作業だけにする切り替え。いつでも押せる
    private var lightModeToggle: some View {
        Button {
            viewModel.setPrefersLight(!viewModel.prefersLight)
        } label: {
            Label(
                viewModel.prefersLight ? "軽いものだけ" : "気が乗らない",
                systemImage: viewModel.prefersLight ? "leaf.fill" : "leaf"
            )
            .font(.footnote)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(viewModel.prefersLight ? Color.green : Color.secondary)
            .background(
                (viewModel.prefersLight ? Color.green : Color.secondary).opacity(0.12),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(viewModel.prefersLight ? "ふだんの推薦に戻します" : "軽い作業と短い作業だけを推薦します")
    }

    /// 「今はやらない」のあとに出す、軽いものへの逃げ道
    private var lightModeOffer: some View {
        HStack(spacing: 12) {
            Image(systemName: "leaf")
                .foregroundStyle(.green)

            Text("気が乗らないときは、軽いものにしますか？")
                .font(.subheadline)

            Spacer(minLength: 0)

            Button("軽いものに") {
                viewModel.setPrefersLight(true)
            }
            .font(.subheadline)
            .fontWeight(.semibold)

            Button {
                viewModel.dismissLightOffer()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("閉じる")
        }
        .padding(12)
        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    /// 軽い作業だけにしたら候補がなかったとき
    private var lightModeNoMatchCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("軽い作業や\(TaskItem.shortTaskMinutes)分以内の作業がありません", systemImage: "leaf")
                .font(.headline)

            Text("タスクの編集画面で「頭を使わない軽い作業」にしておくと、こういうときに出てきます。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("ふだんのおすすめに戻す") {
                viewModel.setPrefersLight(false)
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    ContentView()
}
