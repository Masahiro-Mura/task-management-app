import Foundation
import Combine
import WidgetKit

@MainActor
final class HomeViewModel: ObservableObject {

    /// 画面に出ている ViewModel。Siri やショートカットからの操作を、開いている画面にそのまま反映するのに使う
    static weak var current: HomeViewModel?

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

    struct FocusSession: Equatable, Codable {
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

    private let decisionEngine = DecisionEngine()
    private let userDefaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date
    private let availableMinutesStorageKey = TaskStore.Key.availableMinutes

    /// 保存先（キーと読み書きは `TaskStore` にまとめた）
    private var store: TaskStore {
        TaskStore(userDefaults: userDefaults)
    }

    /// 「今はやらない」で推薦から外す時間
    nonisolated static let skipDuration: TimeInterval = 60 * 60

    /// 1行で追加したとき、時間が書かれていなければ使う所要時間（分）
    nonisolated static let defaultQuickAddMinutes = 30

    /// 読み込めなかった保存データの退避先キーの接頭辞
    static let unreadableTasksKeyPrefix = TaskStore.Key.unreadableTasksPrefix

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

    // MARK: - 1日の区切り

    /// 「今日」が始まる時刻（0〜5時）。夜中まで作業する人のため、4時区切りなどにできる
    @Published private(set) var dayStartHour = 0
    private let dayStartHourStorageKey = "taskFlow.dayStartHour"
    nonisolated static let dayStartHourRange = 0...5

    func setDayStartHour(_ hour: Int) {
        dayStartHour = min(max(hour, Self.dayStartHourRange.lowerBound), Self.dayStartHourRange.upperBound)
        userDefaults.set(dayStartHour, forKey: dayStartHourStorageKey)
        updateRecommendation()
    }

    /// 1日の区切り（0時からずらす秒数）
    private var dayStartOffset: TimeInterval {
        TimeInterval(dayStartHour) * 60 * 60
    }

    /// 1日の区切りをずらした「今」。日付の言葉（今日・明日）や「今日」の判定に使う
    private var logicalNow: Date {
        now().addingTimeInterval(-dayStartOffset)
    }

    /// 1日の区切りを反映した「今日」（その日の 0時）
    private var logicalToday: Date {
        calendar.startOfDay(for: logicalNow)
    }

    /// 今日の欄に出すタスク
    ///
    /// 予定日が今日のものに加え、期限が今日のものと、予定日や期限を過ぎた未完了タスク（持ち越し）を含める。
    /// 冬眠中のタスクは出さない。
    var todayTasks: [TaskItem] {
        let currentDate = now()
        let today = logicalToday

        return tasks.filter { task in
            guard !task.isDormant(at: currentDate, calendar: calendar) else {
                return false
            }

            if let scheduledDate = task.scheduledDate,
               calendar.isDate(scheduledDate, inSameDayAs: today) {
                return true
            }

            if let deadline = task.deadline,
               calendar.isDate(deadline, inSameDayAs: today) {
                return true
            }

            if task.isPinnedForToday(at: currentDate, calendar: calendar, dayStartOffset: dayStartOffset) {
                return true
            }

            return isCarriedOver(task)
        }
    }

    /// 今日「今日やりたい」の印が付いているタスクのID
    var pinnedTaskIDs: Set<UUID> {
        let currentDate = now()
        return Set(
            tasks
                .filter { $0.isPinnedForToday(at: currentDate, calendar: calendar, dayStartOffset: dayStartOffset) }
                .map(\.id)
        )
    }

    /// 今日の欄にある持ち越し（冬眠中を除く）
    var carriedOverTasks: [TaskItem] {
        todayTasks.filter { isCarriedOver($0) }
    }

