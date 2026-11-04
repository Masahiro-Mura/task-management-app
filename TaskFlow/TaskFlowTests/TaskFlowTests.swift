import Foundation
import Testing
@testable import TaskFlow

@MainActor
struct TaskFlowTests {

    @Test
    func recommendsEarliestExecutableTask() {
        let now = Date()

        let completedPreparation = TaskItem(
            title: "資料を準備する",
            isCompleted: true,
            estimatedMinutes: 10
        )

        let recommendedTask = TaskItem(
            title: "レポートを書く",
            estimatedMinutes: 30,
            deadline: now.addingTimeInterval(60 * 60),
            prerequisiteIDs: [completedPreparation.id]
        )

        let laterTask = TaskItem(
            title: "メールを整理する",
            estimatedMinutes: 15,
            deadline: now.addingTimeInterval(60 * 60 * 24)
        )

        let tooLongTask = TaskItem(
            title: "発表資料を作る",
            estimatedMinutes: 90,
            deadline: now.addingTimeInterval(60 * 30)
        )

        let engine = DecisionEngine()
        let context = DecisionContext(
            availableMinutes: 45,
            currentDate: now
        )

        let result = engine.recommend(
            from: [
                completedPreparation,
                recommendedTask,
                laterTask,
                tooLongTask
            ],
            context: context
        )

        #expect(result?.task.id == recommendedTask.id)
    }

    @Test
    func priorityIsPreservedThroughEncoding() throws {
        let task = TaskItem(
            title: "レポートを書く",
            estimatedMinutes: 30,
            priority: .high
        )

        let data = try JSONEncoder().encode(task)
        let decoded = try JSONDecoder().decode(TaskItem.self, from: data)

        #expect(decoded == task)
        #expect(decoded.priority == .high)
    }

    @Test
    func legacyTaskWithoutPriorityDecodesAsMedium() throws {
        // priority 追加前に保存されたデータ
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "title": "メールを整理する",
            "isCompleted": false,
            "estimatedMinutes": 15,
            "prerequisiteIDs": []
        }
        """

        let decoded = try JSONDecoder().decode(
            TaskItem.self,
            from: Data(json.utf8)
        )

        #expect(decoded.priority == .medium)
    }
}
