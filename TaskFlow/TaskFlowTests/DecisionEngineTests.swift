import Foundation
import Testing
@testable import TaskFlow

struct DecisionEngineTests {

    private let engine = DecisionEngine()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

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
        #expect(result?.reason.contains("期限を過ぎている") == true)
    }

    @Test
    func reasonMentionsAvailableTime() {
        let task = TaskItem(title: "A", estimatedMinutes: 20)

        let reason = recommend([task], availableMinutes: 30)?.reason

        #expect(reason?.contains("所要時間20分") == true)
        #expect(reason?.contains("空き時間30分") == true)
    }
}
