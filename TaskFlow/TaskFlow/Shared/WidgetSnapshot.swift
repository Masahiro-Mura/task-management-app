import Foundation

/// ウィジェットに出す「今の1つ」の写し
///
/// ウィジェットは推薦を計算しない。アプリが推薦を出し直すたびに、この写しを App Group に書く。
nonisolated struct WidgetSnapshot: Codable, Equatable {

    struct Pick: Codable, Equatable {
        var taskID: UUID
        var title: String
        var minutes: Int
        var shortReason: String

        /// 一歩なら「2歩目」など
        var stepLabel: String?
    }

    /// 今の1つ。なければ nil
    var pick: Pick?

    /// 今の1つがないときに出す、短い言葉
    var emptyMessage: String

    /// 推薦に使った空き時間（分）
    var availableMinutes: Int

    /// 今日の残りの件数
    var todayRemainingCount: Int

    var updatedAt: Date

    static let storageKey = "taskFlow.widget.snapshot"

    /// 写しの中身が同じか（書いた日時は比べない）。同じならウィジェットを描き直さない
    func hasSameContent(as other: WidgetSnapshot?) -> Bool {
        guard let other else {
            return false
        }
        var copy = other
        copy.updatedAt = updatedAt
        return copy == self
    }

    static func load(from defaults: UserDefaults) -> WidgetSnapshot? {
        guard let data = defaults.data(forKey: storageKey) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    /// ウィジェットのギャラリーやプレビューで出す見本
    static let placeholder = WidgetSnapshot(
        pick: Pick(taskID: UUID(), title: "請求書を送る", minutes: 15, shortReason: "期限が近い"),
        emptyMessage: "",
        availableMinutes: 45,
        todayRemainingCount: 3,
        updatedAt: Date()
    )
}
