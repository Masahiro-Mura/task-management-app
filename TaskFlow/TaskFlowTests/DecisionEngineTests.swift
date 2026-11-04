import Foundation
import Testing
@testable import TaskFlow

struct DecisionEngineTests {

    private let engine = DecisionEngine()
    // タスクの updatedAt は作成時刻になるため、冬眠と判定されないよう現在時刻を基準にする
    private let now = Date()

    private func recommend(
        _ tasks: [TaskItem],
        availableMinutes: Int = 45
    ) -> TaskRecommendation? {
        engine.recommend(
            from: tasks,
            context: DecisionContext(
                availableMinutes: availableMinutes,
                currentDate: now
            )
        )
    }

    @Test
    func returnsNilForEmptyTasks() {
        #expect(recommend([]) == nil)
    }

    @Test
    func returnsNilWhenAllTasksAreCompleted() {
        let tasks = [
            TaskItem(title: "A", isCompleted: true, estimatedMinutes: 10),
            TaskItem(title: "B", isCompleted: true, estimatedMinutes: 20)
        ]

        #expect(recommend(tasks) == nil)
    }

    @Test
    func skipsTaskLongerThanAvailableTime() {
        let longTask = TaskItem(
            title: "発表資料を作る",
            estimatedMinutes: 90,
            deadline: now.addingTimeInterval(60 * 30)
        )
        let shortTask = TaskItem(title: "メールを返す", estimatedMinutes: 15)

        #expect(recommend([longTask, shortTask])?.task.id == shortTask.id)
        #expect(recommend([longTask]) == nil)
    }

    @Test
    func taskExactlyFittingAvailableTimeIsExecutable() {
        let task = TaskItem(title: "ちょうど45分", estimatedMinutes: 45)

        #expect(recommend([task])?.task.id == task.id)
    }

    @Test
    func skipsTaskWithIncompletePrerequisite() {
        let preparation = TaskItem(title: "資料を集める", estimatedMinutes: 60)
        let writing = TaskItem(
            title: "レポートを書く",
            estimatedMinutes: 30,
            deadline: now.addingTimeInterval(60 * 60),
            prerequisiteIDs: [preparation.id]
        )

        // 前提の60分は空き時間に入らず、書く方は前提待ちなので候補がない
        #expect(recommend([preparation, writing]) == nil)
    }

    @Test
    func treatsDeletedPrerequisiteAsSatisfied() {
        let writing = TaskItem(
            title: "レポートを書く",
            estimatedMinutes: 30,
            prerequisiteIDs: [UUID()]
        )

        #expect(recommend([writing])?.task.id == writing.id)
    }

    @Test
    func prefersEarlierDeadline() {
        let later = TaskItem(
            title: "後",
            estimatedMinutes: 10,
            deadline: now.addingTimeInterval(60 * 60 * 24)
        )
        let sooner = TaskItem(
            title: "先",
            estimatedMinutes: 30,
            deadline: now.addingTimeInterval(60 * 60)
        )

        #expect(recommend([later, sooner])?.task.id == sooner.id)
    }

    @Test
    func prefersTaskWithDeadlineOverTaskWithout() {
        let noDeadline = TaskItem(title: "期限なし", estimatedMinutes: 5)
        let withDeadline = TaskItem(
            title: "期限あり",
            estimatedMinutes: 30,
            deadline: now.addingTimeInterval(60 * 60 * 24 * 7)
        )

        #expect(recommend([noDeadline, withDeadline])?.task.id == withDeadline.id)
    }

    @Test
    func prefersShorterTaskWhenDeadlinesTie() {
        let longer = TaskItem(title: "長い", estimatedMinutes: 30)
        let shorter = TaskItem(title: "短い", estimatedMinutes: 10)

        #expect(recommend([longer, shorter])?.task.id == shorter.id)
    }

    @Test
    func overdueTaskComesFirstAndReasonMentionsIt() {
        let overdue = TaskItem(
            title: "期限切れ",
            estimatedMinutes: 20,
            deadline: now.addingTimeInterval(-60 * 60)
        )
        let upcoming = TaskItem(
            title: "これから",
            estimatedMinutes: 20,
            deadline: now.addingTimeInterval(60 * 60)
        )

        let result = recommend([upcoming, overdue])

        #expect(result?.task.id == overdue.id)
        #expect(result?.factor == .earlierDeadline)
        #expect(result?.reason == "期限は過ぎていますが、所要時間20分が空き時間45分に収まるので、今なら片づけられます。")
    }

