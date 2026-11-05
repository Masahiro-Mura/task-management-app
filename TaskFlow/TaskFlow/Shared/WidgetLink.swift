import Foundation

/// ウィジェットやライブアクティビティから、アプリを開くときのURL
///
/// 例：`taskflow://focus?task=<ID>&minutes=5`（5分だけ始める）、`taskflow://add`（入力欄を開く）
nonisolated enum WidgetLink: Equatable {
    /// ホームを開くだけ
    case home

    /// そのタスクに取りかかる。minutes があれば「5分だけ」
    case focus(taskID: UUID, trialMinutes: Int?)

    /// 1行の入力欄を開く
    case add

    static let scheme = "taskflow"

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme

        switch self {
        case .home:
            components.host = "home"
        case .focus(let taskID, let trialMinutes):
            components.host = "focus"
            components.queryItems = [URLQueryItem(name: "task", value: taskID.uuidString)]
                + (trialMinutes.map { [URLQueryItem(name: "minutes", value: String($0))] } ?? [])
        case .add:
            components.host = "add"
        }

        return components.url!
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        func value(_ name: String) -> String? {
            components.queryItems?.first { $0.name == name }?.value
        }

        switch components.host {
        case "home":
            self = .home
        case "add":
            self = .add
        case "focus":
            guard let id = value("task").flatMap(UUID.init(uuidString:)) else {
                return nil
            }
            self = .focus(taskID: id, trialMinutes: value("minutes").flatMap { Int($0) })
        default:
            return nil
        }
    }
}
