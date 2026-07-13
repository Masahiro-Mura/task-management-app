import Foundation
import Combine

@MainActor
final class HomeViewModel: ObservableObject {

    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var recommendation: TaskRecommendation?

    private let decisionEngine = DecisionEngine()

    private let availableMinutes = 45
    
    var todayTasks: [TaskItem] {
        tasks.filter { task in
            guard let scheduledDate = task.scheduledDate else {
                return false
            }

            return Calendar.current.isDateInToday(scheduledDate)
        }
    }

    var tomorrowTasks: [TaskItem] {
        tasks.filter { task in
            guard let scheduledDate = task.scheduledDate else {
                return false
            }

            return Calendar.current.isDateInTomorrow(scheduledDate)
        }
    }

    var allTasks: [TaskItem] {
        tasks
    }

    init() {
        loadSampleTasks()
        updateRecommendation()
    }

    /// 新しいタスクを追加する
    func addTask(
        title: String,
        estimatedMinutes: Int,
        scheduledDate: Date?,
        deadline: Date?
    ) {
        let task = TaskItem(
            title: title,
            estimatedMinutes: estimatedMinutes,
            scheduledDate: scheduledDate,
            deadline: deadline
        )

        tasks.append(task)
        updateRecommendation()
    }
    
    /// タスクの完了状態を切り替える
    func toggleCompletion(for task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else {
            return
        }

        tasks[index].isCompleted.toggle()
        updateRecommendation()
    }

    /// 現在のタスク一覧から推薦を再計算する
    func updateRecommendation() {
        let context = DecisionContext(
            availableMinutes: availableMinutes,
            currentDate: Date()
        )

        recommendation = decisionEngine.recommend(
            from: tasks,
            context: context
        )
    }

    /// 開発中の動作確認用サンプルデータ
    private func loadSampleTasks() {
        let now = Date()

        let preparationTask = TaskItem(
            title: "開発環境を確認する",
            isCompleted: true,
            estimatedMinutes: 10
        )

        let implementationTask = TaskItem(
            title: "TaskFlowの画面を実装する",
            estimatedMinutes: 30,
            scheduledDate: now,
            deadline: now.addingTimeInterval(60 * 60),
            prerequisiteIDs: [preparationTask.id]
        )

        let documentTask = TaskItem(
            title: "READMEを整理する",
            estimatedMinutes: 15,
            deadline: now.addingTimeInterval(60 * 60 * 24)
        )

        tasks = [
            preparationTask,
            implementationTask,
            documentTask
        ]
    }
}
