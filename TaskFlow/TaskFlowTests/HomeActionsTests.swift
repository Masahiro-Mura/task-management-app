import Foundation
import Testing
@testable import TaskFlow

/// テストから進められる時計
@MainActor
private final class ActionsClock {
    var now = Date()

    func advance(minutes: Double) {
        now = now.addingTimeInterval(60 * minutes)
    }
}

/// 推薦カードからの操作（完了・元に戻す・今はやらない・始める）と1行追加
@MainActor
struct HomeActionsTests {

    private let storage = TemporaryUserDefaults(prefix: "HomeActionsTests")
    private let clock = ActionsClock()

    private func makeViewModel() -> HomeViewModel {
        let clock = clock
        return HomeViewModel(
            userDefaults: storage.userDefaults,
            seedsSampleTasks: false,
            now: { clock.now }
        )
    }

    /// 短い順に推薦される2件（A: 10分, B: 20分）を入れる
    private func makeViewModelWithTwoTasks() -> HomeViewModel {
        let viewModel = makeViewModel()
        viewModel.quickAdd("A 10分")
        viewModel.quickAdd("B 20分")
        return viewModel
    }

    // MARK: - 完了と元に戻す

    @Test
    func completingRecommendationMovesToNextAndCanBeUndone() {
        let viewModel = makeViewModelWithTwoTasks()
        #expect(viewModel.recommendation?.task.title == "A")

        viewModel.completeRecommendation()

        #expect(viewModel.recommendation?.task.title == "B")
        #expect(viewModel.lastCompletedTask?.title == "A")
        #expect(viewModel.tasks.first { $0.title == "A" }?.isCompleted == true)

        viewModel.undoLastCompletion()

        #expect(viewModel.recommendation?.task.title == "A")
        #expect(viewModel.lastCompletedTask == nil)
        #expect(viewModel.tasks.first { $0.title == "A" }?.isCompleted == false)
    }

    @Test
    func dismissingUndoKeepsTheTaskCompleted() {
        let viewModel = makeViewModelWithTwoTasks()

        viewModel.completeRecommendation()
        viewModel.dismissUndo()
        viewModel.undoLastCompletion()

        #expect(viewModel.tasks.first { $0.title == "A" }?.isCompleted == true)
    }

    // MARK: - 今はやらない

    @Test
    func skippingShowsNextCandidateForOneHour() {
        let viewModel = makeViewModelWithTwoTasks()

        viewModel.skipRecommendation()
        #expect(viewModel.recommendation?.task.title == "B")

        clock.advance(minutes: 59)
        viewModel.updateRecommendation()
        #expect(viewModel.recommendation?.task.title == "B")

        clock.advance(minutes: 2)
        viewModel.updateRecommendation()
        #expect(viewModel.recommendation?.task.title == "A")
    }

    @Test
    func skippingDoesNotTouchUpdatedAt() throws {
        let viewModel = makeViewModelWithTwoTasks()
        let before = try #require(viewModel.tasks.first { $0.title == "A" }?.updatedAt)

        clock.advance(minutes: 5)
        viewModel.skipRecommendation()

        #expect(viewModel.tasks.first { $0.title == "A" }?.updatedAt == before)
    }

    @Test
    func skippingTheLastCandidateIsCountedAndCanBeCleared() {
        let viewModel = makeViewModel()
        viewModel.quickAdd("A 10分")

        viewModel.skipRecommendation()

        #expect(viewModel.recommendation == nil)
        #expect(viewModel.noRecommendationSummary?.skippedCount == 1)
        #expect(viewModel.noRecommendationSummary?.allCompleted == false)

        viewModel.clearSkips()

        #expect(viewModel.recommendation?.task.title == "A")
    }

    @Test
    func skipsSurviveRelaunch() {
        let first = makeViewModelWithTwoTasks()
        first.skipRecommendation()

        let relaunched = makeViewModel()

        #expect(relaunched.recommendation?.task.title == "B")
    }

    // MARK: - 始める

    @Test
    func focusingAndCompletingFinishesTheTask() {
        let viewModel = makeViewModelWithTwoTasks()

        viewModel.startFocus()
        #expect(viewModel.focusedTask?.title == "A")
        #expect(viewModel.focusSession?.startedAt == clock.now)

        clock.advance(minutes: 12)
        viewModel.finishFocus(completing: true)

        #expect(viewModel.focusSession == nil)
        #expect(viewModel.tasks.first { $0.title == "A" }?.isCompleted == true)
        #expect(viewModel.lastCompletedTask?.title == "A")
        #expect(viewModel.recommendation?.task.title == "B")
    }

    @Test
    func stoppingFocusKeepsTheTaskOpen() {
        let viewModel = makeViewModelWithTwoTasks()

        viewModel.startFocus()
        viewModel.finishFocus(completing: false)

        #expect(viewModel.focusSession == nil)
        #expect(viewModel.recommendation?.task.title == "A")
    }

    // MARK: - 1行追加

    @Test
    func quickAddUsesParsedTitleAndMinutes() {
        let viewModel = makeViewModel()

        #expect(viewModel.quickAdd("資料を読む 1時間"))
        #expect(!viewModel.quickAdd("  "))

        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.tasks.first?.title == "資料を読む")
        #expect(viewModel.tasks.first?.estimatedMinutes == 60)
        #expect(viewModel.tasks.first?.priority == .medium)
    }
}
