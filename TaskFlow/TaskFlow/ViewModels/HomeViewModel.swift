import Foundation
import Combine

@MainActor
final class HomeViewModel: ObservableObject {

    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var recommendation: TaskRecommendation?

    /// 推薦がないときの内訳。推薦があるときはnil
    @Published private(set) var noRecommendationSummary: NoRecommendationSummary?

    /// 今回タスクに使える時間（分）
    @Published private(set) var availableMinutes = HomeViewModel.defaultAvailableMinutes

    /// 直前に推薦カードから完了にしたタスク（完了前の状態）。「元に戻す」に使う
    @Published private(set) var lastCompletedTask: TaskItem?

    /// 集中して取りかかっているタスク
    @Published private(set) var focusSession: FocusSession?

    struct FocusSession: Equatable {
        let taskID: UUID
        let startedAt: Date
    }

    /// 「今はやらない」にしたタスクと、推薦に戻る日時
    private var skippedUntil: [UUID: Date] = [:]

    private let decisionEngine = DecisionEngine()
    private let userDefaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date
    private let tasksStorageKey = "taskFlow.tasks"
    private let availableMinutesStorageKey = "taskFlow.availableMinutes"
    private let skippedUntilStorageKey = "taskFlow.skippedUntil"

    /// 「今はやらない」で推薦から外す時間
    nonisolated static let skipDuration: TimeInterval = 60 * 60

    /// 1行で追加したとき、時間が書かれていなければ使う所要時間（分）
    nonisolated static let defaultQuickAddMinutes = 30

    /// 読み込めなかった保存データの退避先キーの接頭辞
    static let unreadableTasksKeyPrefix = "taskFlow.tasks.unreadable."

    /// ホームで選べる空き時間（分）
    nonisolated static let availableMinuteOptions = [15, 30, 45, 60, 90]
    nonisolated static let defaultAvailableMinutes = 45

    /// 空き時間に収まらないタスクがあるとき、取りかかれるようになる最小の選択肢
    var suggestedAvailableMinutes: Int? {
        guard let shortest = noRecommendationSummary?.shortestTooLongMinutes else {
            return nil
        }

        return Self.availableMinuteOptions.first { $0 >= shortest }
    }

    /// 今日の欄に出すタスク
    ///
    /// 予定日が今日のものに加え、期限が今日のものと、予定日や期限を過ぎた未完了タスク（持ち越し）を含める。
    /// 冬眠中のタスクは出さない。
    var todayTasks: [TaskItem] {
        let currentDate = now()

        return tasks.filter { task in
            guard !task.isDormant(at: currentDate, calendar: calendar) else {
                return false
            }

            if let scheduledDate = task.scheduledDate,
               calendar.isDate(scheduledDate, inSameDayAs: currentDate) {
                return true
            }

            if let deadline = task.deadline,
               calendar.isDate(deadline, inSameDayAs: currentDate) {
                return true
            }

            return isCarriedOver(task)
        }
    }

    /// 明日の欄に出すタスク。今日の欄に出るものは重ねて出さない
    var tomorrowTasks: [TaskItem] {
        let currentDate = now()
        let todayTaskIDs = Set(todayTasks.map(\.id))

        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: currentDate) else {
            return []
        }

