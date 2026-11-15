import Foundation
import Testing
@testable import TaskFlow

/// 一覧の欄分けと「今やる」
@MainActor
struct ClearStructureTests {

    private let storage = TemporaryUserDefaults(prefix: "ClearStructureTests")

    private func makeViewModel() -> HomeViewModel {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let fixed = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 10))!
        return HomeViewModel(userDefaults: storage.userDefaults, seedsSampleTasks: false, calendar: calendar, now: { fixed })
    }

    @Test
    func skippedTasksAreListedAndStartingOneTakesItOutOfLater() throws {
        let viewModel = makeViewModel()
        viewModel.addTask(title: "A", estimatedMinutes: 10, priority: .high, scheduledDate: nil, deadline: nil)
        viewModel.addTask(title: "B", estimatedMinutes: 10, priority: .low, scheduledDate: nil, deadline: nil)
        let a = try #require(viewModel.allTasks.first { $0.title == "A" })

        viewModel.skipRecommendation()
        #expect(viewModel.skippedTaskIDs == [a.id])

        // 一覧の「今やる」で始めたら、もう「あとで」ではない
        viewModel.startFocus(on: a.id)
        #expect(viewModel.focusSession?.taskID == a.id)
        #expect(viewModel.skippedTaskIDs.isEmpty)

        viewModel.finishFocus(completing: false)
        #expect(viewModel.recommendation?.task.title == "A")
    }
}

/// 済んだ一歩を戻す
@MainActor
struct ReopenStepTests {

    private let storage = TemporaryUserDefaults(prefix: "ReopenStepTests")

    private func makeViewModel() -> HomeViewModel {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let fixed = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 10))!
        return HomeViewModel(userDefaults: storage.userDefaults, seedsSampleTasks: false, calendar: calendar, now: { fixed })
    }

    @Test
    func aDoneStepCanBeReopenedAndBecomesTheNextStepAgain() throws {
        let viewModel = makeViewModel()
        viewModel.addTask(title: "論文を読む", estimatedMinutes: 60, priority: .medium, scheduledDate: nil, deadline: nil)
        let parent = try #require(viewModel.allTasks.first)
        viewModel.addStep(to: parent, title: "目次を見る", minutes: 5)
        viewModel.addStep(to: parent, title: "1章を読む", minutes: 20)

        #expect(viewModel.recommendation?.task.title == "目次を見る")
        viewModel.completeRecommendation()
        #expect(viewModel.recommendation?.task.title == "1章を読む")

        // 時間がたって「元に戻す」が消えたあとでも、一歩の一覧から戻せる
        viewModel.dismissUndo()
        let done = try #require(viewModel.steps(of: parent.id).first { $0.isCompleted })
        viewModel.reopenStep(done)

        #expect(viewModel.steps(of: parent.id).allSatisfy { !$0.isCompleted })
        #expect(viewModel.recommendation?.task.title == "目次を見る")
        #expect(viewModel.undoEntry?.message == "「目次を見る」を未完了に戻しました")
    }

    @Test
    func reopeningAStepAlsoReopensACompletedParent() throws {
        let viewModel = makeViewModel()
        viewModel.addTask(title: "論文を読む", estimatedMinutes: 60, priority: .medium, scheduledDate: nil, deadline: nil)
        let parent = try #require(viewModel.allTasks.first)
        viewModel.addStep(to: parent, title: "目次を見る", minutes: 5)
        viewModel.completeRecommendation()
        // 元のタスク（60分）は空き時間に入らないので、一覧から完了にする
        viewModel.toggleCompletion(for: try #require(viewModel.allTasks.first { $0.id == parent.id }))
        #expect(viewModel.allTasks.first { $0.id == parent.id }?.isCompleted == true)

        let step = try #require(viewModel.steps(of: parent.id).first)
        viewModel.reopenStep(step)
        #expect(viewModel.allTasks.first { $0.id == parent.id }?.isCompleted == false)
        #expect(viewModel.steps(of: parent.id).first?.isCompleted == false)
    }
}
