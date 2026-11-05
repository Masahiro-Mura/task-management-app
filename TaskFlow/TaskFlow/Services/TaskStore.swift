import Foundation

/// TaskFlow のデータを UserDefaults に読み書きする
///
/// どのキーに何を入れるかを1か所にまとめる。値は JSON（`Codable`）か、真偽値・数・日付。
struct TaskStore {

    enum Key {
        static let tasks = "taskFlow.tasks"
        static let archived = "taskFlow.archived"
        static let recurring = "taskFlow.recurring"
        static let skippedUntil = "taskFlow.skippedUntil"
        static let focusSession = "taskFlow.focusSession"
        static let availableMinutes = "taskFlow.availableMinutes"

        /// 読み込めなかった保存データの退避先キーの接頭辞
        static let unreadableTasksPrefix = "taskFlow.tasks.unreadable."
    }

    /// タスク一覧を読んだ結果
    enum LoadResult {
        case loaded([TaskItem])
        case notFound
        case unreadable(Data)
    }

    let userDefaults: UserDefaults

    /// タスク一覧を読む。読めなかったときは、退避できるよう元のデータを返す
    func loadTasks() -> LoadResult {
        guard let data = userDefaults.data(forKey: Key.tasks) else {
            return .notFound
        }

        guard let tasks = try? JSONDecoder().decode([TaskItem].self, from: data) else {
            return .unreadable(data)
        }

        return .loaded(tasks)
    }

    /// 読み込めなかった保存データを、日時つきの別キーへ退避し、元のキーは空にする
    ///
    /// 起動のたびに同じデータを退避し直さないよう、元のキーは消す。
    func backUpUnreadableTasks(_ data: Data, at date: Date) {
        let timestamp = ISO8601DateFormatter().string(from: date)
        userDefaults.set(data, forKey: Key.unreadableTasksPrefix + timestamp)
        userDefaults.removeObject(forKey: Key.tasks)
    }

    /// JSON で保存したものを読む。なければ、または読めなければ nil
    func load<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        guard let data = userDefaults.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// JSON で保存する。nil なら消す
    func save<Value: Encodable>(_ value: Value?, forKey key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            userDefaults.removeObject(forKey: key)
            return
        }
        userDefaults.set(data, forKey: key)
    }
}
