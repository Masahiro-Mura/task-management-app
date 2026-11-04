import Foundation

/// Decision Engineが返す推薦結果
struct TaskRecommendation {
    let task: TaskItem
    let reason: String
}

/// 現在の状況に応じて、次に行うタスクを1件選択する
struct DecisionEngine {

    /// タスク一覧から、現在実行すべきタスクを1件推薦する
    ///
    /// - Parameters:
    ///   - tasks: 判断対象となる全タスク
    ///   - context: 現在時刻や利用可能時間などの状況
    /// - Returns: 推薦タスクと推薦理由。候補がない場合はnil
    func recommend(
        from tasks: [TaskItem],
        context: DecisionContext
    ) -> TaskRecommendation? {

        // 未完了のタスクだけが前提として待つ対象になる。
        // 完了済みや、削除されて一覧に存在しない前提は満たされているとみなす
        let incompleteTaskIDs = Set(
            tasks
                .filter { !$0.isCompleted }
                .map(\.id)
        )

        let executableTasks = tasks.filter { task in
            isExecutable(
                task,
                incompleteTaskIDs: incompleteTaskIDs,
                availableMinutes: context.availableMinutes
            )
        }

        guard let recommendedTask = executableTasks.sorted(
            by: taskHasHigherPriority
        ).first else {
            return nil
        }

        return TaskRecommendation(
            task: recommendedTask,
            reason: makeReason(
                for: recommendedTask,
                context: context
            )
        )
    }

    /// タスクが現在実行可能か判定する
    private func isExecutable(
        _ task: TaskItem,
        incompleteTaskIDs: Set<UUID>,
        availableMinutes: Int
    ) -> Bool {

        guard !task.isCompleted else {
            return false
        }

        guard task.estimatedMinutes <= availableMinutes else {
            return false
        }

        let prerequisitesAreCompleted = task.prerequisiteIDs.allSatisfy {
            !incompleteTaskIDs.contains($0)
        }

        return prerequisitesAreCompleted
    }

    /// タスク同士の優先順位を比較する
    private func taskHasHigherPriority(
        _ lhs: TaskItem,
        _ rhs: TaskItem
    ) -> Bool {

        switch (lhs.deadline, rhs.deadline) {
        case let (lhsDeadline?, rhsDeadline?):
            if lhsDeadline != rhsDeadline {
                return lhsDeadline < rhsDeadline
            }

        case (_?, nil):
            return true

        case (nil, _?):
            return false

        case (nil, nil):
            break
        }

        if lhs.estimatedMinutes != rhs.estimatedMinutes {
            return lhs.estimatedMinutes < rhs.estimatedMinutes
        }

        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    /// 推薦理由を生成する
    private func makeReason(
        for task: TaskItem,
        context: DecisionContext
    ) -> String {

        var reasons: [String] = []

        if let deadline = task.deadline {
            if deadline < context.currentDate {
                reasons.append("期限を過ぎている")
            } else {
                reasons.append("期限が設定されている")
            }
        }

        reasons.append(
            "所要時間\(task.estimatedMinutes)分が、現在の空き時間\(context.availableMinutes)分以内である"
        )

        if task.prerequisiteIDs.isEmpty {
            reasons.append("前提タスクがない")
        } else {
            reasons.append("すべての前提タスクが完了している")
        }

        return reasons.joined(separator: "ため、") + "ためです。"
    }
}
