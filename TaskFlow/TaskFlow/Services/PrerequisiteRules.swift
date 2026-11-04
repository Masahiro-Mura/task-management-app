import Foundation

/// 前提タスクとして選べるものを決める
enum PrerequisiteRules {

    /// `task` の前提として選べるタスクを、一覧の順のまま返す
    ///
    /// - 自分自身は選べない
    /// - `task` を（間接的にでも）前提にしているタスクは選べない。選ぶと循環して、どちらも推薦されなくなるため
    /// - 完了済みのタスクは、すでに選ばれているものだけ残す（新しく選んでも待つ意味がないため）
    static func selectablePrerequisites(
        for task: TaskItem,
        in tasks: [TaskItem]
    ) -> [TaskItem] {

        let dependentIDs = dependents(of: task.id, in: tasks)

        return tasks.filter { candidate in
            guard candidate.id != task.id,
                  !dependentIDs.contains(candidate.id) else {
                return false
            }

            return !candidate.isCompleted || task.prerequisiteIDs.contains(candidate.id)
        }
    }

    /// `taskID` を直接・間接に前提にしているタスクのID
    static func dependents(
        of taskID: UUID,
        in tasks: [TaskItem]
    ) -> Set<UUID> {

        var result: Set<UUID> = []
        var queue: [UUID] = [taskID]

        while let current = queue.popLast() {
            for task in tasks where task.prerequisiteIDs.contains(current) {
                if result.insert(task.id).inserted {
                    queue.append(task.id)
                }
            }
        }

        return result
    }
}