    @Test
    func reasonMentionsAvailableTime() {
        let task = TaskItem(title: "A", estimatedMinutes: 20)

        let reason = recommend([task], availableMinutes: 30)?.reason

        #expect(reason?.contains("所要時間20分") == true)
        #expect(reason?.contains("空き時間30分") == true)
    }

    // MARK: - 優先度と並び順

    @Test
    func higherPriorityWinsWhenNoDeadlineIsUrgent() {
        let mediumSoonish = TaskItem(
            title: "中・3日後",
            estimatedMinutes: 10,
            priority: .medium,
            deadline: now.addingTimeInterval(60 * 60 * 24 * 3)
        )
        let highLater = TaskItem(
            title: "高・7日後",
            estimatedMinutes: 30,
            priority: .high,
            deadline: now.addingTimeInterval(60 * 60 * 24 * 7)
        )

        let result = recommend([mediumSoonish, highLater])

        #expect(result?.task.id == highLater.id)
        #expect(result?.factor == .higherPriority)
        #expect(result?.reason == "優先度が「高」で、所要時間30分が空き時間45分に収まるからです。")
    }

    @Test
    func urgentDeadlineBeatsHigherPriority() {
        let urgentLow = TaskItem(
            title: "低・3時間後",
            estimatedMinutes: 20,
            priority: .low,
            deadline: now.addingTimeInterval(60 * 60 * 3)
        )
        let highNoDeadline = TaskItem(
            title: "高・期限なし",
            estimatedMinutes: 10,
            priority: .high
        )

        let result = recommend([highNoDeadline, urgentLow])

        #expect(result?.task.id == urgentLow.id)
        #expect(result?.factor == .urgentDeadline)
        #expect(result?.reason == "期限まであと3時間で、所要時間20分が空き時間45分に収まるからです。")
    }

    @Test
    func urgentTasksAreOrderedByDeadlineBeforePriority() {
        let highIn20Hours = TaskItem(
            title: "高・20時間後",
            estimatedMinutes: 10,
            priority: .high,
            deadline: now.addingTimeInterval(60 * 60 * 20)
        )
        let lowIn2Hours = TaskItem(
            title: "低・2時間後",
            estimatedMinutes: 10,
            priority: .low,
            deadline: now.addingTimeInterval(60 * 60 * 2)
        )

        let result = recommend([highIn20Hours, lowIn2Hours])

        #expect(result?.task.id == lowIn2Hours.id)
        #expect(result?.factor == .earlierDeadline)
    }

    @Test
    func deadlineExactly24HoursAwayIsNotUrgent() {
        let in24Hours = TaskItem(
            title: "ちょうど24時間後",
            estimatedMinutes: 10,
            priority: .low,
            deadline: now.addingTimeInterval(DecisionEngine.urgentDeadlineInterval)
        )
        let high = TaskItem(title: "高", estimatedMinutes: 10, priority: .high)

        #expect(recommend([in24Hours, high])?.task.id == high.id)
    }

    // MARK: - 理由文

    @Test
    func reasonForOnlyCandidate() {
        let task = TaskItem(title: "A", estimatedMinutes: 20)

        let result = recommend([task])

        #expect(result?.factor == .onlyCandidate)
        #expect(result?.reason == "今取りかかれるのはこのタスクだけで、所要時間20分が空き時間45分に収まるからです。")
    }

    @Test
    func reasonShowsMinutesWhenDeadlineIsWithinAnHour() {
        let urgent = TaskItem(
            title: "急ぎ",
            estimatedMinutes: 10,
            deadline: now.addingTimeInterval(60 * 40)
        )
        let other = TaskItem(title: "ほか", estimatedMinutes: 10)

        #expect(recommend([urgent, other])?.reason.hasPrefix("期限まであと40分で、") == true)
    }

    @Test
    func reasonShowsRemainingTimeForOnlyCandidateDueSoon() {
        let urgent = TaskItem(
            title: "急ぎ",
            estimatedMinutes: 30,
            deadline: now.addingTimeInterval(60 * 40)
        )

        let result = recommend([urgent])

        #expect(result?.factor == .onlyCandidate)
        #expect(result?.reason == "期限まであと40分で、所要時間30分が空き時間45分に収まるからです。")
    }

