import Foundation

/// 推薦の決め手。次点の候補と比べて、何がこのタスクを選ばせたか
enum RecommendationFactor: Equatable {
    /// 実行できる候補がこのタスクだけ
    case onlyCandidate
    /// 期限が24時間以内（期限切れを含む）
    case urgentDeadline
    /// 次点より期限が早い
    case earlierDeadline
    /// 次点には期限がなく、このタスクにはある
    case hasDeadline
    /// 次点より優先度が高い
    case higherPriority
    /// 次点より所要時間が短い
    case shorter
    /// 「今日やりたい」の印が付いている
    case pinnedToday
    /// 気が乗らないときに、軽い作業の印が付いている
    case lighter
    /// 条件が並んでいて決め手がない
    case none
}

/// Decision Engineが返す推薦結果
struct TaskRecommendation {
    let task: TaskItem
    let factor: RecommendationFactor
    let reason: String
}

/// 推薦できるタスクがないときの内訳
struct NoRecommendationSummary: Equatable {
    /// 未完了のタスク数（冬眠中を除く）
    var incompleteCount: Int

    /// 冬眠中のタスク数
    var dormantCount: Int

    /// 前提タスクの完了待ちの件数
    var waitingForPrerequisitesCount: Int

    /// 前提は満たしているが、空き時間に収まらない件数
    var tooLongCount: Int

    /// 空き時間に収まらないタスクのうち、最も短い所要時間（分）
    var shortestTooLongMinutes: Int?

    /// 「今はやらない」で一時的に外しているタスク数
    var skippedCount: Int = 0

    /// 予定日が明日以降のタスク数
    var scheduledLaterCount: Int = 0

    /// 空き時間に収まらないタスクのうち、最も短いもの。「最初の一歩」「5分だけ」の対象にする
    var shortestTooLongTaskID: UUID? = nil

    var allCompleted: Bool {
        incompleteCount == 0 && dormantCount == 0
    }
}

/// 現在の状況に応じて、次に行うタスクを1件選択する
struct DecisionEngine {

    /// この時間以内に期限が来るタスクは、優先度より期限を優先する
    static let urgentDeadlineInterval: TimeInterval = 60 * 60 * 24

    /// タスク一覧から、現在実行すべきタスクを1件推薦する
    ///
    /// 並び順は「期限が24時間以内のもの（同士は期限が早い順）→（気が乗らないときは軽い作業）→ 今日やりたい → 優先度 → 期限 → 所要時間の短さ」。
    /// 気が乗らないとき（`prefersLight`）は、軽いか短い作業だけを候補にする。
    ///
    /// - Parameters:
    ///   - tasks: 判断対象となる全タスク
    ///   - context: 現在時刻や利用可能時間などの状況
    /// - Returns: 推薦タスクと推薦理由。候補がない場合はnil
    func recommend(
        from tasks: [TaskItem],
        context: DecisionContext
    ) -> TaskRecommendation? {

        let incompleteTaskIDs = incompleteTaskIDs(in: tasks)

        let candidates = tasks
            .filter { !$0.isDormant(at: context.currentDate) }
            .filter { !context.skippedTaskIDs.contains($0.id) }
            .filter { !context.isScheduledLater($0) }
            .filter { !context.prefersLight || $0.isEasyToStart }
            .filter { task in
                isExecutable(
                    task,
                    incompleteTaskIDs: incompleteTaskIDs,
                    availableMinutes: context.availableMinutes
                )
            }
            .sorted { lhs, rhs in
                if let comparison = compare(lhs, rhs, context: context) {
                    return comparison.lhsComesFirst
                }

                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }

        guard let recommendedTask = candidates.first else {
            return nil
        }

        let factor: RecommendationFactor
        if candidates.count == 1 {
            factor = .onlyCandidate
        } else {
            factor = compare(
                recommendedTask,
                candidates[1],
                context: context
            )?.factor ?? .none
        }

        return TaskRecommendation(
            task: recommendedTask,
            factor: factor,
            reason: makeReason(
                for: recommendedTask,
                factor: factor,
                context: context
            )
        )
    }

