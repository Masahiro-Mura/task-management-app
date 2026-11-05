import Foundation
import Testing
@testable import TaskFlow

/// 通知を実際には出さず、予定された内容を記録する
@MainActor
private final class FakeNotifier: NotificationScheduling {
    var grantsPermission = true
    private(set) var authorizationRequests = 0
    private(set) var scheduled: [PlannedNotification] = []
    private(set) var replaceCount = 0
    private(set) var badgeClears = 0

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        return grantsPermission
    }

    func replaceAll(with notifications: [PlannedNotification]) {
        scheduled = notifications
        replaceCount += 1
    }

    func clearBadge() {
        badgeClears += 1
    }
}

@MainActor
private final class TidyClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func advance(days: Double = 0, hours: Double = 0) {
        now = now.addingTimeInterval(days * 24 * 60 * 60 + hours * 60 * 60)
    }
}

/// フェーズ9：通知と片づけ
@MainActor
struct NotifyAndTidyTests {

    private let storage = TemporaryUserDefaults(prefix: "NotifyAndTidyTests")

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func makeViewModel(clock: TidyClock, notifier: FakeNotifier) -> HomeViewModel {
        HomeViewModel(
            userDefaults: storage.userDefaults,
            seedsSampleTasks: false,
            calendar: calendar,
            now: { clock.now },
            notifier: notifier
        )
    }

    // MARK: - 通知の決め方

    @Test
    func deadlineRemindersFireThreeHoursBeforeOnlyForOpenFutureDeadlines() {
        let now = date(2026, 11, 5, 10)
        let soon = TaskItem(title: "申請書", estimatedMinutes: 15, deadline: date(2026, 11, 5, 18))
        let tooSoon = TaskItem(title: "もうすぐ", estimatedMinutes: 15, deadline: date(2026, 11, 5, 12))
        let done = TaskItem(title: "済み", isCompleted: true, estimatedMinutes: 15, deadline: date(2026, 11, 6))
        let noDeadline = TaskItem(title: "期限なし", estimatedMinutes: 15)

        let reminders = NotificationPlanner.deadlineReminders(for: [soon, tooSoon, done, noDeadline], now: now)

        #expect(reminders.count == 1)
        #expect(reminders.first?.fireDate == date(2026, 11, 5, 15))
        #expect(reminders.first?.id.hasPrefix(NotificationPlanner.idPrefix) == true)
        #expect(reminders.first?.body.contains("「申請書」") == true)
    }

    @Test
    func dailyFireDateIsTodayOrTomorrow() {
        let morning = NotificationPlanner.nextDailyFireDate(
            minutesFromMidnight: 8 * 60,
            now: date(2026, 11, 5, 7),
            calendar: calendar
        )
        let afterwards = NotificationPlanner.nextDailyFireDate(
            minutesFromMidnight: 8 * 60,
            now: date(2026, 11, 5, 9),
            calendar: calendar
        )

        #expect(morning == date(2026, 11, 5, 8))
        #expect(afterwards == date(2026, 11, 6, 8))
    }

    @Test
    func ignoreCountResetsWhenOpenedSoonAfterAndGrowsOtherwise() {
        let fire = date(2026, 11, 5, 8)

        #expect(NotificationPlanner.updatedIgnoreCount(previous: 2, lastFireDate: fire, openedAt: date(2026, 11, 5, 9)) == 0)
        #expect(NotificationPlanner.updatedIgnoreCount(previous: 2, lastFireDate: fire, openedAt: date(2026, 11, 6, 9)) == 3)
        // まだ出ていなければ数えない
        #expect(NotificationPlanner.updatedIgnoreCount(previous: 2, lastFireDate: fire, openedAt: date(2026, 11, 5, 7)) == 2)
        #expect(NotificationPlanner.updatedIgnoreCount(previous: 1, lastFireDate: nil, openedAt: fire) == 1)
    }

    // MARK: - 通知の設定

    @Test
    func nothingIsScheduledUntilTheUserTurnsItOn() {
        let notifier = FakeNotifier()
        let viewModel = makeViewModel(clock: TidyClock(now: date(2026, 11, 5, 10)), notifier: notifier)

        viewModel.addTask(title: "申請書", estimatedMinutes: 15, priority: .medium, scheduledDate: nil, deadline: date(2026, 11, 5, 18))

        #expect(notifier.replaceCount == 0)
        #expect(notifier.authorizationRequests == 0)
    }

    @Test
    func deadlineNotificationsFollowTheTasks() async throws {
        let notifier = FakeNotifier()
        let viewModel = makeViewModel(clock: TidyClock(now: date(2026, 11, 5, 10)), notifier: notifier)
        viewModel.addTask(title: "申請書", estimatedMinutes: 15, priority: .medium, scheduledDate: nil, deadline: date(2026, 11, 5, 18))

        await viewModel.setDeadlineNotifications(true)

        #expect(viewModel.deadlineNotificationsEnabled)
        #expect(notifier.scheduled.map(\.fireDate) == [date(2026, 11, 5, 15)])

        // 終えたら、その通知は消える
        let task = try #require(viewModel.tasks.first)
        viewModel.toggleCompletion(for: task)
        #expect(notifier.scheduled.isEmpty)

        await viewModel.setDeadlineNotifications(false)
        #expect(!viewModel.deadlineNotificationsEnabled)
    }

