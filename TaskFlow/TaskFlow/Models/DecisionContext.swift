import Foundation

struct DecisionContext {
    /// 今回タスクに使える時間（分）
    var availableMinutes: Int

    /// 現在時刻
    var currentDate: Date

    /// 「今はやらない」で一時的に推薦から外しているタスクのID
    var skippedTaskIDs: Set<UUID>

    /// 「明日以降の予定」の判定に使う暦
    var calendar: Calendar

    /// 気が乗らないので、軽い・短い作業だけを推薦してほしいか
    var prefersLight: Bool

    /// 1日の区切り（0時からずらす秒数）。4時区切りなら 4 * 60 * 60
    var dayStartOffset: TimeInterval

    init(
        availableMinutes: Int,
        currentDate: Date = Date(),
        skippedTaskIDs: Set<UUID> = [],
        calendar: Calendar = .current,
        prefersLight: Bool = false,
        dayStartOffset: TimeInterval = 0
    ) {
        self.availableMinutes = availableMinutes
        self.currentDate = currentDate
        self.skippedTaskIDs = skippedTaskIDs
        self.calendar = calendar
        self.prefersLight = prefersLight
        self.dayStartOffset = dayStartOffset
    }

    /// 1日の区切りを反映した「今日」（その日の 0時）
    var logicalToday: Date {
        calendar.startOfDay(for: currentDate.addingTimeInterval(-dayStartOffset))
    }

    /// 予定日が明日以降なら、その日まで推薦しない
    func isScheduledLater(_ task: TaskItem) -> Bool {
        guard let scheduledDate = task.scheduledDate,
              let startOfTomorrow = calendar.date(
                  byAdding: .day,
                  value: 1,
                  to: logicalToday
              ) else {
            return false
        }

        return scheduledDate >= startOfTomorrow
    }
}
