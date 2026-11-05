import Foundation

/// 選んだタスクの日付をまとめて変える（UIや保存に触れない純粋なロジック）
enum TaskRescheduler {

    enum Option: CaseIterable {
        case today
        case tomorrow
        case nextMonday
        case clearDates
        case hibernate

        var title: String {
            switch self {
            case .today:
                return "今日に"
            case .tomorrow:
                return "明日に"
            case .nextMonday:
                return "来週月曜に"
            case .clearDates:
                return "日付を外す（いつかやる）"
            case .hibernate:
                return "冬眠させる"
            }
        }
    }

    /// - 今日／明日／来週月曜：予定日をその日にする。期限がその日より前なら、期限も同じ時刻のままその日に移す
    /// - 日付を外す：予定日・期限・今日やりたいを外す
    /// - 冬眠させる：日付を外し、すぐ冬眠に入るようにする
    ///
    /// - Parameter startOfToday: 「今日」の始まり（1日の区切りの設定を反映したもの）
    static func reschedule(
        _ taskIDs: Set<UUID>,
        to option: Option,
        in tasks: inout [TaskItem],
        now: Date,
        startOfToday: Date,
        calendar: Calendar
    ) {
        let targetDay: Date?
        switch option {
        case .today:
            targetDay = startOfToday
        case .tomorrow:
            targetDay = calendar.date(byAdding: .day, value: 1, to: startOfToday)
        case .nextMonday:
            // 月=0 … 日=6 として、次の週の月曜
            let mondayBased = (calendar.component(.weekday, from: startOfToday) + 5) % 7
            targetDay = calendar.date(byAdding: .day, value: 7 - mondayBased, to: startOfToday)
        case .clearDates, .hibernate:
            targetDay = nil
        }

        for index in tasks.indices where taskIDs.contains(tasks[index].id) && !tasks[index].isCompleted {
            if let targetDay {
                tasks[index].scheduledDate = targetDay

                if let deadline = tasks[index].deadline, deadline < targetDay {
                    let time = calendar.dateComponents([.hour, .minute, .second], from: deadline)
                    tasks[index].deadline = calendar.date(
                        bySettingHour: time.hour ?? 23,
                        minute: time.minute ?? 59,
                        second: time.second ?? 59,
                        of: targetDay
                    )
                }

                tasks[index].updatedAt = now
            } else {
                tasks[index].scheduledDate = nil
                tasks[index].deadline = nil
                tasks[index].pinnedForTodayAt = nil

                // 冬眠は「14日触っていない」で判定しているので、その日時まで戻す
                tasks[index].updatedAt = option == .hibernate
                    ? now.addingTimeInterval(-TaskItem.dormancyInterval)
                    : now
            }
        }
    }
}
