import SwiftUI

struct ContentView: View {

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @StateObject private var viewModel = HomeViewModel.makeForApp()
    @State private var isShowingAddTask = false
    @State private var editingTaskID: UUID?
    @State private var quickAddText = ""
    @State private var ignoredQuickAddParts: Set<QuickAddParser.Part> = []
    @State private var celebration: Celebration?
    @State private var isShowingDoneToday = false
    @State private var firstStepTask: TaskItem?
    @State private var isShowingLetGo = false
    @State private var isShowingFullReason = false
    @State private var firstStepIdeaIndex = 0
    @State private var isQuickAddOpen = false
    @FocusState private var isQuickAddFocused: Bool

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


    /// 広い画面での中身の最大の幅
    private static let readableWidth: CGFloat = 640

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if viewModel.tasks.isEmpty {
                        emptyState
                    } else {
                        availableMinutesPicker

                        if let candidate = viewModel.repeatedSkipCandidate {
                            repeatedSkipOffer(for: candidate)
                                .transition(.opacity)
                        } else if viewModel.isOfferingLightMode {
                            lightModeOffer
                                .transition(.opacity)
                        }

                        if let candidate = viewModel.nextStepCandidate {
                            nextStepOffer(for: candidate)
                                .transition(.opacity)
                        }

                        if viewModel.shouldOfferLetGo {
                            letGoOffer
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

                        // ほかのタスクは、ここから一覧へ（ホームには今やる1つだけを置く）
                        otherTasksRow

                        doneTodayRow
                    }
                }
                .padding()
                // iPad や Mac の広い画面でも、読みやすい幅で中央に置く
                .frame(maxWidth: Self.readableWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
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
                VStack(spacing: 10) {
                    UndoBanner(viewModel: viewModel)

                    if isQuickAddOpen {
                        quickAddBar
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        addButton
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                .frame(maxWidth: Self.readableWidth)
                .frame(maxWidth: .infinity)
                .animation(.spring(duration: 0.3), value: isQuickAddOpen)
            }
            .navigationTitle("今やること")
            .toolbar {
                // 軽いものだけの切り替えは右上に置く（ホームの文字を減らすため）
                if !viewModel.tasks.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        lightModeToggle
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView(viewModel: viewModel)
                            .undoBanner()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("設定")
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
                    // 優先度を下げるのと足すのは、1回の「元に戻す」で戻せるようにまとめる
                    viewModel.performAsOne(String(localized: "「\(newTask.title)」を足しました。")) {
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
                        } else {
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
                }
            }
            .sheet(item: $firstStepTask) { task in
                // 一歩から開いたときは、その元のタスクの一歩の一覧を出す
                StepsView(viewModel: viewModel, parentID: task.parentTaskID ?? task.id)
                    .undoBanner()
            }
            .fullScreenCover(
                isPresented: Binding(
                    get: { viewModel.focusSession != nil },
                    set: { isPresented in
                        if !isPresented {
                            endFocus(completing: false)
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
                            endFocus(completing: true)
                        },
                        onStop: {
                            endFocus(completing: false)
                        },
                        onContinue: {
                            viewModel.continueFocus()
                        }
                    )
                }
            }
            .onAppear {
                HomeViewModel.current = viewModel
            }
            .onOpenURL { url in
                handle(url)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    viewModel.appDidBecomeActive()
                }
            }
            .fullScreenCover(
                isPresented: Binding(
                    get: { viewModel.needsOnboarding },
                    set: { isPresented in
                        if !isPresented {
                            viewModel.finishOnboarding(addExamples: false)
                        }
                    }
                )
            ) {
                OnboardingView { addExamples in
                    viewModel.finishOnboarding(addExamples: addExamples)
                }
            }
            .sheet(isPresented: $isShowingLetGo) {
                LetGoView(
                    tasks: viewModel.longDormantTasks,
                    onLetGo: { ids in
                        viewModel.letGo(ids)
                    },
                    onLater: {
                        viewModel.dismissLetGoOffer()
                    }
                )
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
            .onChange(of: viewModel.recommendation?.task.id) { _, _ in
                isShowingFullReason = false
                firstStepIdeaIndex = 0
            }
            .onChange(of: isQuickAddFocused) { _, isFocused in
                // 何も書かずに入力欄を離れたら、丸い＋に戻す
                if !isFocused, quickAddText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    isQuickAddOpen = false
                    ignoredQuickAddParts = []
                }
            }
        }
        // 一覧・編集・設定・シートでも「元に戻す」を出せるように、画面の奥まで ViewModel を渡す
        .environment(\.homeViewModel, viewModel)
    }

    // MARK: - タスクがないとき

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("最初のタスクを入れましょう")
                .font(.headline)

            Text("＋を押して、思いついたまま書いてください")
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
            if viewModel.prefersLight {
                lightModeStatus
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

    /// 今の1つ。取りかかる操作（始める・5分だけ）を大きく、今はやらない操作（あとで・終わった）を
    /// その下に控えめに並べ、めったに使わない操作は右上の「…」にまとめる（並んだボタンで迷わせないため）
    private func recommendationCard(
        _ recommendation: TaskRecommendation
    ) -> some View {
        let task = recommendation.task

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    // 一歩なら、どのタスクの一歩かを名前の上に小さく示す（つながりが分かるように）
                    if let position = viewModel.stepPosition(of: task) {
                        Label(
                            "「\(CompletionMessages.baseTitle(of: position.parentTitle))」の\(position.index)歩目",
                            systemImage: "shoeprints.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("stepParent")
                    }

                    Text(task.title)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("recommendationTitle")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                cardMenu(for: task)
            }

            cardPills(for: recommendation)

            firstStepIdeaRow(for: task)

            if isShowingFullReason {
                Text(recommendation.reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

            HStack(spacing: 10) {
                Button {
                    beginFocus()
                } label: {
                    Label("始める", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)

                Button {
                    beginFocus(on: task.id, trialMinutes: HomeViewModel.trialFocusMinutes)
                } label: {
                    Label("\(HomeViewModel.trialFocusMinutes)分だけ", systemImage: "timer")
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)

            // 今はやらない2つ。どうなるかを小さく添えておく（押しても、下の「元に戻す」で戻せる）
            HStack(spacing: 0) {
                quietButton("あとで", note: "1時間後にまた出します", systemImage: "clock.arrow.circlepath") {
                    viewModel.skipRecommendation()
                }
                .keyboardShortcut("l", modifiers: .command)
                .accessibilityIdentifier("skipButton")

                Divider()
                    .frame(height: 32)

                quietButton("終わった", note: "完了にして次へ", systemImage: "checkmark") {
                    viewModel.completeRecommendation()
                }
                .keyboardShortcut("d", modifiers: .command)
                .accessibilityIdentifier("completeButton")
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
        .task(id: task.id) {
            await viewModel.loadFirstStepIdeas(for: task)
        }
    }

    /// 重く感じやすいタスクに出す「最初の一歩なら」。押すと、その一歩を足して5分だけ取りかかる
    ///
    /// 全体を考えると手が止まるので、最初の5分だけを差し出す。↻ で別の案に替えられる。
    @ViewBuilder
    private func firstStepIdeaRow(for task: TaskItem) -> some View {
        if viewModel.shouldSuggestFirstStep(for: task),
           let ideas = viewModel.firstStepIdeas[task.id] {
            let idea = ideas.steps[firstStepIdeaIndex % ideas.steps.count]

            HStack(spacing: 8) {
                Button {
                    beginWithFirstStep(idea, of: task)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: ideas.isFromAI ? "sparkles" : "shoeprints.fill")
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(ideas.isFromAI ? "AIの案・最初の\(HomeViewModel.ideaStepMinutes)分なら" : "最初の\(HomeViewModel.ideaStepMinutes)分なら")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(idea)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("この一歩を足して、\(HomeViewModel.ideaStepMinutes)分だけ取りかかります")
                .accessibilityIdentifier("firstStepIdeaButton")

                if ideas.steps.count > 1 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            firstStepIdeaIndex += 1
                        }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("ほかの案")
                }
            }
            .padding(12)
            .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            .transition(.opacity)
        }
    }

    /// 案の一歩から始める。設定していれば、ショートカットで集中モードもオンにする
    private func beginWithFirstStep(_ idea: String, of task: TaskItem) {
        guard viewModel.startWithFirstStep(idea, of: task) != nil else {
            return
        }

        if viewModel.focusSession != nil, let url = viewModel.focusShortcutURL(starting: true) {
            openURL(url)
        }
    }

    /// カードの下の段の、控えめなボタン。名前と、押すとどうなるかを縦に並べる
    private func quietButton(
        _ title: LocalizedStringKey,
        note: LocalizedStringKey,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                action()
            }
        } label: {
            VStack(spacing: 2) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline)
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    /// 右上の「…」。めったに使わない操作をまとめる
    private func cardMenu(for task: TaskItem) -> some View {
        Menu {
            Button {
                firstStepTask = task
            } label: {
                Label(stepsButtonTitle(for: task), systemImage: "shoeprints.fill")
            }

            // くり返しの回は、その回だけ休める
            if task.recurringID != nil {
                Button {
                    viewModel.skipOccurrence(task)
                } label: {
                    Label("今回はお休み", systemImage: "moon.zzz")
                }
            }

            if let link = task.link {
                Button {
                    openURL(link)
                } label: {
                    Label("リンクを開く", systemImage: "safari")
                }
            }

            Button {
                editingTaskID = task.id
            } label: {
                Label("編集", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.deleteTask(task)
                }
            } label: {
                Label("削除", systemImage: "trash")
            }
            .accessibilityIdentifier("deleteFromCardButton")
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("ほかの操作")
        .accessibilityIdentifier("cardMenu")
    }

    /// 所要時間・何歩目・決め手を、短い札で並べる。決め手の札を押すと、理由の全文が出る
    private func cardPills(for recommendation: TaskRecommendation) -> some View {
        let task = recommendation.task

        return HStack(spacing: 6) {
            pill(String(localized: "\(task.estimatedMinutes)分"), systemImage: "clock")

            if let progress = stepCountText(for: task) {
                pill(progress, systemImage: "shoeprints.fill")
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isShowingFullReason.toggle()
                }
            } label: {
                pill(recommendation.shortReason, systemImage: "sparkles", tint: .blue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(recommendation.reason)
            .accessibilityHint(isShowingFullReason ? "理由を閉じます" : "理由をくわしく見ます")
        }
        .lineLimit(1)
    }

    private func pill(_ text: String, systemImage: String, tint: Color = .secondary) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .labelStyle(PillLabelStyle())
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12), in: Capsule())
    }

    /// 札のなかの絵と文字を、詰めて並べる
    private struct PillLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 3) {
                configuration.icon
                    .imageScale(.small)
                configuration.title
            }
        }
    }

    /// 推薦できるタスクがないときに、その内訳と次の一手を示す
    private func noRecommendationCard(
        _ summary: NoRecommendationSummary
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if summary.allCompleted {
                Label("すべてのタスクが完了しています", systemImage: "checkmark.circle")
                    .font(.headline)
            } else {
                Label("\(viewModel.availableMinutes)分に入るものはありません", systemImage: "clock")
                    .font(.headline)

                // 隠れているものは隠さず、短い札1行で伝える
                if let breakdown = breakdownText(summary) {
                    Text(breakdown)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    if let suggested = viewModel.suggestedAvailableMinutes {
                        Button("\(suggested)分にする") {
                            viewModel.setAvailableMinutes(suggested)
                        }
                    }

                    if summary.skippedCount > 0 {
                        Button("あとでを戻す") {
                            viewModel.clearSkips()
                        }
                    }
                }
                .buttonStyle(.bordered)

                // 時間に収まらなくても、最初の一歩か5分だけなら始められる
                if let taskID = summary.shortestTooLongTaskID,
                   let task = viewModel.tasks.first(where: { $0.id == taskID }) {
                    VStack(alignment: .leading, spacing: 6) {
                        firstStepIdeaRow(for: task)

                        startShortcuts(for: task)
                    }
                    .task(id: task.id) {
                        await viewModel.loadFirstStepIdeas(for: task)
                    }
                }
            }
        }
        .font(.subheadline)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// 入らない理由の内訳。「長いもの 1件（最短60分）・あとで 1件」のように短く
    private func breakdownText(_ summary: NoRecommendationSummary) -> String? {
        var parts: [String] = []

        if summary.tooLongCount > 0, let shortest = summary.shortestTooLongMinutes {
            parts.append(String(localized: "長いもの \(summary.tooLongCount)件（最短\(shortest)分）"))
        }
        if summary.skippedCount > 0 {
            parts.append(String(localized: "あとで \(summary.skippedCount)件"))
        }
        if summary.waitingForPrerequisitesCount > 0 {
            parts.append(String(localized: "待ち \(summary.waitingForPrerequisitesCount)件"))
        }
        if summary.scheduledLaterCount > 0 {
            parts.append(String(localized: "明日以降 \(summary.scheduledLaterCount)件"))
        }
        if summary.dormantCount > 0 {
            parts.append(String(localized: "冬眠 \(summary.dormantCount)件"))
        }

        guard !parts.isEmpty else {
            return nil
        }
        return parts.joined(separator: String(localized: "weekday.separator", defaultValue: "・", comment: "曜日を並べるときの区切り"))
    }

    // MARK: - ほかのタスク

    /// 「ほかのタスク 5件 ›」。今日の分と「あとで」の数を小さく添え、押すと一覧を開く
    @ViewBuilder
    private var otherTasksRow: some View {
        let current = viewModel.recommendation?.task
        let shownID = current?.parentTaskID ?? current?.id
        let others = viewModel.visibleAllTasks.filter { !$0.isCompleted && $0.id != shownID }

        if !viewModel.tasks.isEmpty {
            NavigationLink {
                allTasksView
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "list.bullet")
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("ほかのタスク \(others.count)件")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)

                        if let detail = otherTasksDetail(excluding: shownID) {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityIdentifier("allTasksButton")
        }
    }

    /// 「今日 2件・あとで 1件」。どちらもなければ nil
    private func otherTasksDetail(excluding shownID: UUID?) -> String? {
        let visibleIDs = Set(viewModel.visibleAllTasks.map(\.id))
        let today = viewModel.todayTasks.filter { !$0.isCompleted && visibleIDs.contains($0.id) && $0.id != shownID }.count
        let skipped = viewModel.skippedTaskIDs.subtracting([shownID].compactMap { $0 }).count

        var parts: [String] = []
        if today > 0 {
            parts.append(String(localized: "今日 \(today)件"))
        }
        if skipped > 0 {
            parts.append(String(localized: "あとで \(skipped)件"))
        }

        guard !parts.isEmpty else {
            return nil
        }
        return parts.joined(separator: String(localized: "weekday.separator", defaultValue: "・", comment: "曜日を並べるときの区切り"))
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

    /// 真ん中下の大きな＋。押すと、1行で書く入力欄が開く
    private var addButton: some View {
        Button {
            isQuickAddOpen = true
            isQuickAddFocused = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(.blue, in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("n", modifiers: .command)
        .accessibilityLabel("タスクを追加")
        .accessibilityIdentifier("addButton")
    }

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
            let when = full.deadline.map { (String(localized: "期限 \(viewModel.describeQuickAddDate($0, includesTime: full.includesTime))"), "flag") }
                ?? full.scheduledDate.map { (viewModel.describeQuickAddDate($0, includesTime: full.includesTime), "calendar") }

            if when != nil || full.durationWasWritten || full.isLight || full.recurrence != nil || full.unrenamedTitle != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if let when {
                            quickAddChip(when.0, systemImage: when.1, part: .when)
                        }

                        if full.durationWasWritten {
                            quickAddChip(String(localized: "\(full.estimatedMinutes)分"), systemImage: "clock", part: .duration)
                        }

                        if full.isLight {
                            quickAddChip(String(localized: "軽い作業"), systemImage: "leaf", part: .light)
                        }

                        if let recurrence = full.recurrence {
                            quickAddChip(recurrence.summary, systemImage: "repeat", part: .repeat)
                        }

                        if full.unrenamedTitle != nil {
                            quickAddChip(String(localized: "「\(full.title)」にする"), systemImage: "wand.and.stars", part: .rename)
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

            TextField("思いついたまま書く（例：明日までに請求書送らないと）", text: $quickAddText)
                .submitLabel(.done)
                .focused($isQuickAddFocused)
                .onSubmit(submitQuickAdd)
                .accessibilityIdentifier("quickAddField")

            if quickAddText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // 日付や優先度を自分で選びたいときの入り口
                Button("詳しく") {
                    isQuickAddFocused = false
                    isShowingAddTask = true
                }
                .font(.subheadline)
                .accessibilityIdentifier("detailedAddButton")
            } else {
                Button("追加", action: submitQuickAdd)
                    .fontWeight(.semibold)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        // 後ろのカードと溶け合わないよう、少し浮かせる
        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
    }

    private func submitQuickAdd() {
        if viewModel.quickAdd(quickAddText, ignoring: ignoredQuickAddParts) {
            quickAddText = ""
            ignoredQuickAddParts = []
        }
    }

    // MARK: - 遷移先

    private var allTasksView: some View {
        AllTasksView(
            tasks: viewModel.visibleAllTasks,
            dormantTaskIDs: viewModel.dormantTaskIDs,
            tomorrowTaskIDs: Set(viewModel.tomorrowTasks.map(\.id)),
            pinnedTaskIDs: viewModel.pinnedTaskIDs,
            recurringTasks: viewModel.recurringTasks,
            hiddenCompletedTasks: viewModel.hiddenCompletedTasks,
            todayTaskIDs: Set(viewModel.todayTasks.map(\.id)),
            skippedTaskIDs: viewModel.skippedTaskIDs,
            currentTaskID: viewModel.recommendation.map { $0.task.parentTaskID ?? $0.task.id },
            carriedOverTasks: viewModel.carriedOverTasks,
            stepNotes: Dictionary(
                uniqueKeysWithValues: viewModel.visibleAllTasks.compactMap { task in
                    stepProgressText(for: task).map { (task.id, $0) }
                }
            ),
            onToggleCompletion: { task in
                viewModel.toggleCompletion(for: task)
            },
            onDelete: { task in
                viewModel.deleteTask(task)
            },
            onStartNow: { task in
                beginFocus(on: task.id)
            },
            onUpdate: { updatedTask, lowering in
                viewModel.updateTask(updatedTask, lowering: lowering)
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
        .undoBanner()
    }

    private func editView(for task: TaskItem) -> some View {
        EditTaskView(
            task: task,
            allTasks: viewModel.allTasks,
            onSave: { updatedTask, lowering in
                viewModel.updateTask(updatedTask, lowering: lowering)
            },
            onSplit: { parts in
                viewModel.splitTask(task, into: parts)
            },
            onAddFirstStep: { title, minutes in
                viewModel.addFirstStep(for: task, title: title, minutes: minutes)
            },
            onDelete: {
                viewModel.deleteTask(task)
            }
        )
        .undoBanner()
    }

    // MARK: - ウィジェットから開いたとき

    /// ウィジェットやライブアクティビティのURL（`WidgetLink`）に合わせて動く
    private func handle(_ url: URL) {
        guard let link = WidgetLink(url: url) else {
            return
        }

        switch link {
        case .home:
            break

        case .add:
            isQuickAddOpen = true
            isQuickAddFocused = true

        case .focus(let taskID, let trialMinutes):
            // もう集中しているなら、その画面に戻るだけ
            guard viewModel.focusSession == nil else {
                return
            }
            beginFocus(on: taskID, trialMinutes: trialMinutes)
        }
    }

    // MARK: - 集中の始めと終わり

    /// 集中を始める。設定していれば、ショートカットで iPhone の集中モードもオンにする
    private func beginFocus(on taskID: UUID? = nil, trialMinutes: Int? = nil) {
        viewModel.startFocus(on: taskID, trialMinutes: trialMinutes)

        if viewModel.focusSession != nil, let url = viewModel.focusShortcutURL(starting: true) {
            openURL(url)
        }
    }

    /// 集中を終える。設定していれば、ショートカットで集中モードをオフにする
    private func endFocus(completing: Bool) {
        let wasFocusing = viewModel.focusSession != nil
        viewModel.finishFocus(completing: completing)

        if wasFocusing, let url = viewModel.focusShortcutURL(starting: false) {
            openURL(url)
        }
    }

    // MARK: - 取りかかる入り口

    /// 一歩がまだなければ「最初の一歩を決める」、あれば一覧を開く言葉にする
    private func stepsButtonTitle(for task: TaskItem) -> String {
        if task.parentTaskID != nil {
            return String(localized: "ほかの一歩を見る")
        }
        return viewModel.steps(of: task.id).isEmpty ? String(localized: "最初の一歩を決める") : String(localized: "一歩を見る")
    }

    /// 一歩ずつ進めている元のタスクなら「一歩ずつ・2/3 済み」
    private func stepProgressText(for task: TaskItem) -> String? {
        let steps = viewModel.steps(of: task.id)
        guard !steps.isEmpty else {
            return nil
        }
        return String(localized: "一歩ずつ・\(steps.filter(\.isCompleted).count)/\(steps.count) 済み")
    }

    /// 札に出す短い進み具合。「2/3歩」
    private func stepCountText(for task: TaskItem) -> String? {
        let steps = viewModel.steps(of: task.id)
        guard !steps.isEmpty else {
            return nil
        }
        return String(localized: "\(steps.filter(\.isCompleted).count)/\(steps.count)歩")
    }

    /// 「5分だけやる」「最初の一歩を決める」。全部やる気になれなくても、手をつけられるようにする
    private func startShortcuts(for task: TaskItem) -> some View {
        HStack(spacing: 16) {
            Button {
                beginFocus(on: task.id, trialMinutes: HomeViewModel.trialFocusMinutes)
            } label: {
                Label("\(HomeViewModel.trialFocusMinutes)分だけやる", systemImage: "timer")
            }

            Button {
                firstStepTask = task
            } label: {
                Label(stepsButtonTitle(for: task), systemImage: "shoeprints.fill")
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

    // MARK: - 何度も見送られるタスク

    /// 責めずに、小さくするか、いったん眠らせるかを選べるようにする
    private func repeatedSkipOffer(for task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "shoeprints.fill")
                    .foregroundStyle(.orange)

                Text("「\(task.title)」は、今は手が出にくいのかもしれません。小さくしてみますか？")
                    .font(.subheadline)

                Spacer(minLength: 0)

                Button {
                    viewModel.dismissRepeatedSkipOffer()
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("閉じる")
            }

            HStack(spacing: 10) {
                Button(stepsButtonTitle(for: task)) {
                    viewModel.dismissRepeatedSkipOffer()
                    firstStepTask = task
                }

                Button("冬眠させる") {
                    viewModel.hibernate(task)
                }
            }
            .buttonStyle(.bordered)
            .font(.subheadline)
        }
        .padding(12)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 手放す

    /// 長く冬眠しているタスクがあるときに、月に1回だけ出す
    private var letGoOffer: some View {
        HStack(spacing: 12) {
            Image(systemName: "archivebox")
                .foregroundStyle(.secondary)

            Text("長く冬眠しているタスクが\(viewModel.longDormantTasks.count)件あります。手放しますか？")
                .font(.subheadline)

            Spacer(minLength: 0)

            Button("見る") {
                isShowingLetGo = true
            }
            .font(.subheadline)
            .fontWeight(.semibold)

            Button {
                viewModel.dismissLetGoOffer()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("閉じる")
        }
        .padding(12)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 気が乗らないとき

    /// 軽い・短い作業だけにする切り替え。いつでも押せる
    ///
    /// 名前は「軽いものだけ」のまま変えず、オンのときは塗りとチェックで示す（押すと名前が変わると、今どちらか分からないため）
    private var lightModeToggle: some View {
        let isOn = viewModel.prefersLight

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.setPrefersLight(!isOn)
            }
        } label: {
            Label("軽いものだけ", systemImage: isOn ? "checkmark" : "leaf")
                // ツールバーではアイコンだけになるので、名前も必ず出す（今どちらか分かるように）
                .labelStyle(.titleAndIcon)
                .font(.footnote)
                .fontWeight(isOn ? .semibold : .regular)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(isOn ? Color.white : Color.secondary)
                .background(isOn ? Color.green : Color.secondary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? Text("オン") : Text("オフ"))
        .accessibilityHint(isOn ? "ふだんの推薦に戻します" : "軽い作業と短い作業だけを推薦します")
        .accessibilityIdentifier("lightModeToggle")
    }

    /// 軽いものだけにしているあいだ、今の選び方を1行で伝える
    private var lightModeStatus: some View {
        Label("いまは軽いものだけを出しています", systemImage: "leaf.fill")
            .font(.caption)
            .foregroundStyle(.green)
            .transition(.opacity)
    }

    /// 「今はやらない」のあとに出す、軽いものへの逃げ道
    private var lightModeOffer: some View {
        HStack(spacing: 12) {
            Image(systemName: "leaf")
                .foregroundStyle(.green)

            Text("軽いものだけにしますか？")
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