    /// 推薦できるタスクがないときに、その内訳をまとめる
    ///
    /// `recommend(from:context:)` が nil を返したときに使う。
    func summarizeNoRecommendation(
        from tasks: [TaskItem],
        context: DecisionContext
    ) -> NoRecommendationSummary {

        let incompleteTaskIDs = incompleteTaskIDs(in: tasks)

        var activeTasks: [TaskItem] = []
        var dormantCount = 0

        for task in tasks where !task.isCompleted {
            if task.isDormant(at: context.currentDate) {
                dormantCount += 1
            } else {
                activeTasks.append(task)
            }
        }

        var skippedCount = 0
        var scheduledLaterCount = 0
        var waitingCount = 0
        var tooLongMinutes: [Int] = []
        var shortestTooLong: TaskItem?

        for task in activeTasks {
            if context.skippedTaskIDs.contains(task.id) {
                skippedCount += 1
            } else if context.isScheduledLater(task) {
                scheduledLaterCount += 1
            } else if !prerequisitesAreCompleted(task, incompleteTaskIDs: incompleteTaskIDs) {
                waitingCount += 1
            } else if task.estimatedMinutes > context.availableMinutes {
                tooLongMinutes.append(task.estimatedMinutes)

                if task.estimatedMinutes < (shortestTooLong?.estimatedMinutes ?? .max) {
                    shortestTooLong = task
                }
            }
        }

        return NoRecommendationSummary(
            incompleteCount: activeTasks.count,
            dormantCount: dormantCount,
            waitingForPrerequisitesCount: waitingCount,
            tooLongCount: tooLongMinutes.count,
            shortestTooLongMinutes: tooLongMinutes.min(),
            skippedCount: skippedCount,
            scheduledLaterCount: scheduledLaterCount,
            shortestTooLongTaskID: shortestTooLong?.id
        )
    }

    /// 未完了のタスクだけが前提として待つ対象になる。
    /// 完了済みや、削除されて一覧に存在しない前提は満たされているとみなす
    private func incompleteTaskIDs(in tasks: [TaskItem]) -> Set<UUID> {
        Set(
            tasks
                .filter { !$0.isCompleted }
                .map(\.id)
        )
    }

    private func prerequisitesAreCompleted(
        _ task: TaskItem,
        incompleteTaskIDs: Set<UUID>
    ) -> Bool {
        task.prerequisiteIDs.allSatisfy {
            !incompleteTaskIDs.contains($0)
        }
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

        return prerequisitesAreCompleted(task, incompleteTaskIDs: incompleteTaskIDs)
    }

    private func isUrgent(_ task: TaskItem, now: Date) -> Bool {
        guard let deadline = task.deadline else {
            return false
        }

        return deadline < now.addingTimeInterval(Self.urgentDeadlineInterval)
    }