    @Test
    func deniedPermissionKeepsItOffAndSaysSo() async {
        let notifier = FakeNotifier()
        notifier.grantsPermission = false
        let viewModel = makeViewModel(clock: TidyClock(now: date(2026, 11, 5, 10)), notifier: notifier)

        await viewModel.setDailyPick(true)

        #expect(!viewModel.dailyPickEnabled)
        #expect(viewModel.notificationPermissionDenied)
    }

    @Test
    func dailyPickNamesTheTaskForThatTime() async {
        let notifier = FakeNotifier()
        let viewModel = makeViewModel(clock: TidyClock(now: date(2026, 11, 5, 10)), notifier: notifier)
        viewModel.quickAdd("請求書を送る 15分")

        await viewModel.setDailyPick(true)

        let daily = notifier.scheduled.first { $0.id == NotificationPlanner.idPrefix + "daily" }
        #expect(daily?.fireDate == date(2026, 11, 6, 8))
        #expect(daily?.body.contains("「請求書を送る」") == true)
    }

    @Test
    func dailyPickStopsAfterBeingIgnoredThreeTimes() async {
        let clock = TidyClock(now: date(2026, 11, 5, 10))
        let notifier = FakeNotifier()
        let viewModel = makeViewModel(clock: clock, notifier: notifier)
        await viewModel.setDailyPick(true)

        // 3日続けて、通知から半日以上たってから開く
        for _ in 0..<3 {
            clock.advance(days: 1, hours: 12)
            viewModel.appDidBecomeActive()
        }

        #expect(!viewModel.dailyPickEnabled)
        #expect(viewModel.dailyPickPausedByIgnore)
        #expect(!notifier.scheduled.contains { $0.id.hasSuffix("daily") })
    }

    @Test
    func openingSoonAfterTheNotificationKeepsItOn() async {
        let clock = TidyClock(now: date(2026, 11, 5, 10))
        let notifier = FakeNotifier()
        let viewModel = makeViewModel(clock: clock, notifier: notifier)
        await viewModel.setDailyPick(true)

        for _ in 0..<4 {
            // 翌朝8時の通知の30分後に開く
            clock.now = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: clock.now))!
                .addingTimeInterval(8.5 * 60 * 60)
            viewModel.appDidBecomeActive()
        }

        #expect(viewModel.dailyPickEnabled)
        #expect(!viewModel.dailyPickPausedByIgnore)
    }

    @Test
    func activatingClearsTheBadge() {
        let notifier = FakeNotifier()
        let viewModel = makeViewModel(clock: TidyClock(now: date(2026, 11, 5, 10)), notifier: notifier)

        viewModel.appDidBecomeActive()

        #expect(notifier.badgeClears == 1)
    }

    // MARK: - 完了を隠す

    @Test
    func completedTasksHideAfterSevenDays() throws {
        let clock = TidyClock(now: date(2026, 11, 5, 10))
        let viewModel = makeViewModel(clock: clock, notifier: FakeNotifier())
        viewModel.quickAdd("A 10分")
        viewModel.quickAdd("B 10分")
        let a = try #require(viewModel.tasks.first)
        viewModel.toggleCompletion(for: a)

        clock.advance(days: 6)
        #expect(viewModel.visibleAllTasks.count == 2)

        clock.advance(days: 1)
        #expect(viewModel.visibleAllTasks.map(\.title) == ["B"])
        #expect(viewModel.hiddenCompletedTasks.map(\.title) == ["A"])
        // 消してはいない
        #expect(viewModel.tasks.count == 2)
    }

    // MARK: - 手放す

    @Test
    func longDormantTasksAreOfferedMonthlyAndCanBeLetGoAndRestored() throws {
        let clock = TidyClock(now: date(2026, 11, 5, 10))
        let viewModel = makeViewModel(clock: clock, notifier: FakeNotifier())
        viewModel.quickAdd("いつかやる 10分")
        let task = try #require(viewModel.tasks.first)

        clock.advance(days: 30)
        #expect(viewModel.longDormantTasks.isEmpty)
        #expect(!viewModel.shouldOfferLetGo)

        clock.advance(days: 31)
        #expect(viewModel.longDormantTasks.map(\.id) == [task.id])
        #expect(viewModel.shouldOfferLetGo)

        viewModel.dismissLetGoOffer()
        #expect(!viewModel.shouldOfferLetGo)

        clock.advance(days: 30)
        #expect(viewModel.shouldOfferLetGo)

        viewModel.letGo([task.id])

        #expect(viewModel.tasks.isEmpty)
        #expect(viewModel.archivedTasks.map(\.id) == [task.id])
        #expect(!viewModel.shouldOfferLetGo)

        // 保管は次に開いても残る
        let relaunched = makeViewModel(clock: clock, notifier: FakeNotifier())
        #expect(relaunched.archivedTasks.map(\.id) == [task.id])

        viewModel.restoreArchived(task)

        #expect(viewModel.archivedTasks.isEmpty)
        #expect(viewModel.tasks.map(\.id) == [task.id])
        #expect(viewModel.dormantTaskIDs.isEmpty)
        #expect(viewModel.recommendation?.task.id == task.id)
    }

    @Test
    func deletingFromStorageIsPermanent() throws {
        let clock = TidyClock(now: date(2026, 11, 5, 10))
        let viewModel = makeViewModel(clock: clock, notifier: FakeNotifier())
        viewModel.quickAdd("いつかやる 10分")
        let task = try #require(viewModel.tasks.first)
        viewModel.letGo([task.id])

        viewModel.deleteArchived(task)

        #expect(viewModel.archivedTasks.isEmpty)
        #expect(viewModel.tasks.isEmpty)
    }
}