    /// 明日の欄に出すタスク。今日の欄に出るものは重ねて出さない
    var tomorrowTasks: [TaskItem] {
        let currentDate = now()
        let todayTaskIDs = Set(todayTasks.map(\.id))

        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: logicalToday) else {
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

        let startOfToday = logicalToday

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
    private let lastLetGoPromptStorageKey = "taskFlow.lastLetGoPrompt"

    private func isOldCompleted(_ task: TaskItem) -> Bool {
        guard task.isCompleted else {
            return false
        }

        let completedAt = task.completedAt ?? task.updatedAt
        let limit = now().addingTimeInterval(-TimeInterval(Self.completedHideDays) * 24 * 60 * 60)
        return completedAt <= limit
    }

    /// 完了してからこの日数がたったものは、保存データからも消す（データが増え続けないように）
    nonisolated static let completedKeepDays = 365

    /// 完了して1年たったものを消す
    ///
    /// - Returns: 消したものがあったか
    private func pruneOldCompletedTasks() -> Bool {
        let limit = now().addingTimeInterval(-TimeInterval(Self.completedKeepDays) * 24 * 60 * 60)
        let before = tasks.count

        tasks.removeAll { task in
            task.isCompleted && (task.completedAt ?? task.updatedAt) <= limit
        }

        return tasks.count != before
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

    private func saveArchivedTasks() {
        store.save(archivedTasks, forKey: TaskStore.Key.archived)
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
            quickAdd(String(localized: "メールを1通返す 10分"))
            quickAdd(String(localized: "明日までに企画のメモを書く 30分"))
            quickAdd(String(localized: "部屋の片付け 90分"))
        }

        objectWillChange.send()
    }

    /// 設定から、案内をもう一度見られるようにする
    func showOnboardingAgain() {
        isOnboardingRequested = true
    }

    // MARK: - 通知

    private let notifier: NotificationScheduling

    // MARK: - ウィジェット・共有シート・ライブアクティビティ

    /// ウィジェット・共有シートと分け合う保存先（App Group）。なければ、どちらにも触れない
    private let sharedDefaults: UserDefaults?

    /// ウィジェットを描き直す
    private let reloadWidgets: () -> Void

    /// 集中のライブアクティビティを出し入れする
    private let focusActivity: FocusActivityPresenting?

    /// 今の推薦を、ウィジェット用の写しとして書く。中身が変わったときだけ描き直す
    private func publishWidgetSnapshot() {
        guard let sharedDefaults else {
            return
        }

        let pick = recommendation.map { recommendation in
            WidgetSnapshot.Pick(
                taskID: recommendation.task.id,
                title: recommendation.task.title,
                minutes: recommendation.task.estimatedMinutes,
                shortReason: recommendation.shortReason,
                stepLabel: stepPosition(of: recommendation.task).map { String(localized: "\($0.index)歩目") }
            )
        }

        let emptyMessage: String
        if tasks.allSatisfy(\.isCompleted) {
            emptyMessage = String(localized: "やることはありません")
        } else if lightModeHasNoMatch {
            emptyMessage = String(localized: "軽い作業はありません")
        } else {
            emptyMessage = String(localized: "\(availableMinutes)分に入るものはありません")
        }

        let snapshot = WidgetSnapshot(
            pick: pick,
            emptyMessage: emptyMessage,
            availableMinutes: availableMinutes,
            todayRemainingCount: todayTasks.filter { !$0.isCompleted }.count,
            updatedAt: now()
        )

        guard !snapshot.hasSameContent(as: WidgetSnapshot.load(from: sharedDefaults)) else {
            return
        }
        snapshot.save(to: sharedDefaults)
        reloadWidgets()
    }

    /// 共有シートから届いた文を、1行入力と同じ読み方でタスクにする
    ///
    /// - Returns: 足した件数
    @discardableResult
    func importSharedItems() -> Int {
        guard let sharedDefaults else {
            return 0
        }

        var added = 0
        for item in ShareInbox.drain(from: sharedDefaults) {
            let before = Set(tasks.map(\.id))
            guard quickAdd(item.text) else {
                continue
            }
            added += 1

            if let link = item.link,
               let index = tasks.firstIndex(where: { !before.contains($0.id) }) {
                tasks[index].link = link
                saveTasks()
            }
        }
        return added
    }

    /// システムのウィジェットを描き直す
    nonisolated static func reloadSystemWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 集中のライブアクティビティを、今の集中に合わせる
    private func updateFocusActivity() {
        guard let focusActivity else {
            return
        }

        guard let session = focusSession, let task = focusedTask else {
            focusActivity.end()
            return
        }

        let minutes = session.trialMinutes ?? task.estimatedMinutes
        focusActivity.show(
            FocusActivityAttributes(
                taskID: task.id,
                taskTitle: task.title,
                startedAt: session.startedAt,
                isTrial: session.trialMinutes != nil
            ),
            targetEnd: session.startedAt.addingTimeInterval(TimeInterval(minutes) * 60)
        )
    }

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
        importSharedItems()

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
        notifier: NotificationScheduling? = nil,
        sharedDefaults: UserDefaults? = nil,
        reloadWidgets: @escaping () -> Void = {},
        focusActivity: FocusActivityPresenting? = nil
    ) {
        self.userDefaults = userDefaults
        self.calendar = calendar
        self.now = now
        self.notifier = notifier ?? SystemNotificationScheduler()
        self.sharedDefaults = sharedDefaults
        self.reloadWidgets = reloadWidgets
        self.focusActivity = focusActivity

        let savedMinutes = userDefaults.integer(forKey: availableMinutesStorageKey)
        if Self.availableMinuteOptions.contains(savedMinutes) {
            availableMinutes = savedMinutes
        }

        switch store.loadTasks() {
        case .loaded(let savedTasks):
            tasks = savedTasks

        case .notFound:
            if seedsSampleTasks {
                loadSampleTasks()
            }

        case .unreadable(let data):
            // 次の保存で上書きされて失われないよう、元のデータを退避しておく
            store.backUpUnreadableTasks(data, at: now())
        }

        let migrated = StepChain.migrateLegacySteps(in: &tasks)
        let pruned = pruneOldCompletedTasks()
        if migrated || pruned {
            saveTasks()
        }

        skippedUntil = store.load([UUID: Date].self, forKey: TaskStore.Key.skippedUntil) ?? [:]
        skipCounts = store.load([UUID: Int].self, forKey: TaskStore.Key.skipCounts) ?? [:]
        recurringTasks = store.load([RecurringTask].self, forKey: TaskStore.Key.recurring) ?? []
        archivedTasks = store.load([TaskItem].self, forKey: TaskStore.Key.archived) ?? []
        restoreFocusSession()
        // 集中が戻らなかったら、残っているライブアクティビティを下げる
        updateFocusActivity()
        loadNotificationSettings()
        usesFocusShortcut = userDefaults.bool(forKey: focusShortcutStorageKey)
        dayStartHour = min(max(userDefaults.integer(forKey: dayStartHourStorageKey), 0), 5)

        updateRecommendation()
        scheduleNotifications()
    }

