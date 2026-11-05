import Foundation
import Testing
@testable import TaskFlow

/// テストから進められる時計
@MainActor
private final class RecurringClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func advance(days: Int) {
        now = now.addingTimeInterval(TimeInterval(60 * 60 * 24 * days))
    }
}

/// フェーズ8：定期タスク
@MainActor
struct RecurringTests {

    private let storage = TemporaryUserDefaults(prefix: "RecurringTests")

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func makeViewModel(clock: RecurringClock) -> HomeViewModel {
        HomeViewModel(
            userDefaults: storage.userDefaults,
            seedsSampleTasks: false,
            calendar: calendar,
            now: { clock.now }
        )
    }

    private func occurrences(_ viewModel: HomeViewModel) -> [TaskItem] {
        viewModel.tasks.filter { $0.recurringID != nil }
    }

    // MARK: - きまり

    @Test
    func weeklyRuleMatchesChosenWeekdays() {
        // 2026-11-09 は月曜、11-12 は木曜
        let recurring = RecurringTask(
            title: "ゴミ出し",
            estimatedMinutes: 5,
            recurrence: Recurrence(rule: .weekly(weekdays: [2, 5])),
            startDate: date(2026, 11, 1)
        )

        #expect(recurring.occurs(on: date(2026, 11, 9), calendar: calendar))
        #expect(!recurring.occurs(on: date(2026, 11, 10), calendar: calendar))
        #expect(recurring.occurs(on: date(2026, 11, 12), calendar: calendar))
        // 始める前の日には出ない
        #expect(!recurring.occurs(on: date(2026, 10, 29), calendar: calendar))
    }

    @Test
    func monthlyRuleUsesTheLastDayInShortMonths() {
        let recurring = RecurringTask(
            title: "家賃の確認",
            estimatedMinutes: 10,
            recurrence: Recurrence(rule: .monthly(day: 31)),
            startDate: date(2026, 1, 1)
        )

        #expect(recurring.occurs(on: date(2026, 1, 31), calendar: calendar))
        #expect(recurring.occurs(on: date(2026, 2, 28), calendar: calendar))
        #expect(!recurring.occurs(on: date(2026, 2, 27), calendar: calendar))
        #expect(recurring.occurs(on: date(2026, 4, 30), calendar: calendar))
    }

    @Test
    func everyNDaysCountsFromTheStart() {
        let recurring = RecurringTask(
            title: "水やり",
            estimatedMinutes: 5,
            recurrence: Recurrence(rule: .everyNDays(3)),
            startDate: date(2026, 11, 5)
        )

        #expect(recurring.occurs(on: date(2026, 11, 5), calendar: calendar))
        #expect(!recurring.occurs(on: date(2026, 11, 6), calendar: calendar))
        #expect(recurring.occurs(on: date(2026, 11, 8), calendar: calendar))
    }

    @Test
    func holidaysCanBeSkipped() {
        // 2026-11-23（月）は勤労感謝の日
        var recurring = RecurringTask(
            title: "ゴミ出し",
            estimatedMinutes: 5,
            recurrence: Recurrence(rule: .weekly(weekdays: [2])),
            startDate: date(2026, 11, 1)
        )

        #expect(recurring.occurs(on: date(2026, 11, 23), calendar: calendar))

        recurring.recurrence.skipsHolidays = true

        #expect(!recurring.occurs(on: date(2026, 11, 23), calendar: calendar))
        #expect(recurring.occurs(on: date(2026, 11, 16), calendar: calendar))
    }

    @Test(arguments: [
        "2026-01-12", "2026-05-06", "2026-09-22", "2027-03-22", "2027-07-19"
    ])
    func knownHolidaysIncludeSubstituteAndCitizensHolidays(day: String) {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        #expect(JapaneseHolidays.isHoliday(date(parts[0], parts[1], parts[2]), calendar: calendar))
    }

    @Test
    func summaryReadsNaturally() {
        #expect(Recurrence(rule: .daily).summary == "毎日")
        #expect(Recurrence(rule: .weekly(weekdays: [1, 2, 5])).summary == "毎週 月・木・日")
        #expect(Recurrence(rule: .monthly(day: 20), skipsHolidays: true).summary == "毎月20日（祝日は休み）")
        #expect(Recurrence(rule: .everyNDays(3)).summary == "3日ごと")
    }

    // MARK: - 回の出し方

    @Test
    func todaysOccurrenceAppearsRightAwayAndIsRecommended() throws {
        // 2026-11-09（月）
        let clock = RecurringClock(now: date(2026, 11, 9, 8))
        let viewModel = makeViewModel(clock: clock)

        viewModel.addRecurring(
            title: "ゴミ出し",
            estimatedMinutes: 5,
            recurrence: Recurrence(rule: .weekly(weekdays: [2]))
        )

        let occurrence = try #require(occurrences(viewModel).first)
        #expect(occurrence.title == "ゴミ出し")
        #expect(occurrence.occurrenceDate == date(2026, 11, 9))
        #expect(viewModel.recommendation?.task.id == occurrence.id)
        #expect(viewModel.todayTasks.map(\.id) == [occurrence.id])
    }

    @Test
    func nextOccurrenceAppearsEvenIfThePreviousOneWasNotDone() {
        let clock = RecurringClock(now: date(2026, 11, 9, 8))
        let viewModel = makeViewModel(clock: clock)
        viewModel.addRecurring(
            title: "ゴミ出し",
            estimatedMinutes: 5,
            recurrence: Recurrence(rule: .weekly(weekdays: [2]))
        )

        clock.advance(days: 7)
        viewModel.updateRecommendation()

        // 持ち越さないので、先週の回は静かに消え、今週の回だけがある
        #expect(occurrences(viewModel).map(\.occurrenceDate) == [date(2026, 11, 16)])
        #expect(viewModel.carriedOverTasks.isEmpty)
    }

