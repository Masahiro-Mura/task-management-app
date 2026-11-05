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

        /// 「5分だけやる」のときの目安（分）。nilならタスクの所要時間が目安
        var trialMinutes: Int?
    }

    /// 「5分だけやる」の時間（分）
    nonisolated static let trialFocusMinutes = 5

    /// 「最初の一歩」の所要時間の初期値（分）
    nonisolated static let defaultFirstStepMinutes = 10

    /// 一歩を終えたあとに「次の一歩を決めますか？」と聞く元のタスク
    @Published private(set) var nextStepCandidate: TaskItem?

    /// 「今はやらない」にしたタスクと、推薦に戻る日時
    private var skippedUntil: [UUID: Date] = [:]

    /// 気が乗らないので、軽い・短い作業だけを推薦しているか
    @Published private(set) var prefersLight = false

    /// 「今はやらない」のあとに「軽いものにしますか」と聞いているか
    @Published private(set) var isOfferingLightMode = false

    /// 軽い作業だけにしたら候補がなくなったか（ふだんの推薦ならある）
    @Published private(set) var lightModeHasNoMatch = false

    /// 優先度「高」にできるタスクの数
    nonisolated static let maxHighPriorityTasks = 3

    /// くり返すタスクのひな形
    @Published private(set) var recurringTasks: [RecurringTask] = []
    private let recurringStorageKey = "taskFlow.recurring"

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

            if task.isPinnedForToday(at: currentDate, calendar: calendar) {
                return true
            }

            return isCarriedOver(task)
        }
    }

    /// 今日「今日やりたい」の印が付いているタスクのID
    var pinnedTaskIDs: Set<UUID> {
        let currentDate = now()
        return Set(tasks.filter { $0.isPinnedForToday(at: currentDate, calendar: calendar) }.map(\.id))
    }

    /// 今日の欄にある持ち越し（冬眠中を除く）
    var carriedOverTasks: [TaskItem] {
        todayTasks.filter { isCarriedOver($0) }
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

    // MARK: - 片づけ（完了を隠す・手放す）

    /// 完了してからこの日数がたったものは、一覧から隠す（消さない）
    nonisolated static let completedHideDays = 7

    /// この日数触っていない冬眠中のタスクは、「手放しますか？」と聞く
    nonisolated static let letGoDormantDays = 60

    /// 「手放しますか？」を聞く間隔（日）
    nonisolated static let letGoPromptIntervalDays = 30

    /// 手放したタスク（削除ではなく保管）
    @Published private(set) var archivedTasks: [TaskItem] = []
    private let archivedStorageKey = "taskFlow.archived"
    private let lastLetGoPromptStorageKey = "taskFlow.lastLetGoPrompt"

    private func isOldCompleted(_ task: TaskItem) -> Bool {
        guard task.isCompleted else {
            return false
        }

        let completedAt = task.completedAt ?? task.updatedAt
        let limit = now().addingTimeInterval(-TimeInterval(Self.completedHideDays) * 24 * 60 * 60)
        return completedAt <= limit
    }

    /// 「すべてのタスク」に出すもの。完了して7日たったものは除く
    var visibleAllTasks: [TaskItem] {
        tasks.filter { !isOldCompleted($0) && $0.parentTaskID == nil }
    }

    /// 完了して7日たち、一覧から隠しているもの
    var hiddenCompletedTasks: [TaskItem] {
        tasks.filter { isOldCompleted($0) }
    }

    /// 長く冬眠しているタスク（手放す候補）
    var longDormantTasks: [TaskItem] {
        let currentDate = now()
        let limit = currentDate.addingTimeInterval(-TimeInterval(Self.letGoDormantDays) * 24 * 60 * 60)

        return tasks.filter { $0.isDormant(at: currentDate, calendar: calendar) && $0.updatedAt <= limit }
    }

    /// 「手放しますか？」をホームに出すか。長く冬眠しているものがあり、前に聞いてから30日たっていれば
    var shouldOfferLetGo: Bool {
        guard !longDormantTasks.isEmpty else {
            return false
        }

        guard let last = userDefaults.object(forKey: lastLetGoPromptStorageKey) as? Date else {
            return true
        }

        return now().timeIntervalSince(last) >= TimeInterval(Self.letGoPromptIntervalDays) * 24 * 60 * 60
    }

    /// 選んだタスクを手放す（保管に移す）。推薦や一覧には出なくなる
    func letGo(_ taskIDs: Set<UUID>) {
        let moving = tasks.filter { taskIDs.contains($0.id) }
        guard !moving.isEmpty else {
            return
        }

        tasks.removeAll { taskIDs.contains($0.id) }
        archivedTasks.append(contentsOf: moving)
        userDefaults.set(now(), forKey: lastLetGoPromptStorageKey)

        saveArchivedTasks()
        saveTasks()
        updateRecommendation()
        objectWillChange.send()
    }

    /// 「手放しますか？」を、また30日あとまで聞かない
    func dismissLetGoOffer() {
        userDefaults.set(now(), forKey: lastLetGoPromptStorageKey)
        objectWillChange.send()
    }

    /// 保管から戻す。触れた日時を今にするので、冬眠からも起きる
    func restoreArchived(_ task: TaskItem) {
        guard let index = archivedTasks.firstIndex(where: { $0.id == task.id }) else {
            return
        }

        var restored = archivedTasks.remove(at: index)
        restored.updatedAt = now()
        tasks.append(restored)

        saveArchivedTasks()
        saveTasks()
        updateRecommendation()
    }

    /// 保管したものを完全に消す
    func deleteArchived(_ task: TaskItem) {
        archivedTasks.removeAll { $0.id == task.id }
        saveArchivedTasks()
    }

    private func loadArchivedTasks() -> [TaskItem] {
        guard let data = userDefaults.data(forKey: archivedStorageKey),
              let saved = try? JSONDecoder().decode([TaskItem].self, from: data) else {
            return []
        }
        return saved
    }

    private func saveArchivedTasks() {
        guard let data = try? JSONEncoder().encode(archivedTasks) else {
            return
        }
        userDefaults.set(data, forKey: archivedStorageKey)
    }

    // MARK: - 書き出し・読み込み

    /// すべてのタスク・くり返し・保管を、JSONで書き出す
    func makeBackup() -> Data {
        let backup = BackupFile(
            version: BackupFile.currentVersion,
            exportedAt: now(),
            tasks: tasks,
            recurringTasks: recurringTasks,
            archivedTasks: archivedTasks
        )
        return (try? BackupFile.encoder().encode(backup)) ?? Data()
    }

    /// 書き出したファイルの名前（「TaskFlow-2026-11-05.json」）
    var backupFileName: String {
        let components = calendar.dateComponents([.year, .month, .day], from: now())
        return String(
            format: "TaskFlow-%04d-%02d-%02d.json",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    /// 書き出したファイルを読み込む。今あるものは消さず、まだないもの（IDで判断）だけを足す
    @discardableResult
    func importBackup(_ data: Data) throws -> BackupImportSummary {
        guard let backup = try? BackupFile.decoder().decode(BackupFile.self, from: data) else {
            throw BackupError.unreadable
        }

        guard backup.version <= BackupFile.currentVersion else {
            throw BackupError.newerVersion
        }

        let existingTaskIDs = Set(tasks.map(\.id)).union(archivedTasks.map(\.id))
        let newTasks = backup.tasks.filter { !existingTaskIDs.contains($0.id) }
        let newArchived = backup.archivedTasks.filter { !existingTaskIDs.contains($0.id) }

        let existingRecurringIDs = Set(recurringTasks.map(\.id))
        let newRecurring = backup.recurringTasks.filter { !existingRecurringIDs.contains($0.id) }

        tasks.append(contentsOf: newTasks)
        archivedTasks.append(contentsOf: newArchived)
        recurringTasks.append(contentsOf: newRecurring)

        saveTasks()
        saveArchivedTasks()
        saveRecurringTasks()
        updateRecommendation()

        return BackupImportSummary(
            addedTasks: newTasks.count,
            addedRecurringTasks: newRecurring.count,
            addedArchivedTasks: newArchived.count
        )
    }

    // MARK: - 初回の案内

    private let onboardingStorageKey = "taskFlow.onboarded"

    /// 設定の「使い方をもう一度見る」で出しているか
    @Published private(set) var isOnboardingRequested = false

    /// 案内を出すか（初めてでタスクもくり返しもないとき、または設定から頼まれたとき）
    var needsOnboarding: Bool {
        isOnboardingRequested
            || (!userDefaults.bool(forKey: onboardingStorageKey) && tasks.isEmpty && recurringTasks.isEmpty)
    }

    /// 案内を見終えた。`addExamples` なら、試すための例を入れる
    func finishOnboarding(addExamples: Bool) {
        userDefaults.set(true, forKey: onboardingStorageKey)
        isOnboardingRequested = false

        if addExamples {
            quickAdd("メールを1通返す 10分")
            quickAdd("明日までに企画のメモを書く 30分")
            quickAdd("部屋の片付け 90分")
        }

        objectWillChange.send()
    }

    /// 設定から、案内をもう一度見られるようにする
    func showOnboardingAgain() {
        isOnboardingRequested = true
    }

    // MARK: - 通知

    private let notifier: NotificationScheduling

    /// 期限が近いのに終わっていないとき、1回だけ知らせる
    @Published private(set) var deadlineNotificationsEnabled = false

    /// 毎日1回「今の1つ」を届ける
    @Published private(set) var dailyPickEnabled = false

    /// 「今の1つ」を届ける時刻（0時からの分）
    @Published private(set) var dailyPickMinutes = HomeViewModel.defaultDailyPickMinutes

    /// 続けて開かれなかったので、毎日の通知を自動で止めたか
    @Published private(set) var dailyPickPausedByIgnore = false

    /// 通知が許可されていなかったか
    @Published private(set) var notificationPermissionDenied = false

    nonisolated static let defaultDailyPickMinutes = 8 * 60

    private enum NotificationKey {
        static let deadline = "taskFlow.notify.deadline"
        static let daily = "taskFlow.notify.daily"
        static let dailyMinutes = "taskFlow.notify.dailyMinutes"
        static let ignored = "taskFlow.notify.dailyIgnored"
        static let paused = "taskFlow.notify.dailyPausedByIgnore"
        static let lastDailyFire = "taskFlow.notify.lastDailyFire"
    }

    private func loadNotificationSettings() {
        deadlineNotificationsEnabled = userDefaults.bool(forKey: NotificationKey.deadline)
        dailyPickEnabled = userDefaults.bool(forKey: NotificationKey.daily)
        dailyPickPausedByIgnore = userDefaults.bool(forKey: NotificationKey.paused)

        if let minutes = userDefaults.object(forKey: NotificationKey.dailyMinutes) as? Int {
            dailyPickMinutes = minutes
        }
    }

    /// 期限の通知を切り替える。オンにするときだけ許可を求める
    func setDeadlineNotifications(_ enabled: Bool) async {
        if enabled, !(await notifier.requestAuthorization()) {
            notificationPermissionDenied = true
            return
        }

        notificationPermissionDenied = false
        deadlineNotificationsEnabled = enabled
        userDefaults.set(enabled, forKey: NotificationKey.deadline)
        scheduleNotifications(force: true)
    }

    /// 毎日の「今の1つ」を切り替える。オンにするときだけ許可を求める
    func setDailyPick(_ enabled: Bool) async {
        if enabled, !(await notifier.requestAuthorization()) {
            notificationPermissionDenied = true
            return
        }

        notificationPermissionDenied = false
        dailyPickEnabled = enabled
        dailyPickPausedByIgnore = false
        userDefaults.set(enabled, forKey: NotificationKey.daily)
        userDefaults.set(false, forKey: NotificationKey.paused)
        userDefaults.set(0, forKey: NotificationKey.ignored)
        scheduleNotifications(force: true)
    }

    /// 「今の1つ」を届ける時刻を変える
    func setDailyPickMinutes(_ minutes: Int) {
        dailyPickMinutes = min(max(minutes, 0), 24 * 60 - 1)
        userDefaults.set(dailyPickMinutes, forKey: NotificationKey.dailyMinutes)
        scheduleNotifications(force: true)
    }

    /// アプリが前面に来たとき。赤い数字を消し、毎日の通知が開かれたかを数え、推薦と通知を予定し直す
    func appDidBecomeActive() {
        notifier.clearBadge()

        if dailyPickEnabled {
            let ignored = NotificationPlanner.updatedIgnoreCount(
                previous: userDefaults.integer(forKey: NotificationKey.ignored),
                lastFireDate: userDefaults.object(forKey: NotificationKey.lastDailyFire) as? Date,
                openedAt: now()
            )

            if ignored >= NotificationPlanner.ignoreLimit {
                // 見られていない通知を出し続けない
                dailyPickEnabled = false
                dailyPickPausedByIgnore = true
                userDefaults.set(false, forKey: NotificationKey.daily)
                userDefaults.set(true, forKey: NotificationKey.paused)
                userDefaults.set(0, forKey: NotificationKey.ignored)
            } else {
                userDefaults.set(ignored, forKey: NotificationKey.ignored)
            }
        }

        updateRecommendation()
        scheduleNotifications(force: true)
    }

    /// 今の設定とタスクから、通知を予定し直す
    ///
    /// - Parameter force: どちらの通知もオフでも、残っている通知を消すために呼ぶ
    private func scheduleNotifications(force: Bool = false, missedSince: Date? = nil) {
        guard deadlineNotificationsEnabled || dailyPickEnabled || force else {
            return
        }

        // 集中している間は何も予定しない（終わったら予定し直す）
        if focusSession != nil {
            notifier.replaceAll(with: [])
            return
        }

        let currentDate = now()
        var planned: [PlannedNotification] = []

        if deadlineNotificationsEnabled {
            planned += NotificationPlanner.deadlineReminders(for: tasks, now: currentDate, missedSince: missedSince)
        }

        if dailyPickEnabled,
           let fireDate = NotificationPlanner.nextDailyFireDate(
               minutesFromMidnight: dailyPickMinutes,
               now: currentDate,
               calendar: calendar
           ) {
            // その時刻の状況で推薦を出して、通知の文に入れる
            let pick = decisionEngine.recommend(
                from: tasks,
                context: DecisionContext(
                    availableMinutes: availableMinutes,
                    currentDate: fireDate,
                    calendar: calendar
                )
            )
            planned.append(NotificationPlanner.dailyPick(taskTitle: pick?.task.title, fireDate: fireDate))
            userDefaults.set(fireDate, forKey: NotificationKey.lastDailyFire)
        }

        // 予定がなくなった通知（終えたタスクの期限など）も消えるよう、毎回すべて入れ替える
        notifier.replaceAll(with: planned)
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
        now: @escaping () -> Date = { Date() },
        notifier: NotificationScheduling? = nil
    ) {
        self.userDefaults = userDefaults
        self.calendar = calendar
        self.now = now
        self.notifier = notifier ?? SystemNotificationScheduler()

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

        if migrateLegacySteps() {
            saveTasks()
        }

        skippedUntil = loadSkippedUntil()
        recurringTasks = loadRecurringTasks()
        archivedTasks = loadArchivedTasks()
        loadNotificationSettings()
        usesFocusShortcut = userDefaults.bool(forKey: focusShortcutStorageKey)

        updateRecommendation()
        scheduleNotifications()
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
        tasks[index].completedAt = nil
        tasks[index].updatedAt = now()
        lastCompletedTask = nil
        nextStepCandidate = nil
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

        // 気が乗らないのかもしれないので、軽いものにするか聞く（責めずに逃げ道を出す）
        isOfferingLightMode = !prefersLight

        updateRecommendation()
    }

    // MARK: - 気が乗らないとき

    /// 軽い・短い作業だけを推薦するかを切り替える
    func setPrefersLight(_ prefersLight: Bool) {
        self.prefersLight = prefersLight
        isOfferingLightMode = false
        updateRecommendation()
    }

    /// 「軽いものにしますか」を閉じる
    func dismissLightOffer() {
        isOfferingLightMode = false
    }

    // MARK: - 今日やりたい

    /// 「今日やりたい」の印を付け外しする。日付はいじらない
    func togglePinnedForToday(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else {
            return
        }

        let currentDate = now()
        tasks[index].pinnedForTodayAt = tasks[index].isPinnedForToday(at: currentDate, calendar: calendar)
            ? nil
            : currentDate
        tasks[index].updatedAt = currentDate
        saveTasks()
        updateRecommendation()
    }

    // MARK: - まとめて組み直す

    enum RescheduleOption: CaseIterable {
        case today
        case tomorrow
        case nextMonday
        case clearDates
        case hibernate

        var title: String {
            switch self {
            case .today:
                return "今日に"
            case .tomorrow:
                return "明日に"
            case .nextMonday:
                return "来週月曜に"
            case .clearDates:
                return "日付を外す（いつかやる）"
            case .hibernate:
                return "冬眠させる"
            }
        }
    }

    /// 選んだタスクの日付をまとめて変える
    ///
    /// - 今日／明日／来週月曜：予定日をその日にする。期限がその日より前なら、期限も同じ時刻のままその日に移す
    /// - 日付を外す：予定日・期限・今日やりたいを外す
    /// - 冬眠させる：日付を外し、すぐ冬眠に入るようにする
    func reschedule(_ taskIDs: Set<UUID>, to option: RescheduleOption) {
        let currentDate = now()
        let startOfToday = calendar.startOfDay(for: currentDate)

        let targetDay: Date?
        switch option {
        case .today:
            targetDay = startOfToday
        case .tomorrow:
            targetDay = calendar.date(byAdding: .day, value: 1, to: startOfToday)
        case .nextMonday:
            // 月=0 … 日=6 として、次の週の月曜
            let mondayBased = (calendar.component(.weekday, from: startOfToday) + 5) % 7
            targetDay = calendar.date(byAdding: .day, value: 7 - mondayBased, to: startOfToday)
        case .clearDates, .hibernate:
            targetDay = nil
        }

        for index in tasks.indices where taskIDs.contains(tasks[index].id) && !tasks[index].isCompleted {
            if let targetDay {
                tasks[index].scheduledDate = targetDay

                if let deadline = tasks[index].deadline, deadline < targetDay {
                    let time = calendar.dateComponents([.hour, .minute, .second], from: deadline)
                    tasks[index].deadline = calendar.date(
                        bySettingHour: time.hour ?? 23,
                        minute: time.minute ?? 59,
                        second: time.second ?? 59,
                        of: targetDay
                    )
                }

                tasks[index].updatedAt = currentDate
            } else {
                tasks[index].scheduledDate = nil
                tasks[index].deadline = nil
                tasks[index].pinnedForTodayAt = nil

                // 冬眠は「14日触っていない」で判定しているので、その日時まで戻す
                tasks[index].updatedAt = option == .hibernate
                    ? currentDate.addingTimeInterval(-TaskItem.dormancyInterval)
                    : currentDate
            }
        }

        saveTasks()
        updateRecommendation()
    }

    // MARK: - くり返し

    /// くり返すタスクを追加する。今日が回の日なら、今日の分もすぐ出す
    func addRecurring(
        title: String,
        estimatedMinutes: Int,
        priority: TaskPriority = .medium,
        isLight: Bool = false,
        recurrence: Recurrence
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        recurringTasks.append(
            RecurringTask(
                title: trimmed,
                estimatedMinutes: estimatedMinutes,
                priority: priority,
                isLight: isLight,
                recurrence: recurrence,
                startDate: calendar.startOfDay(for: now())
            )
        )
        saveRecurringTasks()
        updateRecommendation()
    }

    /// くり返すタスクの中身を変える。すでに出ている今日の分の名前と時間もそろえる
    func updateRecurring(_ updated: RecurringTask) {
        guard let index = recurringTasks.firstIndex(where: { $0.id == updated.id }) else {
            return
        }

        recurringTasks[index] = updated

        for taskIndex in tasks.indices where tasks[taskIndex].recurringID == updated.id && !tasks[taskIndex].isCompleted {
            tasks[taskIndex].title = updated.title
            tasks[taskIndex].estimatedMinutes = updated.estimatedMinutes
            tasks[taskIndex].priority = updated.priority
            tasks[taskIndex].isLight = updated.isLight
        }

        saveRecurringTasks()
        saveTasks()
        updateRecommendation()
    }

    /// くり返しをやめる。まだ終えていない回も消す（終えた回は「今日やったこと」のために残す）
    func deleteRecurring(_ recurring: RecurringTask) {
        recurringTasks.removeAll { $0.id == recurring.id }
        tasks.removeAll { $0.recurringID == recurring.id && !$0.isCompleted }
        saveRecurringTasks()
        saveTasks()
        updateRecommendation()
    }

    /// くり返しの回を「今回はお休み」にする。その日の分を消し、また出てこないよう覚えておく
    func skipOccurrence(_ task: TaskItem) {
        guard let recurringID = task.recurringID,
              let index = recurringTasks.firstIndex(where: { $0.id == recurringID }) else {
            return
        }

        let day = calendar.startOfDay(for: task.occurrenceDate ?? now())
        recurringTasks[index].skippedDays.append(day)
        // 古いお休みの記録は持ち続けない
        recurringTasks[index].skippedDays.removeAll { $0 < calendar.startOfDay(for: now()).addingTimeInterval(-60 * 60 * 24 * 7) }
        tasks.removeAll { $0.id == task.id }

        saveRecurringTasks()
        saveTasks()
        updateRecommendation()
    }

    /// くり返しのひな形から、今日の回を出す。持ち越さない回で過ぎたものは静かに流す
    private func refreshOccurrences() {
        let today = calendar.startOfDay(for: now())
        let carriesOver = Dictionary(
            uniqueKeysWithValues: recurringTasks.map { ($0.id, $0.recurrence.carriesOver) }
        )

        let before = tasks.count
        tasks.removeAll { task in
            guard let recurringID = task.recurringID,
                  let occurrenceDate = task.occurrenceDate,
                  !task.isCompleted,
                  occurrenceDate < today else {
                return false
            }
            return !(carriesOver[recurringID] ?? true)
        }
        var changed = tasks.count != before

        for recurring in recurringTasks where recurring.occurs(on: today, calendar: calendar) {
            let alreadyExists = tasks.contains { task in
                task.recurringID == recurring.id
                    && task.occurrenceDate.map { calendar.isDate($0, inSameDayAs: today) } == true
            }

            guard !alreadyExists else {
                continue
            }

            tasks.append(
                TaskItem(
                    title: recurring.title,
                    estimatedMinutes: recurring.estimatedMinutes,
                    priority: recurring.priority,
                    scheduledDate: today,
                    updatedAt: now(),
                    isLight: recurring.isLight,
                    recurringID: recurring.id,
                    occurrenceDate: today
                )
            )
            changed = true
        }

        if changed {
            saveTasks()
        }
    }

    private func loadRecurringTasks() -> [RecurringTask] {
        guard let data = userDefaults.data(forKey: recurringStorageKey),
              let saved = try? JSONDecoder().decode([RecurringTask].self, from: data) else {
            return []
        }
        return saved
    }

    private func saveRecurringTasks() {
        guard let data = try? JSONEncoder().encode(recurringTasks) else {
            return
        }
        userDefaults.set(data, forKey: recurringStorageKey)
    }

    // MARK: - 優先度「高」は3件まで

    /// `taskID` 以外で、優先度「高」の未完了タスク
    func otherHighPriorityTasks(excluding taskID: UUID?) -> [TaskItem] {
        tasks.filter { $0.priority == .high && !$0.isCompleted && $0.id != taskID }
    }

    /// 優先度「高」をもう1件付けるには、どれかを外す必要があるか
    func needsToLowerAHighPriority(excluding taskID: UUID?) -> Bool {
        otherHighPriorityTasks(excluding: taskID).count >= Self.maxHighPriorityTasks
    }

    /// 優先度を「中」に戻す
    func lowerPriority(of taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else {
            return
        }

        tasks[index].priority = .medium
        tasks[index].updatedAt = now()
        saveTasks()
        updateRecommendation()
    }

    /// 「今はやらない」をすべて取り消す
    func clearSkips() {
        skippedUntil.removeAll()
        saveSkippedUntil()
        updateRecommendation()
    }

    /// 推薦中のタスクに集中して取りかかる
    ///
    /// - Parameters:
    ///   - taskID: 取りかかるタスク。nilなら推薦中のタスク
    ///   - trialMinutes: 「5分だけやる」のときの目安。空き時間に収まらない大きいタスクでも始められる
    func startFocus(on taskID: UUID? = nil, trialMinutes: Int? = nil) {
        guard let id = taskID ?? recommendation?.task.id,
              let index = tasks.firstIndex(where: { $0.id == id }),
              !tasks[index].isCompleted else {
            return
        }

        tasks[index].updatedAt = now()
        focusSession = FocusSession(taskID: id, startedAt: now(), trialMinutes: trialMinutes)
        saveTasks()

        // 集中している間は、TaskFlow の通知を出さない
        scheduleNotifications()
    }

    /// 「5分だけ」のあと、そのまま続ける（目安をタスクの所要時間に戻す）
    func continueFocus() {
        focusSession?.trialMinutes = nil
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
        let startedAt = focusSession?.startedAt

        if completing, let task = focusedTask {
            complete(task)
        }

        focusSession = nil

        // 集中していた間に出るはずだった期限の通知は、ここで出す
        scheduleNotifications(missedSince: startedAt)
    }

    // MARK: - 集中モード（ショートカット）

    /// 「始める」「5分だけやる」で、ショートカットを使って iPhone の集中モードをオンにするか
    @Published private(set) var usesFocusShortcut = false
    private let focusShortcutStorageKey = "taskFlow.focus.shortcut"

    /// 集中を始めるときに動かすショートカットの名前（ユーザーが自分で作る）
    nonisolated static let focusStartShortcutName = "TaskFlow 集中開始"

    /// 集中を終えるときに動かすショートカットの名前
    nonisolated static let focusEndShortcutName = "TaskFlow 集中終了"

    func setUsesFocusShortcut(_ enabled: Bool) {
        usesFocusShortcut = enabled
        userDefaults.set(enabled, forKey: focusShortcutStorageKey)
    }

    /// 集中の始めか終わりに開く、ショートカットのURL。オフならnil
    ///
    /// アプリから iPhone の集中モードを直接は切り替えられないので、ユーザーが作ったショートカットを動かす。
    /// ショートカットの最後で TaskFlow を開くようにしておくと、自動で戻ってくる。
    func focusShortcutURL(starting: Bool) -> URL? {
        guard usesFocusShortcut else {
            return nil
        }

        let name = starting ? Self.focusStartShortcutName : Self.focusEndShortcutName
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "run-shortcut"
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        return components.url
    }

    /// 1行の入力からタスクを追加する。「請求書を送る 15分」のように時間を書ける
    ///
    /// - Returns: 追加できたら true（タイトルが空なら false）
    @discardableResult
    func quickAdd(
        _ text: String,
        ignoring: Set<QuickAddParser.Part> = []
    ) -> Bool {
        guard let parsed = previewQuickAdd(text, ignoring: ignoring) else {
            return false
        }

        if let recurrence = parsed.recurrence {
            addRecurring(
                title: parsed.title,
                estimatedMinutes: parsed.estimatedMinutes,
                isLight: parsed.isLight,
                recurrence: recurrence
            )
            return true
        }

        addTask(
            title: parsed.title,
            estimatedMinutes: parsed.estimatedMinutes,
            priority: .medium,
            scheduledDate: parsed.scheduledDate,
            deadline: parsed.deadline,
            isLight: parsed.isLight
        )
        return true
    }

    /// 1行の入力をどう読み取るか（入力欄の上に出す確認用）
    func previewQuickAdd(
        _ text: String,
        ignoring: Set<QuickAddParser.Part> = []
    ) -> QuickAddParser.Result? {
        QuickAddParser.parse(
            text,
            defaultMinutes: Self.defaultQuickAddMinutes,
            now: now(),
            calendar: calendar,
            ignoring: ignoring
        )
    }

    /// 読み取った日付の短い表示（「明日 15:00」など）
    func describeQuickAddDate(_ date: Date, includesTime: Bool) -> String {
        QuickAddParser.describe(date, includesTime: includesTime, now: now(), calendar: calendar)
    }

    // MARK: - 今日やったこと

    /// 今日完了にしたタスク（完了した順）
    var completedToday: [TaskItem] {
        let currentDate = now()

        return tasks
            .filter { task in
                guard task.isCompleted, let completedAt = task.completedAt else {
                    return false
                }
                return calendar.isDate(completedAt, inSameDayAs: currentDate)
            }
            .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
    }

    /// 分けたタスクのうち、同じ元タスクから作られたものが全部終わったか
    func finishedWholeSplitGroup(of task: TaskItem) -> Bool {
        guard let groupID = task.splitGroupID else {
            return false
        }

        return tasks
            .filter { $0.splitGroupID == groupID }
            .allSatisfy(\.isCompleted)
    }

    private func complete(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }),
              !tasks[index].isCompleted else {
            return
        }

        lastCompletedTask = tasks[index]
        tasks[index].isCompleted = true
        tasks[index].completedAt = now()
        tasks[index].updatedAt = now()
        skippedUntil[task.id] = nil
        saveTasks()
        saveSkippedUntil()
        updateRecommendation()

        // 一歩を終えて、次の一歩がまだ決まっておらず、元のタスクが空き時間に収まらないままなら、次の一歩を聞く
        if let parentID = task.parentTaskID {
            let hasOpenStep = steps(of: parentID).contains { !$0.isCompleted }
            let parent = tasks.first { $0.id == parentID && !$0.isCompleted }

            nextStepCandidate = (!hasOpenStep && (parent?.estimatedMinutes ?? 0) > availableMinutes) ? parent : nil
            return
        }

        // 分けた部分を終えて、続きのタスクが空き時間に収まらないままなら、次の一歩を聞く
        nextStepCandidate = task.splitGroupID.flatMap { groupID in
            tasks.first { other in
                !other.isCompleted
                    && other.splitGroupID == groupID
                    && other.prerequisiteIDs.contains(task.id)
                    && other.estimatedMinutes > availableMinutes
            }
        }
    }

    // MARK: - 最初の一歩

    /// 一歩の位置（「部屋の片付け」の2歩目・全3歩）
    struct StepPosition: Equatable {
        let parentID: UUID
        let parentTitle: String
        let index: Int
        let total: Int
        let completedCount: Int
    }

    /// 元のタスクの一歩（決めた順。済んだものも含む）
    func steps(of parentID: UUID) -> [TaskItem] {
        tasks.filter { $0.parentTaskID == parentID }
    }

    /// 一歩なら、その位置
    func stepPosition(of task: TaskItem) -> StepPosition? {
        guard let parentID = task.parentTaskID,
              let parent = tasks.first(where: { $0.id == parentID }) else {
            return nil
        }

        let all = steps(of: parentID)
        guard let index = all.firstIndex(where: { $0.id == task.id }) else {
            return nil
        }

        return StepPosition(
            parentID: parentID,
            parentTitle: parent.title,
            index: index + 1,
            total: all.count,
            completedCount: all.filter(\.isCompleted).count
        )
    }

    /// 大きいタスクに一歩を足す（いちばん後ろに）
    ///
    /// 全部を分けなくても、一歩だけ決めれば推薦に出るようにする。ホームには、まだ済んでいない最初の一歩だけが出る。
    func addStep(to parent: TaskItem, title stepTitle: String, minutes: Int) {
        let trimmed = stepTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty,
              let parentIndex = tasks.firstIndex(where: { $0.id == parent.id }) else {
            return
        }

        let currentDate = now()
        let groupID = tasks[parentIndex].splitGroupID ?? tasks[parentIndex].id

        let step = TaskItem(
            title: trimmed,
            estimatedMinutes: min(max(minutes, 5), 480),
            priority: tasks[parentIndex].priority,
            deadline: tasks[parentIndex].deadline,
            updatedAt: currentDate,
            splitGroupID: groupID,
            parentTaskID: parent.id
        )

        tasks[parentIndex].splitGroupID = groupID
        tasks[parentIndex].updatedAt = currentDate
        // 一歩は元のタスクの直前に並べる（決めた順のまま、元のタスクより前になる）
        tasks.insert(step, at: parentIndex)

        skippedUntil[step.id] = nil
        nextStepCandidate = nil
        rebuildStepChain(for: parent.id)
        saveTasks()
        updateRecommendation()
    }

    /// 以前の呼び方。最初の一歩を足す
    func addFirstStep(for task: TaskItem, title stepTitle: String, minutes: Int) {
        addStep(to: task, title: stepTitle, minutes: minutes)
    }

    /// 一歩を取り消す
    func deleteStep(_ step: TaskItem) {
        guard let parentID = step.parentTaskID else {
            return
        }

        tasks.removeAll { $0.id == step.id }
        rebuildStepChain(for: parentID)
        saveTasks()
        updateRecommendation()
    }

    /// まだ済んでいない一歩の順番を入れ替える
    func moveOpenSteps(of parentID: UUID, fromOffsets source: IndexSet, toOffset destination: Int) {
        let original = steps(of: parentID).filter { !$0.isCompleted }

        // 並べ替え（List の onMove と同じ意味。SwiftUI に頼らずに書く）
        let moving = source.sorted().map { original[$0] }
        var open = original.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        open.insert(contentsOf: moving, at: min(max(insertAt, 0), open.count))

        let openIDs = Set(open.map(\.id))
        tasks.removeAll { openIDs.contains($0.id) }

        guard let parentIndex = tasks.firstIndex(where: { $0.id == parentID }) else {
            return
        }

        tasks.insert(contentsOf: open, at: parentIndex)
        rebuildStepChain(for: parentID)
        saveTasks()
        updateRecommendation()
    }

    /// 一歩を、決めた順につなぎ直す
    ///
    /// まだ済んでいない一歩を順に前提としてつなぎ、元のタスクは最後の一歩を待つ。
    /// 元のタスクがもともと待っていた前提（一歩以外）は、最初の一歩が待つ。
    private func rebuildStepChain(for parentID: UUID) {
        guard let parentIndex = tasks.firstIndex(where: { $0.id == parentID }) else {
            return
        }

        let stepIndices = tasks.indices.filter { tasks[$0].parentTaskID == parentID }
        let stepIDs = Set(stepIndices.map { tasks[$0].id })

        var external: [UUID] = []
        for id in tasks[parentIndex].prerequisiteIDs + stepIndices.flatMap({ tasks[$0].prerequisiteIDs })
        where !stepIDs.contains(id) && id != parentID && !external.contains(id) {
            external.append(id)
        }

        var previous: UUID?
        for index in stepIndices where !tasks[index].isCompleted {
            tasks[index].prerequisiteIDs = previous.map { [$0] } ?? external
            previous = tasks[index].id
        }

        tasks[parentIndex].prerequisiteIDs = external + (previous.map { [$0] } ?? [])
    }

    /// 以前の形（「元のタスク名：一歩」というタイトル）の一歩を、元のタスクにぶら下がる形に直す
    ///
    /// 以前は一歩の一歩も作れたので「元：一歩目：二歩目」のように重なっていることがある。
    /// 元のタスク名を外したあと、同じ元のタスクのほかの一歩の名前が頭に付いていれば、それも外す。
    private func migrateLegacySteps() -> Bool {
        var changed = false
        var touchedParents: Set<UUID> = []

        for index in tasks.indices where tasks[index].parentTaskID == nil {
            guard let groupID = tasks[index].splitGroupID,
                  groupID != tasks[index].id,
                  let parent = tasks.first(where: { $0.id == groupID }) else {
                continue
            }

            let prefix = CompletionMessages.baseTitle(of: parent.title) + "："
            guard tasks[index].title.hasPrefix(prefix) else {
                continue
            }

            tasks[index].title = String(tasks[index].title.dropFirst(prefix.count))
            tasks[index].parentTaskID = parent.id
            touchedParents.insert(parent.id)
            changed = true
        }

        // 一歩の名前の頭に、ほかの一歩の名前が重なっていたら外す（短い名前から順に試す）
        for index in tasks.indices {
            guard let parentID = tasks[index].parentTaskID else {
                continue
            }

            let siblingTitles = tasks
                .filter { $0.parentTaskID == parentID && $0.id != tasks[index].id }
                .map(\.title)
                .sorted { $0.count > $1.count }

            var stripped = true
            while stripped {
                stripped = false
                for sibling in siblingTitles where !sibling.isEmpty {
                    let prefix = sibling + "："
                    if tasks[index].title.hasPrefix(prefix), tasks[index].title.count > prefix.count {
                        tasks[index].title = String(tasks[index].title.dropFirst(prefix.count))
                        touchedParents.insert(parentID)
                        changed = true
                        stripped = true
                        break
                    }
                }
            }
        }

        for parentID in touchedParents {
            rebuildStepChain(for: parentID)
        }

        return changed
    }

    /// 「次の一歩を決めますか？」を閉じる
    func dismissNextStepOffer() {
        nextStepCandidate = nil
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
        deadline: Date?,
        isLight: Bool = false
    ) {
        let task = TaskItem(
            title: title,
            estimatedMinutes: estimatedMinutes,
            priority: priority,
            scheduledDate: scheduledDate,
            deadline: deadline,
            updatedAt: now(),
            isLight: isLight
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
        tasks[index].completedAt = tasks[index].isCompleted ? now() : nil
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
        tasks.removeAll { $0.id == task.id || $0.parentTaskID == task.id }

        // 削除したタスクを前提にしていたタスクが、推薦されないまま残らないようにする
        for index in tasks.indices {
            tasks[index].prerequisiteIDs.removeAll { $0 == task.id }
        }

        // 一歩を消したなら、残りの一歩をつなぎ直す
        if let parentID = task.parentTaskID {
            rebuildStepChain(for: parentID)
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

        // 期限や完了が変わったら、通知も予定し直す（オフなら何もしない）
        scheduleNotifications()
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
        refreshOccurrences()

        let currentDate = now()

        // 時間が過ぎたものと、なくなったタスクの「今はやらない」を外す
        let taskIDs = Set(tasks.map(\.id))
        let activeSkips = skippedUntil.filter { taskIDs.contains($0.key) && $0.value > currentDate }
        if activeSkips.count != skippedUntil.count {
            skippedUntil = activeSkips
            saveSkippedUntil()
        }

        var context = DecisionContext(
            availableMinutes: availableMinutes,
            currentDate: currentDate,
            skippedTaskIDs: Set(skippedUntil.keys),
            calendar: calendar,
            prefersLight: prefersLight
        )

        recommendation = decisionEngine.recommend(
            from: tasks,
            context: context
        )

        // 軽いものだけにして候補がなくなったら、ふだんの推薦ならあるかを確かめる
        if prefersLight, recommendation == nil {
            context.prefersLight = false
            lightModeHasNoMatch = decisionEngine.recommend(from: tasks, context: context) != nil
        } else {
            lightModeHasNoMatch = false
        }

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