    /// アプリとして起動したときの ViewModel
    ///
    /// UIテストで `-uiTesting` を付けて起動したときは、毎回空の専用の保存先を使い、案内を出さない。
    /// `-uiTestingSeed` も付けると、決まったタスクを2つ入れる。
    static func makeForApp(arguments: [String] = ProcessInfo.processInfo.arguments) -> HomeViewModel {
        guard arguments.contains("-uiTesting") else {
            return HomeViewModel(
                sharedDefaults: SharedStore.defaults,
                reloadWidgets: HomeViewModel.reloadSystemWidgets,
                focusActivity: SystemFocusActivity()
            )
        }

        let suiteName = "TaskFlowUITesting"
        let userDefaults = UserDefaults(suiteName: suiteName) ?? .standard
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults.set(true, forKey: "taskFlow.onboarded")

        let viewModel = HomeViewModel(userDefaults: userDefaults, seedsSampleTasks: false)
        if arguments.contains("-uiTestingSeed") {
            viewModel.quickAdd("Write report 10m")
            viewModel.quickAdd("Read paper 20m")
        }
        return viewModel
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
        lastSkippedTask = task

        // 何度も見送られているなら、大きすぎるのかもしれない。一度だけ、小さくするか冬眠させるかを聞く
        skipCounts[task.id, default: 0] += 1
        if skipCounts[task.id, default: 0] >= Self.repeatedSkipLimit {
            skipCounts[task.id] = 0
            repeatedSkipCandidate = tasks.first { $0.id == task.id }
            isOfferingLightMode = false
        } else {
            // 気が乗らないのかもしれないので、軽いものにするか聞く（責めずに逃げ道を出す）
            isOfferingLightMode = !prefersLight
        }
        saveSkipCounts()

        updateRecommendation()
    }

