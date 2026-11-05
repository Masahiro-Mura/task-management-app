import Foundation

struct DecisionContext {
    /// 今回タスクに使える時間（分）
    var availableMinutes: Int

    /// 現在時刻
    var currentDate: Date

    /// 「今はやらない」で一時的に推薦から外しているタスクのID
    var skippedTaskIDs: Set<UUID>

    init(
        availableMinutes: Int,
        currentDate: Date = Date(),
        skippedTaskIDs: Set<UUID> = []
    ) {
        self.availableMinutes = availableMinutes
        self.currentDate = currentDate
        self.skippedTaskIDs = skippedTaskIDs
    }
}
