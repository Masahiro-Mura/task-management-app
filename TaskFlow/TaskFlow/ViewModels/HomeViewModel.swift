import Foundation
import Combine

@MainActor
final class HomeViewModel: ObservableObject {

    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var recommendation: TaskRecommendation?

    private let decisionEngine = DecisionEngine()
    private let userDefaults: UserDefaults
    private let tasksStorageKey = "taskFlow.tasks"

    /// 読み込めなかった保存データの退避先キーの接頭辞
    static let unreadableTasksKeyPrefix = "taskFlow.tasks.unreadable."

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

    /// - Parameters:
    ///   - userDefaults: タスクの保存先。テストでは専用のスイートを渡す
    ///   - seedsSampleTasks: 保存データがないときにサンプルタスクを入れるか
    init(
        userDefaults: UserDefaults = .standard,
        seedsSampleTasks: Bool = HomeViewModel.seedsSampleTasksByDefault
    ) {
        self.userDefaults = userDefaults

        switch loadTasks() {
        case .loaded(let savedTasks):
            tasks = savedTasks

        case .notFound:
            if seedsSampleTasks {
                loadSampleTasks()
            }

        case .unreadable(let data):
            // 次の保存で上書きされて失われないよう、元のデータを退避しておく
            backUpUnreadableTasks(data)
        }

        updateRecommendation()
    }

    /// サンプルタスクは開発中のビルドでのみ入れる
    nonisolated static var seedsSampleTasksByDefault: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// 新しいタスクを追加する
    func addTask(
        title: String,
        estimatedMinutes: Int,
        priority: TaskPriority,
        scheduledDate: Date?,
        deadline: Date?
    ) {
        let task = TaskItem(
            title: title,
            estimatedMinutes: estimatedMinutes,
            priority: priority,
            scheduledDate: scheduledDate,
            deadline: deadline
        )

        tasks.append(task)
        saveTasks()
        updateRecommendation()
    }
    
    /// タスクの完了状態を切り替える
    func toggleCompletion(for task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else {
            return
        }

        tasks[index].isCompleted.toggle()
        saveTasks()
        updateRecommendation()
    }
    
    /// 指定したタスクを削除する
    func deleteTask(_ task: TaskItem) {
        tasks.removeAll { $0.id == task.id }

        // 削除したタスクを前提にしていたタスクが、推薦されないまま残らないようにする
        for index in tasks.indices {
            tasks[index].prerequisiteIDs.removeAll { $0 == task.id }
        }

        saveTasks()
        updateRecommendation()
    }
    
    /// 既存タスクの内容を更新する
    func updateTask(_ updatedTask: TaskItem) {
        guard let index = tasks.firstIndex(
            where: { $0.id == updatedTask.id }
        ) else {
            return
        }

        tasks[index] = updatedTask
        saveTasks()
        updateRecommendation()
    }
    
    /// 現在のタスク一覧をUserDefaultsへ保存する
    private func saveTasks() {
        guard let data = try? JSONEncoder().encode(tasks) else {
            return
        }

        userDefaults.set(data, forKey: tasksStorageKey)
    }

    private enum LoadResult {
        case loaded([TaskItem])
        case notFound
        case unreadable(Data)
    }

    /// UserDefaultsから保存済みのタスク一覧を読み込む
    private func loadTasks() -> LoadResult {
        guard let data = userDefaults.data(
            forKey: tasksStorageKey
        ) else {
            return .notFound
        }

        guard let savedTasks = try? JSONDecoder().decode(
            [TaskItem].self,
            from: data
        ) else {
            return .unreadable(data)
        }

        return .loaded(savedTasks)
    }

    /// 読み込めなかった保存データを、日時つきの別キーへ退避する
    private func backUpUnreadableTasks(_ data: Data) {
        let timestamp = ISO8601DateFormatter().string(from: Date())

        userDefaults.set(
            data,
            forKey: Self.unreadableTasksKeyPrefix + timestamp
        )

        // 起動のたびに同じデータを退避し直さないよう、元のキーは空にする
        userDefaults.removeObject(forKey: tasksStorageKey)
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
