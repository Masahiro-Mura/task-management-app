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
