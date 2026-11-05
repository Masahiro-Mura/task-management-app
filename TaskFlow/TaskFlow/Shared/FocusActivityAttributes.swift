import ActivityKit
import Foundation

/// 集中しているあいだ、ロック画面とダイナミックアイランドに出すもの（ライブアクティビティ）
nonisolated struct FocusActivityAttributes: ActivityAttributes {

    struct ContentState: Codable, Hashable {
        /// 目安の終わり（始めた時刻 + 目安の時間）
        var targetEnd: Date
    }

    var taskID: UUID
    var taskTitle: String
    var startedAt: Date

    /// 「5分だけ」なら true
    var isTrial: Bool
}
