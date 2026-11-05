import Foundation
import Testing
@testable import TaskFlow

/// 自然言語の1行追加と、完了まわり（今日やったこと・ひとこと・分けたタスクの区切り）
@MainActor
struct InputAndJoyTests {

    private let storage = TemporaryUserDefaults(prefix: "InputAndJoyTests")

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    /// 2026-11-05（木）10:00（日本時間）
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 10))!
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

    // MARK: - 自然言語の1行追加

    @Test
    func quickAddWithDateSetsScheduleAndWaitsUntilThatDay() throws {
        let viewModel = makeViewModel()

        viewModel.quickAdd("明日の15時に資料作成")

        let task = try #require(viewModel.tasks.first)
        #expect(task.title == "資料作成")
        #expect(task.scheduledDate == calendar.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 15)))

        // 予定日が明日なので、今日は推薦しない
        #expect(viewModel.recommendation == nil)
        #expect(viewModel.noRecommendationSummary?.scheduledLaterCount == 1)
        #expect(viewModel.noRecommendationSummary?.allCompleted == false)
    }

    @Test
    func quickAddWithDeadlineIsRecommendedNow() {
        let viewModel = makeViewModel()

        viewModel.quickAdd("金曜までにレポート 30分")

        #expect(viewModel.tasks.first?.deadline != nil)
        #expect(viewModel.recommendation?.task.title == "レポート")
    }

    @Test
    func quickAddCanIgnoreTheDate() {
        let viewModel = makeViewModel()

        viewModel.quickAdd("3時のおやつ", ignoring: [.when])

        #expect(viewModel.tasks.first?.title == "3時のおやつ")
        #expect(viewModel.tasks.first?.scheduledDate == nil)
    }

    // MARK: - 今日やったこと

    @Test
    func completedTodayListsOnlyTasksFinishedToday() {
        let viewModel = makeViewModel()
        viewModel.quickAdd("A 10分")
        viewModel.quickAdd("B 20分")

        viewModel.completeRecommendation()

        #expect(viewModel.completedToday.map(\.title) == ["A"])
        #expect(viewModel.tasks.first { $0.title == "A" }?.completedAt == now)

        viewModel.undo()

        #expect(viewModel.completedToday.isEmpty)
        #expect(viewModel.tasks.first { $0.title == "A" }?.completedAt == nil)
    }

    @Test
    func togglingFromListSetsAndClearsCompletedAt() throws {
        let viewModel = makeViewModel()
        viewModel.quickAdd("A 10分")
        let task = try #require(viewModel.tasks.first)

        viewModel.toggleCompletion(for: task)
        #expect(viewModel.tasks.first?.completedAt == now)

        viewModel.toggleCompletion(for: task)
        #expect(viewModel.tasks.first?.completedAt == nil)
    }

    @Test
    func editingKeepsCompletedAtAndSplitGroup() throws {
        let groupID = UUID()
        var task = TaskItem(
            title: "A",
            isCompleted: true,
            estimatedMinutes: 10,
            completedAt: now,
            splitGroupID: groupID
        )

        let data = try JSONEncoder().encode(task)
        task = try JSONDecoder().decode(TaskItem.self, from: data)

        #expect(task.completedAt == now)
        #expect(task.splitGroupID == groupID)
    }

    // MARK: - 分けたタスクの区切り

    @Test
    func finishingTheLastSplitPartIsDetected() throws {
        let viewModel = makeViewModel()
        viewModel.quickAdd("発表資料を作る 60分")
        let big = try #require(viewModel.tasks.first)

        viewModel.splitTask(big, into: TaskSplitter.defaultParts(for: big, count: 2))
        #expect(Set(viewModel.tasks.compactMap(\.splitGroupID)) == [big.id])

        viewModel.completeRecommendation()
        let first = try #require(viewModel.lastCompletedTask)
        #expect(!viewModel.finishedWholeSplitGroup(of: first))

        viewModel.completeRecommendation()
        let last = try #require(viewModel.lastCompletedTask)
        #expect(viewModel.finishedWholeSplitGroup(of: last))
        #expect(CompletionMessages.message(for: last, finishedGroup: true) == "「発表資料を作る」が全部終わりました")
    }

    @Test
    func splittingAPartKeepsTheOriginalGroup() throws {
        let original = TaskItem(title: "大掃除", estimatedMinutes: 120)
        let firstSplit = TaskSplitter.split(
            original,
            into: TaskSplitter.defaultParts(for: original, count: 2),
            in: [original],
            now: now
        )
        let part = try #require(firstSplit.first)

        let secondSplit = TaskSplitter.split(
            part,
            into: TaskSplitter.defaultParts(for: part, count: 2),
            in: firstSplit,
            now: now
        )

        #expect(secondSplit.allSatisfy { $0.splitGroupID == original.id })
    }

    // MARK: - ひとこと

    @Test
    func messagesVaryAndMentionMinutes() {
        let task = TaskItem(title: "請求書を送る", estimatedMinutes: 15)

        let messages = Set((0..<4).map {
            CompletionMessages.message(for: task, finishedGroup: false, randomIndex: $0)
        })

        #expect(messages.count == 4)
        #expect(messages.contains("15分ぶん、前に進みました"))
    }

    @Test
    func baseTitleDropsThePartNumber() {
        #expect(CompletionMessages.baseTitle(of: "発表資料を作る（3/3）") == "発表資料を作る")
        #expect(CompletionMessages.baseTitle(of: "そのまま") == "そのまま")
    }
}