        return tasks.filter { task in
            guard let scheduledDate = task.scheduledDate,
                  !todayTaskIDs.contains(task.id),
                  !task.isDormant(at: currentDate, calendar: calendar) else {
                return false
            }

            return calendar.isDate(scheduledDate, inSameDayAs: tomorrow)
        }
    }

    /// 予定日か期限が昨日以前のまま、まだ終わっていないタスクか
    func isCarriedOver(_ task: TaskItem) -> Bool {
        guard !task.isCompleted else {
            return false
        }

        let startOfToday = calendar.startOfDay(for: now())

        if let scheduledDate = task.scheduledDate, scheduledDate < startOfToday {
            return true
        }

        if let deadline = task.deadline, deadline < startOfToday {
            return true
        }

        return false
    }

    /// 冬眠中のタスクのID
    var dormantTaskIDs: Set<UUID> {
        let currentDate = now()

        return Set(
            tasks
                .filter { $0.isDormant(at: currentDate, calendar: calendar) }
                .map(\.id)
        )
    }

    var allTasks: [TaskItem] {
        tasks
    }

    /// - Parameters:
    ///   - userDefaults: タスクの保存先。テストでは専用のスイートを渡す
    ///   - seedsSampleTasks: 保存データがないときにサンプルタスクを入れるか
    ///   - calendar: 今日・明日の判定に使う暦
    ///   - now: 現在時刻。テストでは固定した時刻を返す
    init(
        userDefaults: UserDefaults = .standard,
        seedsSampleTasks: Bool = HomeViewModel.seedsSampleTasksByDefault,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { Date() }
    ) {
        self.userDefaults = userDefaults
        self.calendar = calendar
        self.now = now

        let savedMinutes = userDefaults.integer(forKey: availableMinutesStorageKey)
        if Self.availableMinuteOptions.contains(savedMinutes) {
            availableMinutes = savedMinutes
        }

        switch loadTasks() {
        case .loaded(let savedTasks):
            tasks = savedTasks

        case .notFound:
            if seedsSampleTasks {
                loadSampleTasks()
            }

        case .unreadable(let data):
            // 次の保存で上書きされて失われないよう、元のデータを退避しておく
            backUpUnreadableTasks(data)
        }

        skippedUntil = loadSkippedUntil()

        updateRecommendation()
    }

    /// サンプルタスクは開発中のビルドでのみ入れる
    nonisolated static var seedsSampleTasksByDefault: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// 空き時間を変更し、推薦を計算し直す
    func setAvailableMinutes(_ minutes: Int) {
        guard minutes > 0, minutes != availableMinutes else {
            return
        }

        availableMinutes = minutes
        userDefaults.set(minutes, forKey: availableMinutesStorageKey)
        updateRecommendation()
    }

    // MARK: - 推薦カードからの操作

    /// 推薦中のタスクを完了にし、「元に戻す」ができるよう完了前の状態を覚えておく
    func completeRecommendation() {
        guard let task = recommendation?.task else {
            return
        }

        complete(task)
    }

    /// 直前に完了にしたタスクを未完了に戻す
    func undoLastCompletion() {
        guard let task = lastCompletedTask,
              let index = tasks.firstIndex(where: { $0.id == task.id }),
              tasks[index].isCompleted else {
            lastCompletedTask = nil
            return
        }

        tasks[index].isCompleted = false
        tasks[index].updatedAt = now()
        lastCompletedTask = nil
        saveTasks()
        updateRecommendation()
    }

    /// 「元に戻す」の表示を閉じる
    func dismissUndo() {
        lastCompletedTask = nil
    }

    /// 推薦中のタスクを、しばらく推薦から外す。理由は聞かない
    func skipRecommendation() {
        guard let task = recommendation?.task else {
            return
        }

        skippedUntil[task.id] = now().addingTimeInterval(Self.skipDuration)
        saveSkippedUntil()
        updateRecommendation()
    }

    /// 「今はやらない」をすべて取り消す
    func clearSkips() {
        skippedUntil.removeAll()
        saveSkippedUntil()
        updateRecommendation()
    }

    /// 推薦中のタスクに集中して取りかかる
    func startFocus() {
        guard let task = recommendation?.task,
              let index = tasks.firstIndex(where: { $0.id == task.id }) else {
            return
        }

        tasks[index].updatedAt = now()
        focusSession = FocusSession(taskID: task.id, startedAt: now())
        saveTasks()
    }

    /// 集中しているタスク
    var focusedTask: TaskItem? {
        guard let taskID = focusSession?.taskID else {
            return nil
        }

        return tasks.first { $0.id == taskID }
    }

    /// 集中を終える。`completing` が true ならタスクを完了にする
    func finishFocus(completing: Bool) {
        if completing, let task = focusedTask {
            complete(task)
        }

        focusSession = nil
    }

    /// 1行の入力からタスクを追加する。「請求書を送る 15分」のように時間を書ける
    ///
    /// - Returns: 追加できたら true（タイトルが空なら false）
    @discardableResult
    func quickAdd(_ text: String) -> Bool {
        guard let parsed = QuickAddParser.parse(
            text,
            defaultMinutes: Self.defaultQuickAddMinutes
        ) else {
            return false
        }

        addTask(
            title: parsed.title,
            estimatedMinutes: parsed.estimatedMinutes,
            priority: .medium,
            scheduledDate: nil,
            deadline: nil
        )
        return true
    }

    private func complete(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }),
              !tasks[index].isCompleted else {
            return
        }

        lastCompletedTask = tasks[index]
        tasks[index].isCompleted = true
        tasks[index].updatedAt = now()
        skippedUntil[task.id] = nil
        saveTasks()
        saveSkippedUntil()
        updateRecommendation()
    }

    private func loadSkippedUntil() -> [UUID: Date] {
        guard let data = userDefaults.data(forKey: skippedUntilStorageKey),
              let saved = try? JSONDecoder().decode([UUID: Date].self, from: data) else {
            return [:]
        }

        return saved
    }

    private func saveSkippedUntil() {
        guard let data = try? JSONEncoder().encode(skippedUntil) else {
            return
        }

        userDefaults.set(data, forKey: skippedUntilStorageKey)
    }

    /// 新しいタスクを追加する
    func addTask(
        title: String,
        estimatedMinutes: Int,
        priority: TaskPriority,
        scheduledDate: Date?,
        deadline: Date?
    ) {
        let task = TaskItem(
            title: title,
            estimatedMinutes: estimatedMinutes,
            priority: priority,
            scheduledDate: scheduledDate,
            deadline: deadline,
            updatedAt: now()
        )

        tasks.append(task)
        saveTasks()
        updateRecommendation()
    }
    
    /// タスクの完了状態を切り替える
    func toggleCompletion(for task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else {
            return
        }

        tasks[index].isCompleted.toggle()
        tasks[index].updatedAt = now()
        saveTasks()
        updateRecommendation()
    }

    /// 冬眠中のタスクを起こす。触れた日時を今にして、推薦と今日・明日の欄に戻す
    func wakeTask(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else {
            return
        }

        tasks[index].updatedAt = now()
        saveTasks()
        updateRecommendation()
    }

    /// 大きいタスクを、順番につながった小さいタスクに置き換える
    func splitTask(_ task: TaskItem, into parts: [TaskSplitPart]) {
        let splitTasks = TaskSplitter.split(
            task,
            into: parts,
            in: tasks,
            now: now()
        )

        guard splitTasks != tasks else {
            return
        }

        tasks = splitTasks
        saveTasks()
        updateRecommendation()
    }

    /// 指定したタスクを削除する
    func deleteTask(_ task: TaskItem) {
        tasks.removeAll { $0.id == task.id }

        // 削除したタスクを前提にしていたタスクが、推薦されないまま残らないようにする
        for index in tasks.indices {
            tasks[index].prerequisiteIDs.removeAll { $0 == task.id }
        }

        saveTasks()
        updateRecommendation()
    }
    
    /// 既存タスクの内容を更新する
    func updateTask(_ updatedTask: TaskItem) {
        guard let index = tasks.firstIndex(
            where: { $0.id == updatedTask.id }
        ) else {
            return
        }

        tasks[index] = updatedTask
        tasks[index].updatedAt = now()
        saveTasks()
        updateRecommendation()
    }
    
    /// 現在のタスク一覧をUserDefaultsへ保存する
    private func saveTasks() {
        guard let data = try? JSONEncoder().encode(tasks) else {
            return
        }

        userDefaults.set(data, forKey: tasksStorageKey)
    }

    private enum LoadResult {
        case loaded([TaskItem])
        case notFound
        case unreadable(Data)
    }

    /// UserDefaultsから保存済みのタスク一覧を読み込む
    private func loadTasks() -> LoadResult {
        guard let data = userDefaults.data(
            forKey: tasksStorageKey
        ) else {
            return .notFound
        }

        guard let savedTasks = try? JSONDecoder().decode(
            [TaskItem].self,
            from: data
        ) else {
            return .unreadable(data)
        }

        return .loaded(savedTasks)
    }

    /// 読み込めなかった保存データを、日時つきの別キーへ退避する
    private func backUpUnreadableTasks(_ data: Data) {
        let timestamp = ISO8601DateFormatter().string(from: Date())

        userDefaults.set(
            data,
            forKey: Self.unreadableTasksKeyPrefix + timestamp
        )

        // 起動のたびに同じデータを退避し直さないよう、元のキーは空にする
        userDefaults.removeObject(forKey: tasksStorageKey)
    }

    /// 現在のタスク一覧から推薦を再計算する
    func updateRecommendation() {
        let currentDate = now()

        // 時間が過ぎたものと、なくなったタスクの「今はやらない」を外す
        let taskIDs = Set(tasks.map(\.id))
        let activeSkips = skippedUntil.filter { taskIDs.contains($0.key) && $0.value > currentDate }
        if activeSkips.count != skippedUntil.count {
            skippedUntil = activeSkips
            saveSkippedUntil()
        }

        let context = DecisionContext(
            availableMinutes: availableMinutes,
            currentDate: currentDate,
            skippedTaskIDs: Set(skippedUntil.keys)
        )

        recommendation = decisionEngine.recommend(
            from: tasks,
            context: context
        )

        noRecommendationSummary = recommendation == nil
            ? decisionEngine.summarizeNoRecommendation(from: tasks, context: context)
            : nil
    }

    /// 開発中の動作確認用サンプルデータ
    private func loadSampleTasks() {
        let currentDate = now()

        let preparationTask = TaskItem(
            title: "開発環境を確認する",
            isCompleted: true,
            estimatedMinutes: 10
        )

        let implementationTask = TaskItem(
            title: "TaskFlowの画面を実装する",
            estimatedMinutes: 30,
            scheduledDate: currentDate,
            deadline: currentDate.addingTimeInterval(60 * 60),
            prerequisiteIDs: [preparationTask.id]
        )

        let documentTask = TaskItem(
            title: "READMEを整理する",
            estimatedMinutes: 15,
            deadline: currentDate.addingTimeInterval(60 * 60 * 24)
        )

        tasks = [
            preparationTask,
            implementationTask,
            documentTask
        ]
    }
}
