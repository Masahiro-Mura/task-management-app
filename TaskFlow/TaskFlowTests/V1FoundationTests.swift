import Foundation
import Testing
@testable import TaskFlow

/// フェーズ10：書き出し・読み込み、初回の案内
@MainActor
struct V1FoundationTests {

    private let storage = TemporaryUserDefaults(prefix: "V1FoundationTests")
    private let otherStorage = TemporaryUserDefaults(prefix: "V1FoundationTestsOther")

    private func makeViewModel(_ userDefaults: UserDefaults) -> HomeViewModel {
        HomeViewModel(userDefaults: userDefaults, seedsSampleTasks: false)
    }

    // MARK: - 書き出し・読み込み

    @Test
    func backupRoundTripsEverything() throws {
        let source = makeViewModel(storage.userDefaults)
        source.quickAdd("請求書を送る 15分")
        source.quickAdd("いつかやる 10分")
        source.addRecurring(title: "ストレッチ", estimatedMinutes: 5, recurrence: Recurrence(rule: .daily))
        let someday = try #require(source.tasks.first { $0.title == "いつかやる" })
        source.letGo([someday.id])

        let data = source.makeBackup()

        let destination = makeViewModel(otherStorage.userDefaults)
        let summary = try destination.importBackup(data)

        #expect(summary.addedRecurringTasks == 1)
        #expect(summary.addedArchivedTasks == 1)
        #expect(Set(destination.tasks.map(\.title)).isSuperset(of: ["請求書を送る", "ストレッチ"]))
        #expect(destination.archivedTasks.map(\.title) == ["いつかやる"])
        #expect(destination.recurringTasks.map(\.title) == ["ストレッチ"])
    }

    @Test
    func importingTwiceAddsNothingNew() throws {
        let viewModel = makeViewModel(storage.userDefaults)
        viewModel.quickAdd("請求書を送る 15分")
        let data = viewModel.makeBackup()

        let summary = try viewModel.importBackup(data)

        #expect(summary.total == 0)
        #expect(viewModel.tasks.count == 1)
    }

    @Test
    func importingDoesNotOverwriteExistingTasks() throws {
        let viewModel = makeViewModel(storage.userDefaults)
        viewModel.quickAdd("元の名前 15分")
        let data = viewModel.makeBackup()

        var renamed = try #require(viewModel.tasks.first)
        renamed.title = "変えた名前"
        viewModel.updateTask(renamed)

        try viewModel.importBackup(data)

        #expect(viewModel.tasks.map(\.title) == ["変えた名前"])
    }

    @Test
    func unreadableAndNewerFilesAreRejected() throws {
        let viewModel = makeViewModel(storage.userDefaults)

        #expect(throws: BackupError.self) {
            try viewModel.importBackup(Data("これはJSONではない".utf8))
        }

        let newer = BackupFile(
            version: BackupFile.currentVersion + 1,
            exportedAt: Date(),
            tasks: [],
            recurringTasks: [],
            archivedTasks: []
        )
        let newerData = try BackupFile.encoder().encode(newer)

        #expect(throws: BackupError.self) {
            try viewModel.importBackup(newerData)
        }
    }

    @Test
    func backupFileNameHasTheDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let fixed = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 10))!

        let viewModel = HomeViewModel(
            userDefaults: storage.userDefaults,
            seedsSampleTasks: false,
            calendar: calendar,
            now: { fixed }
        )

        #expect(viewModel.backupFileName == "TaskFlow-2026-11-05.json")
    }

    // MARK: - 初回の案内

    @Test
    func onboardingShowsOnceOnAnEmptyFirstLaunch() {
        let viewModel = makeViewModel(storage.userDefaults)
        #expect(viewModel.needsOnboarding)

        viewModel.finishOnboarding(addExamples: false)

        #expect(!viewModel.needsOnboarding)
        #expect(viewModel.tasks.isEmpty)
        #expect(!makeViewModel(storage.userDefaults).needsOnboarding)
    }

    @Test
    func onboardingCanAddExamplesThatGetRecommended() {
        let viewModel = makeViewModel(storage.userDefaults)

        viewModel.finishOnboarding(addExamples: true)

        #expect(viewModel.tasks.count == 3)
        #expect(viewModel.tasks.contains { $0.deadline != nil })
        #expect(viewModel.recommendation != nil)
    }

    @Test
    func onboardingCanBeShownAgainFromSettings() {
        let viewModel = makeViewModel(storage.userDefaults)
        viewModel.quickAdd("請求書を送る 15分")
        #expect(!viewModel.needsOnboarding)

        viewModel.showOnboardingAgain()
        #expect(viewModel.needsOnboarding)

        viewModel.finishOnboarding(addExamples: false)
        #expect(!viewModel.needsOnboarding)
        #expect(viewModel.tasks.count == 1)
    }
}