    @Test
    func reasonShowsRemainingTimeWhenBothCandidatesAreUrgent() {
        let sooner = TaskItem(
            title: "先",
            estimatedMinutes: 30,
            deadline: now.addingTimeInterval(60 * 60)
        )
        let later = TaskItem(
            title: "後",
            estimatedMinutes: 15,
            deadline: now.addingTimeInterval(60 * 60 * 23)
        )

        let result = recommend([later, sooner])

        #expect(result?.task.id == sooner.id)
        #expect(result?.factor == .earlierDeadline)
        #expect(result?.reason == "期限まであと1時間で、所要時間30分が空き時間45分に収まるからです。")
    }

    @Test
    func reasonForEarlierDeadlineWhenNotUrgent() {
        let sooner = TaskItem(
            title: "先",
            estimatedMinutes: 30,
            deadline: now.addingTimeInterval(60 * 60 * 24 * 2)
        )
        let later = TaskItem(
            title: "後",
            estimatedMinutes: 15,
            deadline: now.addingTimeInterval(60 * 60 * 24 * 5)
        )

        #expect(recommend([later, sooner])?.reason == "ほかのタスクより期限が早く、所要時間30分が空き時間45分に収まるからです。")
    }

    @Test
    func reasonWhenChosenTaskIsShorter() {
        let shorter = TaskItem(title: "短い", estimatedMinutes: 10)
        let longer = TaskItem(title: "長い", estimatedMinutes: 30)

        let result = recommend([longer, shorter])

        #expect(result?.factor == .shorter)
        #expect(result?.reason == "ほかのタスクより短く、所要時間10分が空き時間45分に収まるからです。")
    }

    @Test
    func reasonWithoutDecisiveFactorOnlyMentionsFit() {
        let a = TaskItem(title: "A", estimatedMinutes: 10)
        let b = TaskItem(title: "B", estimatedMinutes: 10)

        let result = recommend([b, a])

        #expect(result?.task.id == a.id)
        #expect(result?.factor == RecommendationFactor.none)
        #expect(result?.reason == "所要時間10分が空き時間45分に収まるからです。")
    }

    // MARK: - 推薦がないときの内訳

    private func summarize(
        _ tasks: [TaskItem],
        availableMinutes: Int = 45
    ) -> NoRecommendationSummary {
        engine.summarizeNoRecommendation(
            from: tasks,
            context: DecisionContext(
                availableMinutes: availableMinutes,
                currentDate: now
            )
        )
    }

    @Test
    func summaryCountsTooLongAndWaitingTasksSeparately() {
        let preparation = TaskItem(title: "資料を集める", estimatedMinutes: 120)
        let writing = TaskItem(
            title: "レポートを書く",
            estimatedMinutes: 30,
            prerequisiteIDs: [preparation.id]
        )
        let slides = TaskItem(title: "発表資料", estimatedMinutes: 60)
        let done = TaskItem(title: "済み", isCompleted: true, estimatedMinutes: 10)

        let summary = summarize([preparation, writing, slides, done])

        #expect(summary == NoRecommendationSummary(
            incompleteCount: 3,
            dormantCount: 0,
            waitingForPrerequisitesCount: 1,
            tooLongCount: 2,
            shortestTooLongMinutes: 60
        ))
        #expect(!summary.allCompleted)
    }

    @Test
    func summaryReportsAllCompleted() {
        let summary = summarize([
            TaskItem(title: "済み", isCompleted: true, estimatedMinutes: 10)
        ])

        #expect(summary.allCompleted)
        #expect(summary.tooLongCount == 0)
        #expect(summary.shortestTooLongMinutes == nil)
    }

    // MARK: - 冬眠

    private var fifteenDaysAgo: Date {
        now.addingTimeInterval(-60 * 60 * 24 * 15)
    }

    @Test
    func dormantTaskIsNotRecommended() {
        let dormant = TaskItem(
            title: "放置",
            estimatedMinutes: 5,
            priority: .high,
            updatedAt: fifteenDaysAgo
        )
        let active = TaskItem(title: "最近", estimatedMinutes: 30)

        #expect(recommend([dormant, active])?.task.id == active.id)
        #expect(recommend([dormant]) == nil)
    }

    @Test
    func summaryCountsDormantTasksSeparately() {
        let dormant = TaskItem(
            title: "放置",
            estimatedMinutes: 5,
            updatedAt: fifteenDaysAgo
        )

        let summary = summarize([dormant])

        #expect(summary.incompleteCount == 0)
        #expect(summary.dormantCount == 1)
        #expect(!summary.allCompleted)
    }
}
