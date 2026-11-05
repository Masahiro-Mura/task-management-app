import AppIntents
import Foundation

/// Siri やショートカットから、1行でタスクを足す
///
/// 書き方は1行入力と同じ（「明日の15時に資料作成 30分」「毎週月曜にゴミ出し」など）。
struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "タスクを追加"
    static let description = IntentDescription("1行入力と同じ書き方で、TaskFlow にタスクを足します。")

    @Parameter(title: "タスク", requestValueDialog: "何を足しますか？")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let viewModel = HomeViewModel.current ?? HomeViewModel()

        guard let parsed = viewModel.previewQuickAdd(text), viewModel.quickAdd(text) else {
            return .result(dialog: "タスク名が空だったので、足しませんでした。")
        }

        return .result(dialog: "「\(parsed.title)」を足しました。")
    }
}

/// Siri やショートカットで「今の1つ」を聞く
struct CurrentPickIntent: AppIntent {
    static let title: LocalizedStringResource = "今の1つ"
    static let description = IntentDescription("今の空き時間で取りかかるタスクを1つ、理由と一緒に教えます。")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let viewModel = HomeViewModel.current ?? HomeViewModel()
        viewModel.updateRecommendation()

        guard let recommendation = viewModel.recommendation else {
            return .result(dialog: "今の空き時間で取りかかれるタスクはありません。")
        }

        return .result(dialog: "今の1つは「\(recommendation.task.title)」です。\(recommendation.reason)")
    }
}

/// 「Hey Siri、TaskFlow に追加」などの呼び方
struct TaskFlowShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "\(.applicationName)に追加",
                "\(.applicationName)にタスクを追加"
            ],
            shortTitle: "タスクを追加",
            systemImageName: "plus.circle"
        )

        AppShortcut(
            intent: CurrentPickIntent(),
            phrases: [
                "\(.applicationName)で今の1つ",
                "\(.applicationName)で次は何をする"
            ],
            shortTitle: "今の1つ",
            systemImageName: "sparkles"
        )
    }
}
