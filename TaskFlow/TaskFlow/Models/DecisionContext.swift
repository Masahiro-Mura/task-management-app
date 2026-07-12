import Foundation

struct DecisionContext {
    /// 今回タスクに使える時間（分）
    var availableMinutes: Int

    /// 現在時刻
    var currentDate: Date

    init(
        availableMinutes: Int,
        currentDate: Date = Date()
    ) {
        self.availableMinutes = availableMinutes
        self.currentDate = currentDate
    }
}
