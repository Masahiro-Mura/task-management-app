import Foundation
import Testing
@testable import TaskFlow

/// フェーズ6：まとめて組み直す・今日やりたい・「高」は3件まで・気が乗らないとき
@MainActor
struct RescheduleAndMoodTests {

    private let storage = TemporaryUserDefaults(prefix: "RescheduleAndMoodTests")

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    /// 2026-11-05（木）10:00（日本時間）
    private var now: Date {
        date(2026, 11, 5, 10)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func makeViewModel() -> HomeViewModel {
        let now = now
        return HomeViewModel(
            userDefaults: storage.userDefaults,
            seedsSampleTasks: false,
            calendar: calendar,
            now: { now }
        )
    }

    private func add(
        _ viewModel: HomeViewModel,
        _ title: String,
        minutes: Int = 30,
        priority: TaskPriority = .medium,
        scheduledDate: Date? = nil,
        deadline: Date? = nil,
        isLight: Bool = false
    ) -> TaskItem {
        viewModel.addTask(
            title: title,
            estimatedMinutes: minutes,
            priority: priority,
            scheduledDate: scheduledDate,
            deadline: deadline,
            isLight: isLight
        )
        return viewModel.tasks.last!
    }

    private func task(_ viewModel: HomeViewModel, _ id: UUID) -> TaskItem? {
        viewModel.tasks.first { $0.id == id }
    }

    // MARK: - まとめて組み直す

    @Test
    func reschedulingToTomorrowMovesScheduleAndOverdueDeadline() throws {
        let viewModel = makeViewModel()
        let scheduled = add(viewModel, "昨日の予定", scheduledDate: date(2026, 11, 4, 9))
        let overdue = add(viewModel, "昨日の期限", deadline: date(2026, 11, 4, 18))
        let later = add(viewModel, "来週の期限", deadline: date(2026, 11, 12, 18))

        #expect(viewModel.carriedOverTasks.count == 2)

        viewModel.reschedule([scheduled.id, overdue.id, later.id], to: .tomorrow)

        #expect(task(viewModel, scheduled.id)?.scheduledDate == date(2026, 11, 6))
        // 過ぎた期限は、同じ時刻のまま明日に移す
        #expect(task(viewModel, overdue.id)?.deadline == date(2026, 11, 6, 18))
        // まだ先の期限は動かさない
        #expect(task(viewModel, later.id)?.deadline == date(2026, 11, 12, 18))
        #expect(viewModel.carriedOverTasks.isEmpty)
    }

    @Test
    func reschedulingToNextMondayFromThursday() throws {
        let viewModel = makeViewModel()
        let item = add(viewModel, "昨日の予定", scheduledDate: date(2026, 11, 4))

        viewModel.reschedule([item.id], to: .nextMonday)

        #expect(task(viewModel, item.id)?.scheduledDate == date(2026, 11, 9))
    }

    @Test
    func clearingDatesMakesItSomeday() throws {
        let viewModel = makeViewModel()
        let item = add(viewModel, "昨日の期限", scheduledDate: date(2026, 11, 4), deadline: date(2026, 11, 4, 18))

        viewModel.reschedule([item.id], to: .clearDates)

        let updated = try #require(task(viewModel, item.id))
        #expect(updated.scheduledDate == nil)
        #expect(updated.deadline == nil)
        #expect(!viewModel.isCarriedOver(updated))
        #expect(viewModel.dormantTaskIDs.isEmpty)
    }

    @Test
    func hibernatingPutsItToSleepRightAway() {
        let viewModel = makeViewModel()
        let item = add(viewModel, "昨日の予定", minutes: 10, scheduledDate: date(2026, 11, 4))

        viewModel.reschedule([item.id], to: .hibernate)

        #expect(viewModel.dormantTaskIDs == [item.id])
        #expect(viewModel.recommendation == nil)
        #expect(viewModel.todayTasks.isEmpty)

        viewModel.wakeTask(item)
        #expect(viewModel.dormantTaskIDs.isEmpty)
    }

    @Test
    func reschedulingSkipsCompletedTasks() throws {
        let viewModel = makeViewModel()
        let item = add(viewModel, "済み", scheduledDate: date(2026, 11, 4))
        viewModel.toggleCompletion(for: item)

        viewModel.reschedule([item.id], to: .tomorrow)

        #expect(task(viewModel, item.id)?.scheduledDate == date(2026, 11, 4))
    }

    // MARK: - 今日やりたい

    @Test
    func pinnedTaskIsRecommendedBeforeHigherPriorityAndShowsToday() throws {
        let viewModel = makeViewModel()
        let important = add(viewModel, "大事", minutes: 10, priority: .high)
        let pinned = add(viewModel, "今日少し進めたい", minutes: 30, deadline: date(2026, 11, 12))

        #expect(viewModel.recommendation?.task.id == important.id)

        viewModel.togglePinnedForToday(pinned)

        #expect(viewModel.recommendation?.task.id == pinned.id)
        #expect(viewModel.recommendation?.factor == .pinnedToday)
        #expect(viewModel.recommendation?.reason.hasPrefix("今日やりたいと決めていて、") == true)
        #expect(viewModel.todayTasks.map(\.id) == [pinned.id])
        #expect(viewModel.pinnedTaskIDs == [pinned.id])
        // 日付はいじらない
        #expect(task(viewModel, pinned.id)?.deadline == date(2026, 11, 12))

        viewModel.togglePinnedForToday(pinned)
        #expect(viewModel.pinnedTaskIDs.isEmpty)
    }

    @Test
    func pinFromYesterdayNoLongerCounts() {
        let yesterdayPin = TaskItem(
            title: "昨日の印",
            estimatedMinutes: 10,
            pinnedForTodayAt: date(2026, 11, 4, 20)
        )

        #expect(!yesterdayPin.isPinnedForToday(at: now, calendar: calendar))
    }

    // MARK: - 「高」は3件まで

    @Test
    func highPriorityIsLimitedToThree() throws {
        let viewModel = makeViewModel()
        let first = add(viewModel, "高1", priority: .high)
        _ = add(viewModel, "高2", priority: .high)
        #expect(!viewModel.needsToLowerAHighPriority(excluding: nil))

        _ = add(viewModel, "高3", priority: .high)
        #expect(viewModel.needsToLowerAHighPriority(excluding: nil))
        // 自分がその3件の1つなら、高のままでよい
        #expect(!viewModel.needsToLowerAHighPriority(excluding: first.id))

        viewModel.lowerPriority(of: first.id)

        #expect(task(viewModel, first.id)?.priority == .medium)
        #expect(viewModel.otherHighPriorityTasks(excluding: nil).count == 2)
    }

    @Test
    func completedHighTasksDoNotCount() throws {
        let viewModel = makeViewModel()
        let done = add(viewModel, "高・済み", priority: .high)
        viewModel.toggleCompletion(for: done)
        _ = add(viewModel, "高2", priority: .high)
        _ = add(viewModel, "高3", priority: .high)

        #expect(!viewModel.needsToLowerAHighPriority(excluding: nil))
    }

    // MARK: - 気が乗らないとき

    @Test
    func skippingOffersLightModeWhichRecommendsEasyTasks() {
        let viewModel = makeViewModel()
        _ = add(viewModel, "企画書を書く", minutes: 45, priority: .high)
        _ = add(viewModel, "資料を読む", minutes: 30)
        let light = add(viewModel, "メールを整理する", minutes: 25, isLight: true)

        viewModel.skipRecommendation()
        #expect(viewModel.isOfferingLightMode)

        viewModel.setPrefersLight(true)

        #expect(!viewModel.isOfferingLightMode)
        #expect(viewModel.recommendation?.task.id == light.id)
        #expect(viewModel.recommendation?.reason.hasPrefix("頭を使わずにできる軽い作業で、") == true)
    }

    @Test
    func lightModeAlsoAcceptsShortTasks() {
        let viewModel = makeViewModel()
        _ = add(viewModel, "企画書を書く", minutes: 45)
        let short = add(viewModel, "電話を1本", minutes: 10)

        viewModel.setPrefersLight(true)

        #expect(viewModel.recommendation?.task.id == short.id)
        #expect(viewModel.recommendation?.reason.hasPrefix("10分で終わる短い作業で、") == true)
    }

    @Test
    func lightModeWithNothingEasyIsHonestAndReversible() {
        let viewModel = makeViewModel()
        let heavy = add(viewModel, "企画書を書く", minutes: 45)

        viewModel.setPrefersLight(true)

        #expect(viewModel.recommendation == nil)
        #expect(viewModel.lightModeHasNoMatch)

        viewModel.setPrefersLight(false)

        #expect(!viewModel.lightModeHasNoMatch)
        #expect(viewModel.recommendation?.task.id == heavy.id)
    }

    // MARK: - 1行追加の「軽」

    @Test
    func quickAddReadsTheLightMark() {
        let parse = { (text: String, ignoring: Set<QuickAddParser.Part>) in
            QuickAddParser.parse(text, defaultMinutes: 30, now: now, calendar: calendar, ignoring: ignoring)
        }

        let light = parse("メール整理 軽 10分", [])
        #expect(light?.title == "メール整理")
        #expect(light?.isLight == true)
        #expect(light?.estimatedMinutes == 10)

        #expect(parse("（軽）洗濯物をたたむ", [])?.isLight == true)
        #expect(parse("（軽）洗濯物をたたむ", [])?.title == "洗濯物をたたむ")

        // 単語の一部の「軽」は読まない
        #expect(parse("軽井沢の宿を探す", [])?.isLight == false)
        #expect(parse("軽井沢の宿を探す", [])?.title == "軽井沢の宿を探す")

        #expect(parse("メール整理 軽", [.light])?.title == "メール整理 軽")
    }

    // MARK: - 保存データの後方互換

    @Test
    func legacyDataWithoutNewFieldsDecodes() throws {
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "title": "古いデータ",
            "isCompleted": false,
            "estimatedMinutes": 15,
            "prerequisiteIDs": []
        }
        """

        let decoded = try JSONDecoder().decode(TaskItem.self, from: Data(json.utf8))

        #expect(decoded.pinnedForTodayAt == nil)
        #expect(decoded.isLight == false)
        #expect(decoded.completedAt == nil)
        #expect(decoded.splitGroupID == nil)
    }
}