    /// 直前に「あとで」にしたタスク。「1時間後にまた出します」と、取り消しを出す
    @Published private(set) var lastSkippedTask: TaskItem?

    /// 直前の「あとで」を取り消して、そのタスクをまた推薦に戻す
    func undoSkip() {
        guard let task = lastSkippedTask else {
            return
        }

        lastSkippedTask = nil
        skippedUntil[task.id] = nil
        saveSkippedUntil()

        if let count = skipCounts[task.id], count > 0 {
            skipCounts[task.id] = count - 1
            saveSkipCounts()
        }
        isOfferingLightMode = false
        if repeatedSkipCandidate?.id == task.id {
            repeatedSkipCandidate = nil
        }

        updateRecommendation()
    }

    /// 「あとで」の知らせを閉じる
    func dismissSkipFeedback() {
        lastSkippedTask = nil
    }

    // MARK: - 何度も見送られるタスク

    /// 何回「今はやらない」にされたら、小さくするか冬眠させるかを聞くか
    nonisolated static let repeatedSkipLimit = 3

    /// 「今はやらない」にされた回数（取りかかったり、終えたり、手を入れたりすると 0 に戻る）
    private var skipCounts: [UUID: Int] = [:]

    /// 何度も見送られているので「小さくしてみますか？」と聞いているタスク
    @Published private(set) var repeatedSkipCandidate: TaskItem?

    /// 「小さくしてみますか？」を閉じる
    func dismissRepeatedSkipOffer() {
        repeatedSkipCandidate = nil
    }

    /// 見送られ続けているタスクを冬眠させる
    func hibernate(_ task: TaskItem) {
        repeatedSkipCandidate = nil
        reschedule([task.id], to: .hibernate)
    }

    private func resetSkipCount(for taskID: UUID) {
        guard skipCounts[taskID] != nil else {
            return
        }
        skipCounts[taskID] = nil
        saveSkipCounts()
    }

    private func saveSkipCounts() {
        store.save(skipCounts, forKey: TaskStore.Key.skipCounts)
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
        tasks[index].pinnedForTodayAt = tasks[index].isPinnedForToday(at: currentDate, calendar: calendar, dayStartOffset: dayStartOffset)
            ? nil
            : currentDate
        tasks[index].updatedAt = currentDate
        saveTasks()
        updateRecommendation()
    }

    // MARK: - まとめて組み直す

    typealias RescheduleOption = TaskRescheduler.Option

    /// 選んだタスクの日付をまとめて変える（中身は `TaskRescheduler`）
    func reschedule(_ taskIDs: Set<UUID>, to option: RescheduleOption) {
        TaskRescheduler.reschedule(
            taskIDs,
            to: option,
            in: &tasks,
            now: now(),
            startOfToday: logicalToday,
            calendar: calendar
        )
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

    /// くり返しのひな形から、今日の回を出す（中身は `RecurrenceScheduler`）
    private func refreshOccurrences() {
        if RecurrenceScheduler.refreshOccurrences(
            in: &tasks,
            recurringTasks: recurringTasks,
            now: logicalNow,
            calendar: calendar
        ) {
            saveTasks()
        }
    }

    private func saveRecurringTasks() {
        store.save(recurringTasks, forKey: TaskStore.Key.recurring)
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
        resetSkipCount(for: id)
        focusSession = FocusSession(taskID: id, startedAt: now(), trialMinutes: trialMinutes)
        saveFocusSession()
        saveTasks()
        updateFocusActivity()

        // 集中している間は、TaskFlow の通知を出さない
        scheduleNotifications()
    }

    /// 「5分だけ」のあと、そのまま続ける（目安をタスクの所要時間に戻す）
    func continueFocus() {
        focusSession?.trialMinutes = nil
        saveFocusSession()
        updateFocusActivity()
    }

    /// 集中しているあいだにアプリが終わっても、戻ってきたら続きから再開できるよう保存する
    private func saveFocusSession() {
        store.save(focusSession, forKey: TaskStore.Key.focusSession)
    }

    /// 保存していた集中を戻す。タスクがもうないか終わっているか、始めてから半日以上たっていれば戻さない
    private func restoreFocusSession() {
        guard let saved = store.load(FocusSession.self, forKey: TaskStore.Key.focusSession),
              tasks.contains(where: { $0.id == saved.taskID && !$0.isCompleted }),
              now().timeIntervalSince(saved.startedAt) < 12 * 60 * 60 else {
            store.save(FocusSession?.none, forKey: TaskStore.Key.focusSession)
            return
        }

        focusSession = saved
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
            // 実際にかかった時間を覚えておく（見積もりの初期値を現実に近づけるため）
            if let startedAt, let index = tasks.firstIndex(where: { $0.id == task.id }) {
                let elapsed = now().timeIntervalSince(startedAt)
                tasks[index].actualMinutes = max(1, Int((elapsed / 60).rounded(.up)))
            }
            complete(task)
        }

        focusSession = nil
        saveFocusSession()
        updateFocusActivity()

        // 集中していた間に出るはずだった期限の通知は、ここで出す
        scheduleNotifications(missedSince: startedAt)
    }