    @Test
    func carryingOverKeepsThePastOccurrence() {
        let clock = RecurringClock(now: date(2026, 11, 5, 8))
        let viewModel = makeViewModel(clock: clock)
        viewModel.addRecurring(
            title: "日報",
            estimatedMinutes: 10,
            recurrence: Recurrence(rule: .daily, carriesOver: true)
        )

        clock.advance(days: 1)
        viewModel.updateRecommendation()

        #expect(occurrences(viewModel).count == 2)
        #expect(viewModel.carriedOverTasks.count == 1)
    }

    @Test
    func completedOccurrencesStayAndDoNotDuplicate() throws {
        let clock = RecurringClock(now: date(2026, 11, 5, 8))
        let viewModel = makeViewModel(clock: clock)
        viewModel.addRecurring(title: "ストレッチ", estimatedMinutes: 5, recurrence: Recurrence(rule: .daily))

        viewModel.completeRecommendation()
        viewModel.updateRecommendation()

        #expect(occurrences(viewModel).count == 1)
        #expect(viewModel.completedToday.map(\.title) == ["ストレッチ"])

        clock.advance(days: 1)
        viewModel.updateRecommendation()

        // 昨日の済みの回は残り、今日の回が増える
        #expect(occurrences(viewModel).count == 2)
        #expect(viewModel.recommendation?.task.occurrenceDate == date(2026, 11, 6))
    }

    @Test
    func skippingAnOccurrenceKeepsItAwayForThatDayOnly() throws {
        let clock = RecurringClock(now: date(2026, 11, 5, 8))
        let viewModel = makeViewModel(clock: clock)
        viewModel.addRecurring(title: "ストレッチ", estimatedMinutes: 5, recurrence: Recurrence(rule: .daily))
        let today = try #require(occurrences(viewModel).first)

        viewModel.skipOccurrence(today)
        viewModel.updateRecommendation()

        #expect(occurrences(viewModel).isEmpty)
        #expect(viewModel.recommendation == nil)

        clock.advance(days: 1)
        viewModel.updateRecommendation()

        #expect(occurrences(viewModel).count == 1)
    }

    @Test
    func updatingAndDeletingTheTemplate() throws {
        let clock = RecurringClock(now: date(2026, 11, 5, 8))
        let viewModel = makeViewModel(clock: clock)
        viewModel.addRecurring(title: "ストレッチ", estimatedMinutes: 5, recurrence: Recurrence(rule: .daily))

        var template = try #require(viewModel.recurringTasks.first)
        template.title = "ストレッチと深呼吸"
        template.estimatedMinutes = 10
        viewModel.updateRecurring(template)

        #expect(occurrences(viewModel).first?.title == "ストレッチと深呼吸")
        #expect(occurrences(viewModel).first?.estimatedMinutes == 10)

        viewModel.deleteRecurring(template)

        #expect(viewModel.recurringTasks.isEmpty)
        #expect(occurrences(viewModel).isEmpty)
    }

    @Test
    func templatesSurviveRelaunch() {
        let clock = RecurringClock(now: date(2026, 11, 5, 8))
        let first = makeViewModel(clock: clock)
        first.addRecurring(title: "ストレッチ", estimatedMinutes: 5, recurrence: Recurrence(rule: .daily))

        let relaunched = makeViewModel(clock: clock)

        #expect(relaunched.recurringTasks.map(\.title) == ["ストレッチ"])
        #expect(occurrences(relaunched).count == 1)
    }

    // MARK: - 1行追加

    @Test
    func quickAddReadsRecurrence() throws {
        let now = date(2026, 11, 5, 10)
        let parse = { (text: String) in
            QuickAddParser.parse(text, defaultMinutes: 30, now: now, calendar: calendar)
        }

        let weekly = try #require(parse("毎週月曜にゴミ出し 5分"))
        #expect(weekly.title == "ゴミ出し")
        #expect(weekly.recurrence == Recurrence(rule: .weekly(weekdays: [2])))
        #expect(weekly.estimatedMinutes == 5)
        // 「月曜」を予定日としては読まない
        #expect(weekly.scheduledDate == nil)

        #expect(parse("毎週月・木 ジム")?.recurrence == Recurrence(rule: .weekly(weekdays: [2, 5])))
        #expect(parse("毎日ストレッチ")?.recurrence == Recurrence(rule: .daily))
        #expect(parse("毎月25日に家計簿")?.recurrence == Recurrence(rule: .monthly(day: 25)))
        #expect(parse("3日ごとに水やり")?.recurrence == Recurrence(rule: .everyNDays(3)))
        #expect(parse("毎日ストレッチ")?.title == "ストレッチ")
        #expect(parse("毎日")?.recurrence == nil)
    }

    @Test
    func quickAddWithRecurrenceCreatesATemplate() {
        let clock = RecurringClock(now: date(2026, 11, 9, 8))
        let viewModel = makeViewModel(clock: clock)

        viewModel.quickAdd("毎週月曜にゴミ出し 5分")

        #expect(viewModel.recurringTasks.map(\.title) == ["ゴミ出し"])
        #expect(occurrences(viewModel).count == 1)
    }

    // MARK: - 編集してもくり返しの情報を失わない

    @Test
    func legacyTaskDecodesWithoutRecurrenceFields() throws {
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

        #expect(decoded.recurringID == nil)
        #expect(decoded.occurrenceDate == nil)
    }
}
