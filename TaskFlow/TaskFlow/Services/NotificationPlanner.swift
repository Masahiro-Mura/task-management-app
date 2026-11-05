import Foundation
import UserNotifications

/// 予定する通知1件
nonisolated struct PlannedNotification: Equatable {
    let id: String
    let title: String
    let body: String
    let fireDate: Date
}

/// どの通知を、いつ出すかを決める（通知の仕組みには触れない純粋なロジック）
///
/// 方針：通知は最小限。アイコンの赤い数字は出さない。
/// - 期限が近いのに終わっていないタスクに、1回だけ
/// - 希望した人だけ、毎日1回「今の1つ」
/// - 毎日の通知が続けて開かれなければ、自動で止める
enum NotificationPlanner {

    /// 通知の識別子の接頭辞。予定し直すときに、この接頭辞のものだけを入れ替える
    nonisolated static let idPrefix = "taskflow."

    /// 期限の何時間前に知らせるか
    nonisolated static let deadlineLeadTime: TimeInterval = 60 * 60 * 3

    /// 毎日の通知が、続けて何回開かれなかったら止めるか
    nonisolated static let ignoreLimit = 3

    /// 毎日の通知のあと、この時間以内にアプリを開いたら「開かれた」とみなす
    nonisolated static let responseWindow: TimeInterval = 60 * 60 * 12

    /// 期限が近いのに終わっていないタスクへの通知。期限の3時間前に1回だけ
    static func deadlineReminders(for tasks: [TaskItem], now: Date) -> [PlannedNotification] {
        tasks.compactMap { task in
            guard !task.isCompleted, let deadline = task.deadline else {
                return nil
            }

            let fireDate = deadline.addingTimeInterval(-deadlineLeadTime)
            guard fireDate > now else {
                return nil
            }

            return PlannedNotification(
                id: idPrefix + "deadline." + task.id.uuidString,
                title: "期限が近づいています",
                body: "「\(task.title)」の期限まで、あと3時間です。\(task.estimatedMinutes)分あれば片づけられます。",
                fireDate: fireDate
            )
        }
    }

    /// 次に「今の1つ」を届ける日時（今日のその時刻が過ぎていれば明日）
    static func nextDailyFireDate(
        minutesFromMidnight: Int,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let startOfToday = calendar.startOfDay(for: now)

        guard let today = calendar.date(byAdding: .minute, value: minutesFromMidnight, to: startOfToday) else {
            return nil
        }

        return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today)
    }

    /// 毎日の「今の1つ」の通知
    static func dailyPick(taskTitle: String?, fireDate: Date) -> PlannedNotification {
        PlannedNotification(
            id: idPrefix + "daily",
            title: "今の1つ",
            body: taskTitle.map { "「\($0)」から始めませんか。開くと、そのときの空き時間に合わせて選び直します。" }
                ?? "今日の「今の1つ」を見てみませんか。",
            fireDate: fireDate
        )
    }

    /// アプリを開いたときに、毎日の通知が開かれなかった回数を数え直す
    ///
    /// - Parameters:
    ///   - lastFireDate: 最後に予定した毎日の通知の日時
    /// - Returns: 新しい回数。通知がまだ出ていなければ前のまま
    static func updatedIgnoreCount(
        previous: Int,
        lastFireDate: Date?,
        openedAt: Date
    ) -> Int {
        guard let lastFireDate, lastFireDate <= openedAt else {
            return previous
        }

        return openedAt.timeIntervalSince(lastFireDate) <= responseWindow ? 0 : previous + 1
    }
}

/// 通知を実際に予定する仕組み。テストでは記録するだけのものに差し替える
protocol NotificationScheduling: AnyObject {
    /// 通知の許可を求める（赤い数字の許可は求めない）
    func requestAuthorization() async -> Bool

    /// TaskFlow の通知を、渡したものにすべて入れ替える
    func replaceAll(with notifications: [PlannedNotification])

    /// アイコンの数字を消す
    func clearBadge()
}

/// `UNUserNotificationCenter` を使う通知
final class SystemNotificationScheduler: NotificationScheduling {

    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func replaceAll(with notifications: [PlannedNotification]) {
        center.getPendingNotificationRequests { [center] requests in
            let ours = requests.map(\.identifier).filter { $0.hasPrefix(NotificationPlanner.idPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)

            for notification in notifications {
                let content = UNMutableNotificationContent()
                content.title = notification.title
                content.body = notification.body
                content.sound = .default

                let components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: notification.fireDate
                )
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

                center.add(
                    UNNotificationRequest(identifier: notification.id, content: content, trigger: trigger)
                )
            }
        }
    }

    func clearBadge() {
        center.setBadgeCount(0)
    }
}