    // MARK: - 集中モード（ショートカット）

    /// 「始める」「5分だけやる」で、ショートカットを使って iPhone の集中モードをオンにするか
    @Published private(set) var usesFocusShortcut = false
    private let focusShortcutStorageKey = "taskFlow.focus.shortcut"

    /// 集中を始めるときに動かすショートカットの名前（ユーザーが自分で作る）
    nonisolated static let focusStartShortcutName = String(localized: "TaskFlow 集中開始")

    /// 集中を終えるときに動かすショートカットの名前
    nonisolated static let focusEndShortcutName = String(localized: "TaskFlow 集中終了")

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

    // MARK: - 見積もりと実際

    /// 実際の時間から傾向を出すのに要る、集中画面で終えたタスクの数
    nonisolated static let estimateSampleMinimum = 5

    /// 最近、集中画面で終えたタスクの「実際の時間 ÷ 見積もり」のまん中の値。数が足りなければ nil
    var estimateRatio: Double? {
        let ratios = tasks
            .filter { $0.isCompleted && $0.actualMinutes != nil && $0.estimatedMinutes > 0 }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            .prefix(20)
            .map { Double($0.actualMinutes ?? 0) / Double($0.estimatedMinutes) }
            .sorted()

        guard ratios.count >= Self.estimateSampleMinimum else {
            return nil
        }

        let median = ratios[ratios.count / 2]
        return min(max(median, 0.5), 2)
    }

    /// 1行追加で時間を書かなかったときの所要時間。実際の傾向がはっきりしていれば、それに合わせる
    var quickAddDefaultMinutes: Int {
        guard let ratio = estimateRatio, abs(ratio - 1) >= 0.15 else {
            return Self.defaultQuickAddMinutes
        }

        let adjusted = Double(Self.defaultQuickAddMinutes) * ratio
        return min(max(Int((adjusted / 5).rounded()) * 5, 5), 120)
    }

    /// 1行の入力をどう読み取るか（入力欄の上に出す確認用）
    func previewQuickAdd(
        _ text: String,
        ignoring: Set<QuickAddParser.Part> = []
    ) -> QuickAddParser.Result? {
        QuickAddParser.parse(
            text,
            defaultMinutes: quickAddDefaultMinutes,
            now: logicalNow,
            calendar: calendar,
            ignoring: ignoring
        )
    }

    /// 読み取った日付の短い表示（「明日 15:00」など）
    func describeQuickAddDate(_ date: Date, includesTime: Bool) -> String {
        QuickAddParser.describe(date, includesTime: includesTime, now: logicalNow, calendar: calendar)
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
                // 4時区切りなら、深夜1時に終えたものは前の日の分
                return calendar.isDate(
                    completedAt.addingTimeInterval(-dayStartOffset),
                    inSameDayAs: currentDate.addingTimeInterval(-dayStartOffset)
                )
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
        resetSkipCount(for: task.id)
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
        StepChain.steps(of: parentID, in: tasks)
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
        resetSkipCount(for: parent.id)
        if repeatedSkipCandidate?.id == parent.id {
            repeatedSkipCandidate = nil
        }
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
        StepChain.moveOpenSteps(of: parentID, fromOffsets: source, toOffset: destination, in: &tasks)
        saveTasks()
        updateRecommendation()
    }

