import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// 大きいタスクの「最初の一歩」の候補を出す
///
/// 対応機種では端末内のAI（Foundation Models）で作り、データは端末の外に出さない。
/// 非対応の機種やAIが使えないときは、タスク名の言葉から決まった型を出す。
nonisolated enum StepSuggester {

    /// 候補の数
    static let count = 3

    /// 端末内のAIが使えるか
    static var isAIAvailable: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        #endif
        return false
    }

    /// 出した候補と、どうやって作ったか
    struct Suggestions: Equatable {
        var steps: [String]

        /// 端末内のAIで作ったか（false なら決まった型）
        var isFromAI: Bool
    }

    /// 候補を出す。AIが使えれば使い、失敗したら決まった型に戻る
    static func suggestions(for title: String) async -> Suggestions {
        #if canImport(FoundationModels)
        if isAIAvailable, let generated = try? await generateWithAI(for: title), !generated.isEmpty {
            return Suggestions(steps: generated, isFromAI: true)
        }
        #endif
        return Suggestions(steps: templateSuggestions(for: title), isFromAI: false)
    }

    /// タスク名の言葉から選ぶ、決まった型の候補
    static func templateSuggestions(for title: String) -> [String] {
        // 言葉はタスク名に含まれるかで調べる（日本語と英語）。候補は使っている言語で出す
        let templates: [(keywords: [String], steps: [String])] = [
            (["片付", "片づ", "掃除", "整理", "部屋", "clean", "tidy", "room"], [
                String(localized: "机の上だけ片づける"),
                String(localized: "床に落ちている物を拾う"),
                String(localized: "ゴミをひとまとめにする")
            ]),
            (["資料", "レポート", "企画", "書く", "文章", "論文", "報告", "write", "report", "draft", "essay"], [
                String(localized: "タイトルと見出しだけ書く"),
                String(localized: "入れたいことを3つメモする"),
                String(localized: "最初の1段落だけ書く")
            ]),
            (["メール", "連絡", "返信", "電話", "mail", "reply", "call", "message"], [
                String(localized: "送る相手を1人決める"),
                String(localized: "件名だけ書く"),
                String(localized: "要点を3行で書く")
            ]),
            (["勉強", "読む", "読書", "復習", "予習", "study", "read", "learn", "review"], [
                String(localized: "目次をざっと見る"),
                String(localized: "5ページだけ読む"),
                String(localized: "問題を1問だけ解く")
            ]),
            (["準備", "支度", "荷造り", "用意", "prepare", "pack"], [
                String(localized: "必要な物を書き出す"),
                String(localized: "1つだけ用意する"),
                String(localized: "置き場所を決める")
            ]),
            (["買い物", "買う", "注文", "buy", "shop", "order"], [
                String(localized: "買う物を3つ書き出す"),
                String(localized: "1つだけ値段を調べる"),
                String(localized: "店かサイトを決める")
            ]),
            (["申請", "手続き", "書類", "提出", "apply", "form", "submit"], [
                String(localized: "必要な書類を確認する"),
                String(localized: "名前と日付だけ書く"),
                String(localized: "提出先を調べる")
            ])
        ]

        let lowercased = title.lowercased()
        for template in templates where template.keywords.contains(where: { lowercased.contains($0) }) {
            return template.steps
        }

        return [
            String(localized: "やることを3つ書き出す"),
            String(localized: "必要な物を1つ集める"),
            String(localized: "5分だけ手をつけてみる")
        ]
    }

    #if canImport(FoundationModels)
    @Generable
    struct StepIdeas {
        @Guide(description: "最初の5分でできる、具体的で小さな作業。指示された言語で、短く。動詞で終える。")
        var steps: [String]
    }

    /// 候補を書く言語の名前（アプリを使っている言語。例：日本語、English）
    private static var answerLanguage: String {
        let code = Locale.current.language.languageCode?.identifier ?? "ja"
        return Locale(identifier: code).localizedString(forLanguageCode: code) ?? code
    }

    private static func generateWithAI(for title: String) async throws -> [String] {
        let session = LanguageModelSession(
            instructions: """
            あなたは、先延ばししがちな人がタスクに取りかかれるよう、最初の小さな一歩を提案します。
            責めたり急かしたりせず、5分以内にできる具体的な作業だけを出してください。
            答えは \(answerLanguage) で書いてください。
            """
        )

        let response = try await session.respond(
            to: "「\(title)」に取りかかるための、最初の小さな一歩を\(count)つ考えてください。",
            generating: StepIdeas.self
        )

        return response.content.steps
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(count)
            .map { $0 }
    }
    #endif
}
