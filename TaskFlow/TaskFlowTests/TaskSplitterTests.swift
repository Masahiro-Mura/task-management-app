import Foundation
import Testing
@testable import TaskFlow

@MainActor
struct TaskSplitterTests {

    private let now = Date()

    // MARK: - 初期の分け方

    @Test
    func defaultPartsSplitEvenlyRoundedUpTo5Minutes() {
        let task = TaskItem(title: "発表資料を作る", estimatedMinutes: 100)

        let parts = TaskSplitter.defaultParts(for: task, count: 3)

        #expect(parts == [
            TaskSplitPart(title: "発表資料を作る（1/3）", estimatedMinutes: 35),
            TaskSplitPart(title: "発表資料を作る（2/3）", estimatedMinutes: 35),
            TaskSplitPart(title: "発表資料を作る（3/3）", estimatedMinutes: 35)
        ])
    }

    @Test
    func defaultPartsClampCountAndKeepAtLeast5Minutes() {
        let task = TaskItem(title: "短い", estimatedMinutes: 5)

        #expect(TaskSplitter.defaultParts(for: task, count: 1).count == 2)
        #expect(TaskSplitter.defaultParts(for: task, count: 9).count == 5)
        #expect(TaskSplitter.defaultParts(for: task, count: 2).allSatisfy { $0.estimatedMinutes == 5 })
    }

    // MARK: - 分ける

    @Test
    func splitReplacesTaskWithChainInPlace() throws {
        let preparation = TaskItem(title: "資料を集める", estimatedMinutes: 20)
        let big = TaskItem(
            title: "発表資料を作る",
            estimatedMinutes: 90,
            priority: .high,
            scheduledDate: now,
            deadline: now.addingTimeInterval(60 * 60 * 24 * 3),
            prerequisiteIDs: [preparation.id]
        )
        let rehearsal = TaskItem(
            title: "リハーサル",
            estimatedMinutes: 30,
            prerequisiteIDs: [big.id]
        )

        let result = TaskSplitter.split(
            big,
            into: TaskSplitter.defaultParts(for: big, count: 3),
            in: [preparation, big, rehearsal],
            now: now
        )

        #expect(result.count == 5)
        #expect(!result.contains { $0.id == big.id })
        #expect(result.first?.id == preparation.id)
        #expect(result.last?.id == rehearsal.id)

        let parts = Array(result[1...3])

        // 1つ目は元の前提を引き継ぎ、以降は前のものを前提にする
        #expect(parts[0].prerequisiteIDs == [preparation.id])
        #expect(parts[1].prerequisiteIDs == [parts[0].id])
        #expect(parts[2].prerequisiteIDs == [parts[1].id])

        // 元のタスクを前提にしていたものは、最後の1つを前提にする
        let lastPart = try #require(parts.last)
        #expect(result.last?.prerequisiteIDs == [lastPart.id])

        for part in parts {
            #expect(part.priority == .high)
            #expect(part.scheduledDate == big.scheduledDate)
            #expect(part.deadline == big.deadline)
            #expect(part.updatedAt == now)
            #expect(!part.isCompleted)
        }
    }

    @Test
    func splitWithFewerThanTwoPartsChangesNothing() {
        let task = TaskItem(title: "A", estimatedMinutes: 60)

        let result = TaskSplitter.split(
            task,
            into: [TaskSplitPart(title: "A", estimatedMinutes: 60)],
            in: [task],
            now: now
        )

        #expect(result == [task])
    }

    // MARK: - ロードマップの完了条件

    @Test
    func splitting90MinutesIntoThreeMakesFirstPartRecommendableIn45Minutes() throws {
        let storage = TemporaryUserDefaults(prefix: "TaskSplitterTests")
        let viewModel = HomeViewModel(
            userDefaults: storage.userDefaults,
            seedsSampleTasks: false
        )

        viewModel.addTask(
            title: "発表資料を作る",
            estimatedMinutes: 90,
            priority: .medium,
            scheduledDate: nil,
            deadline: nil
        )
        let big = try #require(viewModel.tasks.first)

        #expect(viewModel.availableMinutes == 45)
        #expect(viewModel.recommendation == nil)

        viewModel.splitTask(big, into: TaskSplitter.defaultParts(for: big, count: 3))

        #expect(viewModel.tasks.count == 3)
        #expect(viewModel.recommendation?.task.title == "発表資料を作る（1/3）")
        #expect(viewModel.recommendation?.task.estimatedMinutes == 30)
    }
}
