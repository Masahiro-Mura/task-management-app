import Foundation
import Testing
@testable import TaskFlow

/// 通知を実際には出さず、予定された内容を記録する
@MainActor
private final class RecordingNotifier: NotificationScheduling {
    private(set) var scheduled: [PlannedNotification] = []

    func requestAuthorization() async -> Bool { true }

    func replaceAll(with notifications: [PlannedNotification]) {
        scheduled = notifications
    }

    func clearBadge() {}
}

@MainActor
private final class StepsClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

/// 一歩ずつ（何歩目まで決めても、ホームには最初の一歩だけ）と、集中中の通知
@MainActor
struct StepsAndQuietFocusTests {

    private let storage = TemporaryUserDefaults(prefix: "StepsAndQuietFocusTests")

    private func makeViewModel(
        clock: StepsClock? = nil,
        notifier: NotificationScheduling? = nil
    ) -> HomeViewModel {
        let clock = clock
        return HomeViewModel(
            userDefaults: storage.userDefaults,
            seedsSampleTasks: false,
            now: { clock?.now ?? Date() },
            notifier: notifier
        )
    }

    private func addBigTask(_ viewModel: HomeViewModel) -> TaskItem {
        viewModel.addTask(title: "部屋の片付け", estimatedMinutes: 120, priority: .medium, scheduledDate: nil, deadline: nil)
        return viewModel.tasks.first { $0.title == "部屋の片付け" }!
    }

    private func addThreeSteps(_ viewModel: HomeViewModel, to big: TaskItem) {
        viewModel.addStep(to: big, title: "机の上", minutes: 10)
        viewModel.addStep(to: big, title: "床の物", minutes: 10)
        viewModel.addStep(to: big, title: "ゴミをまとめる", minutes: 10)
    }

    // MARK: - 一歩ずつ

    @Test
    func onlyTheFirstOpenStepIsRecommended() throws {
        let viewModel = makeViewModel()
        let big = addBigTask(viewModel)
        addThreeSteps(viewModel, to: big)

        let current = try #require(viewModel.recommendation?.task)
        #expect(current.title == "机の上")

        let position = try #require(viewModel.stepPosition(of: current))
        #expect(position.index == 1)
        #expect(position.total == 3)
        #expect(position.parentTitle == "部屋の片付け")

        #expect(viewModel.steps(of: big.id).map(\.title) == ["机の上", "床の物", "ゴミをまとめる"])
    }

    @Test
    func completingAStepMovesToTheNextWithoutAsking() throws {
        let viewModel = makeViewModel()
        let big = addBigTask(viewModel)
        addThreeSteps(viewModel, to: big)

        viewModel.completeRecommendation()

        #expect(viewModel.recommendation?.task.title == "床の物")
        #expect(viewModel.stepPosition(of: try #require(viewModel.recommendation?.task))?.index == 2)
        // 次の一歩はもう決まっているので、聞かない
        #expect(viewModel.nextStepCandidate == nil)

        viewModel.completeRecommendation()
        viewModel.completeRecommendation()

        // 決めた一歩を全部終えて、元のタスクがまだ大きいときだけ聞く
        #expect(viewModel.nextStepCandidate?.id == big.id)
    }

    @Test
    func reorderingOpenStepsChangesWhatComesFirst() {
        let viewModel = makeViewModel()
        let big = addBigTask(viewModel)
        addThreeSteps(viewModel, to: big)

        viewModel.moveOpenSteps(of: big.id, fromOffsets: [2], toOffset: 0)

        #expect(viewModel.steps(of: big.id).map(\.title) == ["ゴミをまとめる", "机の上", "床の物"])
        #expect(viewModel.recommendation?.task.title == "ゴミをまとめる")
    }

    @Test
    func deletingAStepRelinksTheRest() {
        let viewModel = makeViewModel()
        let big = addBigTask(viewModel)
        addThreeSteps(viewModel, to: big)
        let first = viewModel.steps(of: big.id)[0]

        viewModel.deleteStep(first)

        #expect(viewModel.steps(of: big.id).map(\.title) == ["床の物", "ゴミをまとめる"])
        #expect(viewModel.recommendation?.task.title == "床の物")
    }

    @Test
    func stepsAreHiddenFromTheListAndDeletedWithTheParent() {
        let viewModel = makeViewModel()
        let big = addBigTask(viewModel)
        addThreeSteps(viewModel, to: big)

        #expect(viewModel.visibleAllTasks.map(\.title) == ["部屋の片付け"])

        viewModel.deleteTask(big)

        #expect(viewModel.tasks.isEmpty)
    }

