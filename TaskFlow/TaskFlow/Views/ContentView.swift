import SwiftUI

struct ContentView: View {

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @StateObject private var viewModel = HomeViewModel.makeForApp()
    @State private var isShowingAddTask = false
    @State private var isTodayExpanded = false
    @State private var editingTaskID: UUID?
    @State private var quickAddText = ""
    @State private var ignoredQuickAddParts: Set<QuickAddParser.Part> = []
    @State private var celebration: Celebration?
    @State private var isShowingDoneToday = false
    @State private var isShowingCarryOver = false
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

                        // 「あとで」にしたものも、1時間待たずにいつでも戻せる
                        if viewModel.recommendation != nil, viewModel.skippedTaskCount > 0 {
                            skippedRow
                        }

                        todaySection

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
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        allTasksView
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .accessibilityLabel("すべてのタスク")
                    .accessibilityIdentifier("allTasksButton")
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

            Text("下の＋を押して「明日までにレポート書かないと 30分」のように書くと、そのまま追加できます。")
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

    /// 今の1つ。取りかかる操作（始める・5分だけ）だけを大きくし、完了は名前の横の丸、
    /// 見送りは控えめな文字、ほかの操作は右上の「…」にまとめる（並んだボタンで迷わせないため）
    private func recommendationCard(
        _ recommendation: TaskRecommendation
    ) -> some View {
        let task = recommendation.task

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                completeCheck(for: task)

                Text(task.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("recommendationTitle")

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

            // 見送っても責めない。どうなるか（1時間後にまた出る）を先に見せておく
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.skipRecommendation()
                }
            } label: {
                VStack(spacing: 2) {
                    Text("あとで")
                        .font(.subheadline)
                    Text("1時間後にまた出します")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .keyboardShortcut("l", modifiers: .command)
            .accessibilityIdentifier("skipButton")
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

    /// 「あとでにした2件を戻す」。押すと、あとでにしたものがまた推薦に入る（これも元に戻せる）
    private var skippedRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.clearSkips()
            }
        } label: {
            Label("あとでにした\(viewModel.skippedTaskCount)件を戻す", systemImage: "arrow.uturn.backward")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("restoreSkippedButton")
    }

    /// 名前の横の丸。押すと完了（「元に戻す」がすぐ出るので、確かめはしない）
    private func completeCheck(for task: TaskItem) -> some View {
        Button {
            viewModel.completeRecommendation()
        } label: {
            Image(systemName: "circle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(.top, 1)
        .keyboardShortcut("d", modifiers: .command)
        .accessibilityLabel("完了にする")
        .accessibilityIdentifier("completeButton")
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

            if let position = viewModel.stepPosition(of: task) {
                pill(String(localized: "\(position.index)歩目"), systemImage: "shoeprints.fill")
                    .accessibilityLabel("「\(CompletionMessages.baseTitle(of: position.parentTitle))」の\(position.index)歩目")
            } else if let progress = stepCountText(for: task) {
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

                        // 時間に入らない大きいタスクこそ、最初の5分の案があると手をつけやすい
                        firstStepIdeaRow(for: task)

                        startShortcuts(for: task)
                    }
                    .padding(.top, 6)
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
                                ? String(localized: "持ち越し")
                                : viewModel.pinnedTaskIDs.contains(task.id) ? String(localized: "今日やりたい") : nil,
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
