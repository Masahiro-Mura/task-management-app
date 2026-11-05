import Foundation

/// 共有シートから届いた文の受け箱
///
/// 共有シート（拡張）はここに書くだけにし、タスクにするのはアプリが開いたとき（`HomeViewModel.importSharedItems`）。
/// こうしておくと、拡張がタスクの保存データに触れずに済む。
nonisolated enum ShareInbox {

    struct Item: Codable, Equatable {
        /// タスク名にする文（1行入力と同じ書き方が使える）
        var text: String

        /// 共有したページのURL。あればタスクに残す
        var link: URL?

        var sharedAt: Date
    }

    static let storageKey = "taskFlow.share.inbox"

    static func append(_ item: Item, to defaults: UserDefaults) {
        var items = load(from: defaults)
        items.append(item)
        save(items, to: defaults)
    }

    /// 届いているものを取り出して、受け箱を空にする
    static func drain(from defaults: UserDefaults) -> [Item] {
        let items = load(from: defaults)
        if !items.isEmpty {
            defaults.removeObject(forKey: storageKey)
        }
        return items
    }

    private static func load(from defaults: UserDefaults) -> [Item] {
        guard let data = defaults.data(forKey: storageKey) else {
            return []
        }
        return (try? JSONDecoder().decode([Item].self, from: data)) ?? []
    }

    private static func save(_ items: [Item], to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: storageKey)
        }
    }

    /// 共有されたページから、タスク名の案を作る。「〇〇」を読む
    ///
    /// ページ名の後ろによく付く「 | サイト名」「 - サイト名」は外す。
    static func suggestedTitle(pageTitle: String?, url: URL?) -> String {
        var title = (pageTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        for separator in [" | ", " - ", " – ", " — ", "｜"] {
            if let range = title.range(of: separator, options: .backwards),
               title.distance(from: title.startIndex, to: range.lowerBound) >= 4 {
                title = String(title[..<range.lowerBound])
            }
        }

        if title.isEmpty {
            title = url?.host(percentEncoded: false)?.replacingOccurrences(of: "www.", with: "") ?? ""
        }

        guard !title.isEmpty else {
            return ""
        }
        return url == nil ? title : "「\(title)」を読む"
    }
}
