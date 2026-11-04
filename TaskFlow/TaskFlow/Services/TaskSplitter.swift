import Foundation

/// 分けたあとの1つ分
struct TaskSplitPart: Equatable {
    var title: String
    var estimatedMinutes: Int
}

/// 大きいタスクを、順番につながった小さいタスクに分ける
enum TaskSplitter {

    static let partCountRange = 2...5

    /// 分け方の初期値。所要時間を等分し、5分単位に切り上げる
    static func defaultParts(
        for task: TaskItem,
        count: Int
    ) -> [TaskSplitPart] {

        let count = min(max(count, partCountRange.lowerBound), partCountRange.upperBound)
        let share = Double(task.estimatedMinutes) / Double(count)
        let minutes = max(5, Int((share / 5).rounded(.up)) * 5)

        return (1...count).map { index in
            TaskSplitPart(
                title: "\(task.title)（\(index)/\(count)）",
                estimatedMinutes: minutes
            )
        }
    }

    /// `task` を `parts` に置き換えた、新しいタスク一覧を返す
    ///
    /// - 分けたタスクは1つ目から順に、前のものを前提としてつながる
    /// - 1つ目は元のタスクの前提を引き継ぐ
    /// - 元のタスクを前提にしていたタスクは、最後の1つを前提にする
    /// - 優先度・予定日・期限は、すべての部分に引き継ぐ
    /// - 部分は元のタスクがあった位置に並ぶ
    ///
    /// `parts` が2つ未満のとき、または `task` が一覧にないときは、一覧をそのまま返す。
    static func split(
        _ task: TaskItem,
        into parts: [TaskSplitPart],
        in tasks: [TaskItem],
        now: Date
    ) -> [TaskItem] {

        guard parts.count >= partCountRange.lowerBound,
              let index = tasks.firstIndex(where: { $0.id == task.id }) else {
            return tasks
        }

        var newParts: [TaskItem] = []

        for part in parts {
            let previousID = newParts.last?.id

            newParts.append(
                TaskItem(
                    title: part.title,
                    estimatedMinutes: part.estimatedMinutes,
                    priority: task.priority,
                    scheduledDate: task.scheduledDate,
                    deadline: task.deadline,
                    prerequisiteIDs: previousID.map { [$0] } ?? task.prerequisiteIDs,
                    updatedAt: now
                )
            )
        }

        guard let lastPartID = newParts.last?.id else {
            return tasks
        }

        var result = tasks
        result.replaceSubrange(index...index, with: newParts)

        for resultIndex in result.indices {
            result[resultIndex].prerequisiteIDs = result[resultIndex].prerequisiteIDs.map {
                $0 == task.id ? lastPartID : $0
            }
        }

        return result
    }
}
