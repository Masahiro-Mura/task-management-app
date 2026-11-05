import Foundation
import Testing
@testable import TaskFlow

/// フェーズ7：最初の一歩・次の一歩・5分だけ・分解の候補
@MainActor
struct EasySplitTests {

    private let storage = TemporaryUserDefaults(prefix: "EasySplitTests")

    private func makeViewModel() -> HomeViewModel {
        HomeViewModel(userDefaults: storage.userDefaults, seedsSampleTasks: false)
    }

    private func addBigTask(_ viewModel: HomeViewModel) -> TaskItem {
        viewModel.addTask(
            title: "部屋の片付け",
            estimatedMinutes: 120,
            priority: .high,
            scheduledDate: nil,
            deadline: nil
        )
        return viewModel.tasks.last!
    }

    // MARK: - 最初の一歩

    @Test
    func noRecommendationPointsAtTheShortestTooLongTask() {
        let viewModel = makeViewModel()
        _ = addBigTask(viewModel)
        viewModel.addTask(title: "引っ越し準備", estimatedMinutes: 240, priority: .medium, scheduledDate: nil, deadline: nil)

        let shortest = viewModel.tasks.first { $0.title == "部屋の片付け" }
        #expect(viewModel.noRecommendationSummary?.shortestTooLongTaskID == shortest?.id)
    }

    @Test
    func firstStepIsRecommendedAndTheBigTaskWaitsForIt() throws {
        let viewModel = makeViewModel()
        let big = addBigTask(viewModel)
        #expect(viewModel.recommendation == nil)

        viewModel.addFirstStep(for: big, title: "  机の上だけ片づける ", minutes: 10)

        let step = try #require(viewModel.recommendation?.task)
        // タイトルには元のタスク名を入れず、元のタスクにぶら下げる
        #expect(step.title == "机の上だけ片づける")
        #expect(step.parentTaskID == big.id)
        #expect(step.estimatedMinutes == 10)
        #expect(step.priority == .high)
        #expect(step.splitGroupID == big.id)

        let updatedBig = try #require(viewModel.tasks.first { $0.id == big.id })
        #expect(updatedBig.prerequisiteIDs == [step.id])
        #expect(updatedBig.splitGroupID == big.id)

        // 一歩は元のタスクの直前に並ぶ
        let stepIndex = try #require(viewModel.tasks.firstIndex { $0.id == step.id })
        let bigIndex = try #require(viewModel.tasks.firstIndex { $0.id == big.id })
        #expect(stepIndex + 1 == bigIndex)
    }

    @Test
    func firstStepInheritsTheOriginalPrerequisites() throws {
        let viewModel = makeViewModel()
        viewModel.addTask(title: "ゴミ袋を買う", estimatedMinutes: 10, priority: .medium, scheduledDate: nil, deadline: nil)
        let bag = try #require(viewModel.tasks.first)

        var big = addBigTask(viewModel)
        big.prerequisiteIDs = [bag.id]
        viewModel.updateTask(big)

        viewModel.addFirstStep(for: big, title: "机の上", minutes: 10)

        let step = try #require(viewModel.tasks.first { $0.title.hasSuffix("机の上") })
        #expect(step.prerequisiteIDs == [bag.id])
    }

    @Test
    func emptyStepTitleAddsNothing() {
        let viewModel = makeViewModel()
        let big = addBigTask(viewModel)

        viewModel.addFirstStep(for: big, title: "   ", minutes: 10)

        #expect(viewModel.tasks.count == 1)
    }

    // MARK: - 次の一歩

    @Test
    func finishingAStepOffersTheNextStep() throws {
        let viewModel = makeViewModel()
        let big = addBigTask(viewModel)
        viewModel.addFirstStep(for: big, title: "机の上", minutes: 10)

        viewModel.completeRecommendation()

        #expect(viewModel.nextStepCandidate?.id == big.id)
        // 元のタスクはまだ120分なので、推薦はない
        #expect(viewModel.recommendation == nil)

        let candidate = try #require(viewModel.nextStepCandidate)
        viewModel.addFirstStep(for: candidate, title: "床の物を拾う", minutes: 10)

        #expect(viewModel.nextStepCandidate == nil)
        #expect(viewModel.recommendation?.task.title == "床の物を拾う")
    }

    @Test
    func undoingClearsTheNextStepOffer() {
        let viewModel = makeViewModel()
        let big = addBigTask(viewModel)
        viewModel.addFirstStep(for: big, title: "机の上", minutes: 10)

        viewModel.completeRecommendation()
        viewModel.undoLastCompletion()

        #expect(viewModel.nextStepCandidate == nil)
    }

    @Test
    func ordinaryTaskCompletionDoesNotOfferNextStep() {
        let viewModel = makeViewModel()
        viewModel.quickAdd("請求書を送る 15分")

        viewModel.completeRecommendation()

        #expect(viewModel.nextStepCandidate == nil)
    }

    // MARK: - 5分だけ

    @Test
    func fiveMinuteFocusWorksEvenForTasksThatDoNotFit() throws {
        let viewModel = makeViewModel()
        let big = addBigTask(viewModel)
        #expect(viewModel.recommendation == nil)

        viewModel.startFocus(on: big.id, trialMinutes: HomeViewModel.trialFocusMinutes)

        #expect(viewModel.focusedTask?.id == big.id)
        #expect(viewModel.focusSession?.trialMinutes == 5)

        viewModel.continueFocus()
        #expect(viewModel.focusSession?.trialMinutes == nil)
        #expect(viewModel.focusedTask?.id == big.id)

        viewModel.finishFocus(completing: false)
        #expect(viewModel.focusSession == nil)
        #expect(viewModel.tasks.first?.isCompleted == false)
    }

    @Test
    func focusIsNotStartedForCompletedTasks() throws {
        let viewModel = makeViewModel()
        viewModel.quickAdd("A 10分")
        let task = try #require(viewModel.tasks.first)
        viewModel.toggleCompletion(for: task)

        viewModel.startFocus(on: task.id, trialMinutes: 5)

        #expect(viewModel.focusSession == nil)
    }

    // MARK: - 分解の候補

    @Test(arguments: [
        ("部屋の片付け", "机の上だけ片づける"),
        ("企画書を書く", "タイトルと見出しだけ書く"),
        ("英語の勉強", "目次をざっと見る"),
        ("引っ越しの手続き", "必要な書類を確認する")
    ])
    func templatesMatchKeywords(title: String, firstSuggestion: String) {
        let suggestions = StepSuggester.templateSuggestions(for: title)

        #expect(suggestions.first == firstSuggestion)
        #expect(suggestions.count == StepSuggester.count)
    }

    @Test
    func unknownTitlesGetGenericSteps() {
        #expect(StepSuggester.templateSuggestions(for: "なにか大きいこと") == [
            "やることを3つ書き出す", "必要な物を1つ集める", "5分だけ手をつけてみる"
        ])
    }
}