    /// タスク同士の順序と、その決め手を返す。タイトル以外がすべて並ぶ場合はnil
    private func compare(
        _ lhs: TaskItem,
        _ rhs: TaskItem,
        context: DecisionContext
    ) -> (lhsComesFirst: Bool, factor: RecommendationFactor)? {

        let now = context.currentDate
        let lhsIsUrgent = isUrgent(lhs, now: now)
        let rhsIsUrgent = isUrgent(rhs, now: now)

        if lhsIsUrgent != rhsIsUrgent {
            return (lhsIsUrgent, .urgentDeadline)
        }

        // 急ぎのもの同士は、優先度より締め切りの近さを優先する
        if lhsIsUrgent,
           let lhsDeadline = lhs.deadline,
           let rhsDeadline = rhs.deadline,
           lhsDeadline != rhsDeadline {
            return (lhsDeadline < rhsDeadline, .earlierDeadline)
        }

        if context.prefersLight, lhs.isLight != rhs.isLight {
            return (lhs.isLight, .lighter)
        }

        let lhsIsPinned = lhs.isPinnedForToday(at: now, calendar: context.calendar, dayStartOffset: context.dayStartOffset)
        let rhsIsPinned = rhs.isPinnedForToday(at: now, calendar: context.calendar, dayStartOffset: context.dayStartOffset)

        if lhsIsPinned != rhsIsPinned {
            return (lhsIsPinned, .pinnedToday)
        }

        if lhs.priority != rhs.priority {
            return (lhs.priority.rawValue > rhs.priority.rawValue, .higherPriority)
        }

        switch (lhs.deadline, rhs.deadline) {
        case let (lhsDeadline?, rhsDeadline?) where lhsDeadline != rhsDeadline:
            return (lhsDeadline < rhsDeadline, .earlierDeadline)

        case (_?, nil):
            return (true, .hasDeadline)

        case (nil, _?):
            return (false, .hasDeadline)

        default:
            break
        }

        if lhs.estimatedMinutes != rhs.estimatedMinutes {
            return (lhs.estimatedMinutes < rhs.estimatedMinutes, .shorter)
        }

        return nil
    }

    /// 推薦理由を生成する。決め手を1つと、空き時間に収まることを伝える
    private func makeReason(
        for task: TaskItem,
        factor: RecommendationFactor,
        context: DecisionContext
    ) -> String {

        // 期限切れは責めず、今なら片づけられることを伝える
        if let deadline = task.deadline, deadline <= context.currentDate {
            return "期限は過ぎていますが、所要時間\(task.estimatedMinutes)分が空き時間\(context.availableMinutes)分に収まるので、今なら片づけられます。"
        }

        let fit = "所要時間\(task.estimatedMinutes)分が空き時間\(context.availableMinutes)分に収まるからです。"

        guard let lead = leadPhrase(
            for: task,
            factor: factor,
            context: context
        ) else {
            return fit
        }

        return lead + "、" + fit
    }

    private func leadPhrase(
        for task: TaskItem,
        factor: RecommendationFactor,
        context: DecisionContext
    ) -> String? {

        let now = context.currentDate

        // 期限が24時間以内なら、決め手が何であっても残り時間を一番に伝える
        if isUrgent(task, now: now), let deadline = task.deadline {
            return remainingTimePhrase(until: deadline, now: now)
        }

        // 気が乗らないときは、軽さ・短さを一番に伝える
        if context.prefersLight {
            return task.isLight
                ? "頭を使わずにできる軽い作業で"
                : "\(task.estimatedMinutes)分で終わる短い作業で"
        }

        switch factor {
        case .onlyCandidate:
            return "今取りかかれるのはこのタスクだけで"

        case .urgentDeadline:
            // 急ぎのタスクは上で処理済み
            return nil

        case .earlierDeadline:
            return "ほかのタスクより期限が早く"

        case .hasDeadline:
            return "期限が決まっていて"

        case .higherPriority:
            return "優先度が「\(task.priority.displayName)」で"

        case .shorter:
            return "ほかのタスクより短く"

        case .pinnedToday:
            return "今日やりたいと決めていて"

        case .lighter:
            return "頭を使わずにできる軽い作業で"

        case .none:
            return nil
        }
    }

    private func remainingTimePhrase(until deadline: Date, now: Date) -> String {
        // 期限切れは makeReason で別の文にしているので、ここでは残り時間が正の場合だけを扱う
        let remaining = max(deadline.timeIntervalSince(now), 0)

        let minutes = Int((remaining / 60).rounded(.up))
        if minutes < 60 {
            return "期限まであと\(minutes)分で"
        }

        let hours = Int((remaining / 3600).rounded(.up))
        return "期限まであと\(hours)時間で"
    }
}