    /// 一歩を、決めた順につなぎ直す（中身は `StepChain`）
    private func rebuildStepChain(for parentID: UUID) {
        StepChain.rebuild(parentID: parentID, in: &tasks)
    }

    /// 「次の一歩を決めますか？」を閉じる
    func dismissNextStepOffer() {
        nextStepCandidate = nil
    }

    private func saveSkippedUntil() {
        store.save(skippedUntil, forKey: TaskStore.Key.skippedUntil)
    }

    /// 新しいタスクを追加する
    func addTask(
        title: String,
        estimatedMinutes: Int,
        priority: TaskPriority,
        scheduledDate: Date?,
        deadline: Date?,
        isLight: Bool = false,
        link: URL? = nil
    ) {
        let task = TaskItem(
            title: title,
            estimatedMinutes: estimatedMinutes,
            priority: priority,
            scheduledDate: scheduledDate,
            deadline: deadline,
            updatedAt: now(),
            isLight: isLight,
            link: link
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

    /// 直前に削除したもの。「元に戻す」で戻せるよう、少しのあいだだけ覚えておく
    struct DeletedTasks {
        /// 削除したタスク（一歩も含む）と、一覧のなかでの元の位置。一歩の順番を崩さずに戻すため
        let tasks: [(index: Int, task: TaskItem)]

        /// 削除したタスクを前提にしていたタスク
        let dependentIDs: [UUID]

        /// 表示に使う、消したタスク
        let main: TaskItem
    }

    @Published private(set) var lastDeleted: DeletedTasks?

    /// 指定したタスクを削除する
    func deleteTask(_ task: TaskItem) {
        let removed = tasks.enumerated()
            .filter { $0.element.id == task.id || $0.element.parentTaskID == task.id }
            .map { (index: $0.offset, task: $0.element) }
        guard let main = removed.first(where: { $0.task.id == task.id })?.task else {
            return
        }

        tasks.removeAll { $0.id == task.id || $0.parentTaskID == task.id }

        // 削除したタスクを前提にしていたタスクが、推薦されないまま残らないようにする
        var dependentIDs: [UUID] = []
        for index in tasks.indices where tasks[index].prerequisiteIDs.contains(task.id) {
            tasks[index].prerequisiteIDs.removeAll { $0 == task.id }
            dependentIDs.append(tasks[index].id)
        }
        lastDeleted = DeletedTasks(tasks: removed, dependentIDs: dependentIDs, main: main)

        if lastCompletedTask?.id == task.id {
            lastCompletedTask = nil
        }
        if lastSkippedTask?.id == task.id {
            lastSkippedTask = nil
        }

        // 一歩を消したなら、残りの一歩をつなぎ直す
        if let parentID = task.parentTaskID {
            rebuildStepChain(for: parentID)
        }

        saveTasks()
        updateRecommendation()
    }
    
    /// 直前の削除を取り消す
    func undoDelete() {
        guard let deleted = lastDeleted else {
            return
        }

        lastDeleted = nil
        let existingIDs = Set(tasks.map(\.id))
        for entry in deleted.tasks where !existingIDs.contains(entry.task.id) {
            tasks.insert(entry.task, at: min(entry.index, tasks.count))
        }

        for index in tasks.indices where deleted.dependentIDs.contains(tasks[index].id) {
            if !tasks[index].prerequisiteIDs.contains(deleted.main.id) {
                tasks[index].prerequisiteIDs.append(deleted.main.id)
            }
        }

        if let parentID = deleted.main.parentTaskID {
            rebuildStepChain(for: parentID)
        }

        saveTasks()
        updateRecommendation()
    }

    /// 削除の「元に戻す」を閉じる
    func dismissDeleteUndo() {
        lastDeleted = nil
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
    
    /// 現在のタスク一覧を保存する
    private func saveTasks() {
        store.save(tasks, forKey: TaskStore.Key.tasks)

        // 期限や完了が変わったら、通知も予定し直す（オフなら何もしない）
        scheduleNotifications()
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
            prefersLight: prefersLight,
            dayStartOffset: dayStartOffset
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

        publishWidgetSnapshot()
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
