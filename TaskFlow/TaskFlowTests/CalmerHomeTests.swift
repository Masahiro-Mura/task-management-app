import Foundation
import Testing
@testable import TaskFlow

/// 書いた文をタスクらしい名前に整える
struct TitleNormalizerTests {

    @Test(arguments: [
        ("先生にメール送らないといけない", "先生にメール送る"),
        ("あ、レポート書かなきゃ！", "レポート書く"),
        ("部屋の掃除しないと", "部屋の掃除する"),
        ("TODO: 請求書の確認", "請求書の確認"),
        ("牛乳を買わないと。", "牛乳を買う"),
        ("ご飯食べないと", "ご飯食べる"),
        ("病院に行かなければならない", "病院に行く"),
        ("資料を作成しておく", "資料を作成する"),
        ("洗濯物を取り込むこと", "洗濯物を取り込む"),
        ("区役所に来ないと", "区役所に来る"),
        ("請求書を送る", "請求書を送る"),
        ("ゴミ出し", "ゴミ出し")
    ])
    func normalizes(_ input: String, _ expected: String) {
        #expect(TitleNormalizer.normalize(input) == expected)
    }

    @Test
    func keepsTheTextWhenNothingWouldRemain() {
        #expect(TitleNormalizer.normalize("しないと") == "しないと")
        #expect(TitleNormalizer.normalize("あ、") == "あ、")
    }

    @Test
    func leavesAmbiguousWordsAlone() {
        // 「あのこと」の「こと」は名詞の一部なので外さない
        #expect(TitleNormalizer.normalize("あのこと") == "あのこと")
    }
}

/// 1行入力で名前を整え、チップで元に戻せる
struct QuickAddRenameTests {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 10))!
    }

    @Test
    func renamesAfterReadingDateAndDuration() throws {
        let result = try #require(
            QuickAddParser.parse("明日までにレポート書かないと 30分", defaultMinutes: 15, now: now, calendar: calendar)
        )

        #expect(result.title == "レポート書く")
        #expect(result.unrenamedTitle == "レポート書かないと")
        #expect(result.estimatedMinutes == 30)
        #expect(result.deadline != nil)
    }

    @Test
    func ignoringRenameKeepsWhatWasWritten() throws {
        let result = try #require(
            QuickAddParser.parse("レポート書かないと", defaultMinutes: 15, now: now, calendar: calendar, ignoring: [.rename])
        )

        #expect(result.title == "レポート書かないと")
        #expect(result.unrenamedTitle == nil)
    }

    @Test
    func noRenameWhenAlreadyTaskLike() throws {
        let result = try #require(
            QuickAddParser.parse("請求書を送る 15分", defaultMinutes: 15, now: now, calendar: calendar)
        )

        #expect(result.title == "請求書を送る")
        #expect(result.unrenamedTitle == nil)
    }
}

/// 落ち着いたホーム：短い決め手・あとでの取り消し・削除の取り消し
@MainActor
struct CalmerHomeTests {

    private let storage = TemporaryUserDefaults(prefix: "CalmerHomeTests")

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 10))!
    }

    private func makeViewModel() -> HomeViewModel {
        let fixed = now
        return HomeViewModel(
            userDefaults: storage.userDefaults,
            seedsSampleTasks: false,
            calendar: calendar,
            now: { fixed }
        )
    }

    // MARK: - 短い決め手

    @Test
    func shortReasonNamesTheDecidingFactor() throws {
        let engine = DecisionEngine()
        let context = DecisionContext(availableMinutes: 60, currentDate: now)

        let urgent = try #require(engine.recommend(
            from: [
                TaskItem(title: "急ぎ", estimatedMinutes: 20, deadline: now.addingTimeInterval(3 * 3600)),
                TaskItem(title: "ほか", estimatedMinutes: 10)
            ],
            context: context
        ))
        #expect(urgent.shortReason == "期限まであと3時間")

        let shorter = try #require(engine.recommend(
            from: [
                TaskItem(title: "長い", estimatedMinutes: 40),
                TaskItem(title: "短い", estimatedMinutes: 10)
            ],
            context: context
        ))
        #expect(shorter.task.title == "短い")
        #expect(shorter.shortReason == "すぐ終わる")

        let overdue = try #require(engine.recommend(
            from: [TaskItem(title: "過ぎた", estimatedMinutes: 10, deadline: now.addingTimeInterval(-3600))],
            context: context
        ))
        #expect(overdue.shortReason == "今なら片づく")
    }

    // MARK: - あとで

    @Test
    func undoSkipBringsTheTaskBack() throws {
        let viewModel = makeViewModel()
        viewModel.addTask(title: "A", estimatedMinutes: 10, priority: .high, scheduledDate: nil, deadline: nil)
        viewModel.addTask(title: "B", estimatedMinutes: 10, priority: .low, scheduledDate: nil, deadline: nil)
        #expect(viewModel.recommendation?.task.title == "A")

        viewModel.skipRecommendation()
        #expect(viewModel.undoEntry?.actionTitle == "やっぱり今やる")
        #expect(viewModel.recommendation?.task.title == "B")

        viewModel.undo()
        #expect(viewModel.undoEntry == nil)
        #expect(viewModel.recommendation?.task.title == "A")
        #expect(!viewModel.isOfferingLightMode)
    }

    // MARK: - 削除

    @Test
    func undoDeleteRestoresTaskStepsAndOrder() throws {
        let viewModel = makeViewModel()
        viewModel.addTask(title: "まとめる", estimatedMinutes: 60, priority: .medium, scheduledDate: nil, deadline: nil)
        let parent = try #require(viewModel.tasks.first)
        viewModel.addStep(to: parent, title: "集める", minutes: 10)
        viewModel.addStep(to: parent, title: "書く", minutes: 10)
        let before = viewModel.tasks

        viewModel.deleteTask(parent)
        #expect(viewModel.tasks.isEmpty)
        #expect(viewModel.undoEntry?.message == "「まとめる」を削除しました")

        viewModel.undo()
        #expect(viewModel.undoEntry == nil)
        #expect(viewModel.tasks.map(\.id) == before.map(\.id))
        #expect(viewModel.tasks.map(\.prerequisiteIDs) == before.map(\.prerequisiteIDs))
    }

    @Test
    func undoDeleteReconnectsDependents() throws {
        let viewModel = makeViewModel()
        viewModel.addTask(title: "先", estimatedMinutes: 10, priority: .medium, scheduledDate: nil, deadline: nil)
        viewModel.addTask(title: "後", estimatedMinutes: 10, priority: .medium, scheduledDate: nil, deadline: nil)
        let first = try #require(viewModel.tasks.first { $0.title == "先" })
        var second = try #require(viewModel.tasks.first { $0.title == "後" })
        second.prerequisiteIDs = [first.id]
        viewModel.updateTask(second)

        viewModel.deleteTask(first)
        #expect(viewModel.tasks.first { $0.title == "後" }?.prerequisiteIDs.isEmpty == true)

        viewModel.undo()
        #expect(viewModel.tasks.first { $0.title == "後" }?.prerequisiteIDs == [first.id])
    }
}
