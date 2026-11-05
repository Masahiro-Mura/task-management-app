import Foundation

/// アプリと、ウィジェット・共有シート（拡張）とで分け合う保存先
///
/// このフォルダ（`Shared/`）のファイルは、アプリとウィジェット・共有シートの3つのターゲットに入れる。
/// タスクそのものはアプリの保存先に置いたままにし、ここには「今の1つ」の写しと、共有シートから届いた文だけを置く。
nonisolated enum SharedStore {

    /// Xcode の Signing & Capabilities で、3つのターゲットに同じ名前で付ける App Group
    static let appGroupID = "group.com.masahiromura.TaskFlow"

    /// App Group の保存先。App Group をまだ設定していなければ nil（アプリはそのまま動く）
    static var defaults: UserDefaults? {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil else {
            return nil
        }
        return UserDefaults(suiteName: appGroupID)
    }
}
