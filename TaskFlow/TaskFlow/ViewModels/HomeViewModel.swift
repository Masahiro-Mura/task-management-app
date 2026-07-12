import Foundation
import Combine

@MainActor
final class HomeViewModel: ObservableObject {

    @Published private(set) var recommendation: TaskRecommendation?

    private let decisionEngine = DecisionEngine()

    func loadRecommendation() {
        let now = Date()

        let preparationTask = TaskItem(
            title: "開発環境を確認する",
            isCompleted: true,
            estimatedMinutes: 10
        )

        let implementationTask = TaskItem(
            title: "TaskFlowの画面を実装する",
            estimatedMinutes: 30,
            deadline: now.addingTimeInterval(60 * 60),
            prerequisiteIDs: [preparationTask.id]
        )

        let documentTask = TaskItem(
            title: "READMEを整理する",
            estimatedMinutes: 15,
            deadline: now.addingTimeInterval(60 * 60 * 24)
        )

        let tasks = [
            preparationTask,
            implementationTask,
            documentTask
        ]

        let context = DecisionContext(
            availableMinutes: 45,
            currentDate: now
        )

        recommendation = decisionEngine.recommend(
            from: tasks,
            context: context
        )
    }
}
