import Foundation
import Testing
@testable import TaskFlow

/// テストから進められる時計
@MainActor
private final class TestClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func advance(days: Double) {
        now = now.addingTimeInterval(60 * 60 * 24 * days)
    }
}

@MainActor
struct HomeScheduleTests {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    /// 2026-11-05 12:00（日本時間）
    private var noon: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 12))!
    }

    private func day(_ offset: Int, hour: Int = 10) -> Date {
        let start = calendar.startOfDay(for: noon)
        return calendar.date(
            byAdding: DateComponents(day: offset, hour: hour),
            to: start
        )!
    }

    /// テストごとに独立した保存先。テストが終わると消える
    private let storage = TemporaryUserDefaults(prefix: "HomeScheduleTests")

    private func makeViewModel(clock: TestClock) -> HomeViewModel {
        HomeViewModel(
            userDefaults: storage.userDefaults,
            seedsSampleTasks: false,
            calendar: calendar,
            now: { clock.now }
        )
    }

    private func add(
        _ viewModel: HomeViewModel,
        _ title: String,
        minutes: Int = 10,
        scheduledDate: Date? = nil,
        deadline: Date? = nil
    ) -> TaskItem {
        viewModel.addTask(
            title: title,
            estimatedMinutes: minutes,
            priority: .medium,
            scheduledDate: scheduledDate,
            deadline: deadline
        )
        return viewModel.tasks.last!
    }

    // MARK: - 今日・明日の欄

    @Test
    func todayIncludesScheduledDeadlineAndCarriedOverTasks() {
        let clock = TestClock(now: noon)
        let viewModel = makeViewModel(clock: clock)

        let scheduledToday = add(viewModel, "予定が今日", scheduledDate: day(0))
        let dueToday = add(viewModel, "期限が今日", deadline: day(0, hour: 18))
        let scheduledYesterday = add(viewModel, "予定が昨日", scheduledDate: day(-1))
        let overdue = add(viewModel, "期限が昨日", deadline: day(-1, hour: 18))
        let unscheduled = add(viewModel, "日付なし")

        let todayIDs = Set(viewModel.todayTasks.map(\.id))

        #expect(todayIDs == [scheduledToday.id, dueToday.id, scheduledYesterday.id, overdue.id])
        #expect(!todayIDs.contains(unscheduled.id))

        #expect(!viewModel.isCarriedOver(scheduledToday))
        #expect(!viewModel.isCarriedOver(dueToday))
        #expect(viewModel.isCarriedOver(scheduledYesterday))
        #expect(viewModel.isCarriedOver(overdue))
    }

    @Test
    func completedPastTaskIsNotCarriedOver() {
        let clock = TestClock(now: noon)
        let viewModel = makeViewModel(clock: clock)

        let task = add(viewModel, "昨日やった", scheduledDate: day(-1))
        viewModel.toggleCompletion(for: task)

        #expect(viewModel.todayTasks.isEmpty)
    }

    @Test
    func tomorrowDoesNotRepeatTasksShownToday() {
        let clock = TestClock(now: noon)
        let viewModel = makeViewModel(clock: clock)

        let tomorrowOnly = add(viewModel, "明日やる", scheduledDate: day(1))
        let dueToday = add(viewModel, "明日予定だが期限は今日", scheduledDate: day(1), deadline: day(0, hour: 18))

        #expect(viewModel.tomorrowTasks.map(\.id) == [tomorrowOnly.id])
        #expect(viewModel.todayTasks.map(\.id) == [dueToday.id])
    }

    // MARK: - 冬眠と起こす

    @Test
    func untouchedTaskGoesDormantAndCanBeWoken() {
        let clock = TestClock(now: noon)
        let viewModel = makeViewModel(clock: clock)

        let task = add(viewModel, "いつかやる")
        #expect(viewModel.recommendation?.task.id == task.id)

        clock.advance(days: 15)
        viewModel.updateRecommendation()

        #expect(viewModel.dormantTaskIDs == [task.id])
        #expect(viewModel.recommendation == nil)
        #expect(viewModel.noRecommendationSummary?.dormantCount == 1)

        viewModel.wakeTask(task)

        #expect(viewModel.dormantTaskIDs.isEmpty)
        #expect(viewModel.recommendation?.task.id == task.id)
    }

    @Test
    func dormantCarriedOverTaskLeavesToday() {
        let clock = TestClock(now: noon)
        let viewModel = makeViewModel(clock: clock)

        let task = add(viewModel, "予定が今日", scheduledDate: day(0))

        clock.advance(days: 15)

        #expect(viewModel.dormantTaskIDs == [task.id])
        #expect(viewModel.todayTasks.isEmpty)
    }

    @Test
    func togglingAndEditingResetTheDormancyClock() {
        let clock = TestClock(now: noon)
        let viewModel = makeViewModel(clock: clock)

        var task = add(viewModel, "触る")

        clock.advance(days: 10)
        viewModel.toggleCompletion(for: task)
        viewModel.toggleCompletion(for: task)

        clock.advance(days: 10)
        #expect(viewModel.dormantTaskIDs.isEmpty)

        clock.advance(days: 5)
        #expect(viewModel.dormantTaskIDs == [task.id])

        task = viewModel.tasks[0]
        task.title = "触った"
        viewModel.updateTask(task)

        #expect(viewModel.dormantTaskIDs.isEmpty)
    }
}
