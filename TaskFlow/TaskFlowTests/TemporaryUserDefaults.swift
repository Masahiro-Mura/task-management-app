import Foundation

/// テスト専用の保存先。破棄されるときに保存内容を消す
///
/// テストはアプリと同じデータ領域で動くため、後片付けをしないと設定ファイルが溜まっていく。
/// テストのスイートにプロパティとして持たせ、テストが終わってスイートが破棄されるときに消す。
final class TemporaryUserDefaults {
    let suiteName: String
    let userDefaults: UserDefaults

    init(prefix: String) {
        suiteName = "\(prefix).\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        userDefaults.removePersistentDomain(forName: suiteName)
    }
}
