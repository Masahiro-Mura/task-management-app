import Foundation
import Testing
@testable import TaskFlow

@MainActor
struct HomeViewModelTests {

    private let tasksKey = "taskFlow.tasks"

    /// テストごとに独立した保存先を用意する
    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "HomeViewModelTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }

    private func unreadableBackupKeys(in userDefaults: UserDefaults) -> [String] {
        userDefaults.dictionaryRepresentation().keys.filter {
            $0.hasPrefix(HomeViewModel.unreadableTasksKeyPrefix)
        }
    }

    @Test
    func startsEmptyWhenNothingIsSavedAndSamplesAreOff() {
        let viewModel = HomeViewModel(
            userDefaults: makeUserDefaults(),
            seedsSampleTasks: false
        )

        #expect(viewModel.tasks.isEmpty)
        #expect(viewModel.recommendation == nil)
    }

    @Test
    func savedTasksAreLoadedOnNextLaunch() {
        let userDefaults = makeUserDefaults()

        let first = HomeViewModel(userDefaults: userDefaults, seedsSampleTasks: false)
        first.addTask(
            title: "レポートを書く",
            estimatedMinutes: 30,
            priority: .high,
            scheduledDate: nil,
            deadline: nil
        )

        let second = HomeViewModel(userDefaults: userDefaults, seedsSampleTasks: true)

        #expect(second.tasks.map(\.title) == ["レポートを書く"])
        #expect(second.tasks.first?.priority == .high)
    }

    @Test
    func unreadableDataIsBackedUpInsteadOfOverwritten() {
        let userDefaults = makeUserDefaults()
        let brokenData = Data("壊れたデータ".utf8)
        userDefaults.set(brokenData, forKey: tasksKey)

        let viewModel = HomeViewModel(userDefaults: userDefaults, seedsSampleTasks: true)

        // サンプルで埋めず、空の状態で始める
        #expect(viewModel.tasks.isEmpty)

        let backupKeys = unreadableBackupKeys(in: userDefaults)
        #expect(backupKeys.count == 1)
        #expect(backupKeys.first.flatMap { userDefaults.data(forKey: $0) } == brokenData)

        // 新しく保存しても退避したデータは残る
        viewModel.addTask(
            title: "新しいタスク",
            estimatedMinutes: 10,
            priority: .medium,
            scheduledDate: nil,
            deadline: nil
        )
        #expect(unreadableBackupKeys(in: userDefaults).count == 1)
    }

    @Test
    func deletingTaskRemovesItFromOtherTasksPrerequisites() throws {
        let userDefaults = makeUserDefaults()
        let viewModel = HomeViewModel(userDefaults: userDefaults, seedsSampleTasks: false)

        viewModel.addTask(
            title: "資料を集める",
            estimatedMinutes: 60,
            priority: .medium,
            scheduledDate: nil,
            deadline: nil
        )
        let preparation = try #require(viewModel.tasks.first)

        viewModel.addTask(
            title: "レポートを書く",
            estimatedMinutes: 30,
            priority: .medium,
            scheduledDate: nil,
            deadline: nil
        )
        var writing = try #require(viewModel.tasks.last)
        writing.prerequisiteIDs = [preparation.id]
        viewModel.updateTask(writing)

        // 前提の60分が空き時間に入らないため、まだ推薦はない
        #expect(viewModel.recommendation == nil)

        viewModel.deleteTask(preparation)

        #expect(viewModel.tasks.first?.prerequisiteIDs.isEmpty == true)
        #expect(viewModel.recommendation?.task.id == writing.id)
    }
}