    @Test
    func legacyStepsAreMigratedOnLoad() throws {
        let parent = TaskItem(title: "部屋の片付け", estimatedMinutes: 120)
        let legacyStep = TaskItem(
            title: "部屋の片付け：机の上だけ片づける",
            estimatedMinutes: 10,
            splitGroupID: parent.id
        )
        var savedParent = parent
        savedParent.prerequisiteIDs = [legacyStep.id]
        savedParent.splitGroupID = parent.id
        storage.userDefaults.set(
            try JSONEncoder().encode([legacyStep, savedParent]),
            forKey: "taskFlow.tasks"
        )

        let viewModel = makeViewModel()

        let step = try #require(viewModel.tasks.first { $0.id == legacyStep.id })
        #expect(step.title == "机の上だけ片づける")
        #expect(step.parentTaskID == parent.id)
        #expect(viewModel.recommendation?.task.id == step.id)
    }

    @Test
    func nestedLegacyStepsBecomeAnOrderedList() throws {
        // 以前の版で、一歩の一歩を作ったときの形：P ← A ← B（B が先）
        let parent = TaskItem(title: "研究のモデルを作る", estimatedMinutes: 90)
        let first = TaskItem(
            title: "研究のモデルを作る：5分だけ手をつけてみる：必要な物を1つ集める",
            estimatedMinutes: 10,
            splitGroupID: parent.id
        )
        let second = TaskItem(
            title: "研究のモデルを作る：5分だけ手をつけてみる",
            estimatedMinutes: 10,
            prerequisiteIDs: [first.id],
            splitGroupID: parent.id
        )
        var savedParent = parent
        savedParent.prerequisiteIDs = [second.id]
        savedParent.splitGroupID = parent.id
        storage.userDefaults.set(
            try JSONEncoder().encode([first, second, savedParent]),
            forKey: "taskFlow.tasks"
        )

        let viewModel = makeViewModel()

        #expect(viewModel.steps(of: parent.id).map(\.title) == ["必要な物を1つ集める", "5分だけ手をつけてみる"])
        #expect(viewModel.recommendation?.task.title == "必要な物を1つ集める")
        #expect(viewModel.stepPosition(of: try #require(viewModel.recommendation?.task))?.index == 1)
    }

    // MARK: - 集中中の通知

    @Test
    func notificationsPauseWhileFocusingAndMissedOnesComeAfter() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = StepsClock(now: start)
        let notifier = RecordingNotifier()
        let viewModel = makeViewModel(clock: clock, notifier: notifier)

        // 期限まで3時間10分。10分後に「あと3時間」の通知が出る
        viewModel.addTask(
            title: "申請書",
            estimatedMinutes: 15,
            priority: .medium,
            scheduledDate: nil,
            deadline: start.addingTimeInterval(3 * 60 * 60 + 10 * 60)
        )
        viewModel.quickAdd("別のこと 10分")
        await viewModel.setDeadlineNotifications(true)
        #expect(notifier.scheduled.count == 1)

        let other = try #require(viewModel.tasks.first { $0.title == "別のこと" })
        viewModel.startFocus(on: other.id)
        #expect(notifier.scheduled.isEmpty)

        // 集中している間に、通知の時刻を過ぎる
        clock.now = start.addingTimeInterval(20 * 60)
        viewModel.finishFocus(completing: true)

        let reminder = try #require(notifier.scheduled.first)
        #expect(reminder.fireDate == clock.now.addingTimeInterval(60))
    }

    @Test
    func remindersThatPassedBeforeFocusingAreNotRepeated() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let task = TaskItem(title: "申請書", estimatedMinutes: 15, deadline: now.addingTimeInterval(60 * 60))

        // 通知の時刻（2時間前）は集中を始めるより前なので、出し直さない
        let reminders = NotificationPlanner.deadlineReminders(
            for: [task],
            now: now,
            missedSince: now.addingTimeInterval(-30 * 60)
        )

        #expect(reminders.isEmpty)
    }

    @Test
    func focusShortcutURLOnlyWhenEnabled() {
        let viewModel = makeViewModel()
        #expect(viewModel.focusShortcutURL(starting: true) == nil)

        viewModel.setUsesFocusShortcut(true)

        let start = viewModel.focusShortcutURL(starting: true)
        #expect(start?.scheme == "shortcuts")
        #expect(start?.host == "run-shortcut")
        #expect(URLComponents(url: start!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "TaskFlow 集中開始")

        let end = viewModel.focusShortcutURL(starting: false)
        #expect(URLComponents(url: end!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "TaskFlow 集中終了")
    }
}
