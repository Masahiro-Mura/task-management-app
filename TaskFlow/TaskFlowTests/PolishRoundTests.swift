import Foundation
import Testing
@testable import TaskFlow

@MainActor
private final class PolishClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

/// 使ってみての改善：1日の区切り・集中の保存
@MainActor
struct PolishRoundTests {

    private let storage = TemporaryUserDefaults(prefix: "PolishRoundTests")

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func makeViewModel(clock: PolishClock) -> HomeViewModel {
        HomeViewModel(
            userDefaults: storage.userDefaults,
            seedsSampleTasks: false,
            calendar: calendar,
            now: { clock.now }
        )
    }

    // MARK: - 1日の区切り

    @Test
    func lateNightStillCountsAsThePreviousDayWithA4amBoundary() throws {
        // 11/5 の夜に予定を入れ、11/6 の深夜1時半に開く
        let clock = PolishClock(now: date(2026, 11, 5, 21))
        let viewModel = makeViewModel(clock: clock)
        viewModel.addTask(title: "11/5の予定", estimatedMinutes: 10, priority: .medium, scheduledDate: date(2026, 11, 5), deadline: nil)

        clock.now = date(2026, 11, 6, 1, 30)

        // 0時区切りなら、もう持ち越し
        let task = try #require(viewModel.tasks.first)
        #expect(viewModel.isCarriedOver(task))

        viewModel.setDayStartHour(4)

        #expect(!viewModel.isCarriedOver(task))
        #expect(viewModel.todayTasks.map(\.title) == ["11/5の予定"])
    }

    @Test
    func completionsAfterMidnightCountForThePreviousDay() {
        let clock = PolishClock(now: date(2026, 11, 6, 0, 30))
        let viewModel = makeViewModel(clock: clock)
        viewModel.setDayStartHour(4)
        viewModel.quickAdd("夜の作業 10分")
        viewModel.completeRecommendation()

        // 朝3時でも、まだ「今日（11/5）」の分
        clock.now = date(2026, 11, 6, 3)
        #expect(viewModel.completedToday.map(\.title) == ["夜の作業"])

        // 4時を過ぎたら、新しい日
        clock.now = date(2026, 11, 6, 5)
        #expect(viewModel.completedToday.isEmpty)
    }

    @Test
    func dateWordsFollowTheBoundary() throws {
        let clock = PolishClock(now: date(2026, 11, 6, 1, 30))
        let viewModel = makeViewModel(clock: clock)
        viewModel.setDayStartHour(4)

        // 深夜1時半の「明日」は、寝て起きた日（11/6）
        viewModel.quickAdd("明日 掃除")

        #expect(viewModel.tasks.first?.scheduledDate == date(2026, 11, 6))
        #expect(viewModel.dayStartHour == 4)
    }

    @Test
    func boundaryIsSavedAndClamped() {
        let clock = PolishClock(now: date(2026, 11, 5, 10))
        let viewModel = makeViewModel(clock: clock)

        viewModel.setDayStartHour(9)
        #expect(viewModel.dayStartHour == 5)

        #expect(makeViewModel(clock: clock).dayStartHour == 5)
    }

    // MARK: - 集中の保存

    @Test
    func focusSessionResumesAfterRelaunch() throws {
        let clock = PolishClock(now: date(2026, 11, 5, 10))
        let first = makeViewModel(clock: clock)
        first.quickAdd("資料を読む 30分")
        first.startFocus(trialMinutes: 5)

        clock.now = date(2026, 11, 5, 10, 3)
        let relaunched = makeViewModel(clock: clock)

        #expect(relaunched.focusedTask?.title == "資料を読む")
        #expect(relaunched.focusSession?.startedAt == date(2026, 11, 5, 10))
        #expect(relaunched.focusSession?.trialMinutes == 5)

        relaunched.finishFocus(completing: false)
        #expect(makeViewModel(clock: clock).focusSession == nil)
    }

    @Test
    func staleFocusSessionIsDropped() {
        let clock = PolishClock(now: date(2026, 11, 5, 10))
        let first = makeViewModel(clock: clock)
        first.quickAdd("資料を読む 30分")
        first.startFocus()

        clock.now = date(2026, 11, 6, 10)

        #expect(makeViewModel(clock: clock).focusSession == nil)
    }

    // MARK: - 何度も見送られるタスク

    @Test
    func thirdSkipOffersToMakeItSmallerOnce() throws {
        let clock = PolishClock(now: date(2026, 11, 5, 10))
        let viewModel = makeViewModel(clock: clock)
        viewModel.quickAdd("企画書を書く 30分")
        let task = try #require(viewModel.tasks.first)

        for round in 1...3 {
            viewModel.skipRecommendation()
            #expect((viewModel.repeatedSkipCandidate != nil) == (round == 3))
            // 1時間たって、また推薦に戻ってくる
            clock.now = clock.now.addingTimeInterval(61 * 60)
            viewModel.updateRecommendation()
        }

        #expect(viewModel.repeatedSkipCandidate?.id == task.id)
        #expect(!viewModel.isOfferingLightMode)

        viewModel.dismissRepeatedSkipOffer()
        viewModel.skipRecommendation()
        // 聞いたあとは数え直すので、すぐにはまた聞かない
        #expect(viewModel.repeatedSkipCandidate == nil)
    }

    @Test
    func startingOrAddingAStepResetsTheCount() throws {
        let clock = PolishClock(now: date(2026, 11, 5, 10))
        let viewModel = makeViewModel(clock: clock)
        viewModel.quickAdd("企画書を書く 30分")
        let task = try #require(viewModel.tasks.first)

        viewModel.skipRecommendation()
        viewModel.skipRecommendation()
        viewModel.clearSkips()
        viewModel.startFocus(on: task.id)
        viewModel.finishFocus(completing: false)
        viewModel.skipRecommendation()

        #expect(viewModel.repeatedSkipCandidate == nil)
    }

    @Test
    func hibernatingFromTheOfferPutsTheTaskToSleep() throws {
        let clock = PolishClock(now: date(2026, 11, 5, 10))
        let viewModel = makeViewModel(clock: clock)
        viewModel.quickAdd("企画書を書く 30分")
        let task = try #require(viewModel.tasks.first)

        viewModel.hibernate(task)

        #expect(viewModel.dormantTaskIDs == [task.id])
        #expect(viewModel.repeatedSkipCandidate == nil)
    }

    // MARK: - 見積もりと実際

    @Test
    func actualTimeIsRecordedAndShapesTheQuickAddDefault() throws {
        let clock = PolishClock(now: date(2026, 11, 5, 9))
        let viewModel = makeViewModel(clock: clock)
        #expect(viewModel.estimateRatio == nil)
        #expect(viewModel.quickAddDefaultMinutes == 30)

        // 20分の見積もりで、実際は30分かかった（1.5倍）を5回
        for index in 0..<5 {
            viewModel.quickAdd("作業\(index) 20分")
            let task = try #require(viewModel.tasks.last)
            viewModel.startFocus(on: task.id)
            clock.now = clock.now.addingTimeInterval(30 * 60)
            viewModel.finishFocus(completing: true)
        }

        #expect(viewModel.tasks.allSatisfy { $0.actualMinutes == 30 })
        #expect(viewModel.estimateRatio == 1.5)
        #expect(viewModel.quickAddDefaultMinutes == 45)

        // 時間を書いたときは、そのまま
        viewModel.quickAdd("メール 10分")
        #expect(viewModel.tasks.last?.estimatedMinutes == 10)
        viewModel.quickAdd("掃除")
        #expect(viewModel.tasks.last?.estimatedMinutes == 45)
    }

    // MARK: - UIテスト用の起動

    @Test
    func uiTestingLaunchUsesAnEmptySeparateStore() {
        let plain = HomeViewModel.makeForApp(arguments: ["-uiTesting"])
        #expect(plain.tasks.isEmpty)
        #expect(!plain.needsOnboarding)

        let seeded = HomeViewModel.makeForApp(arguments: ["-uiTesting", "-uiTestingSeed"])
        #expect(seeded.tasks.map(\.title) == ["Write report", "Read paper"])
    }

    // MARK: - 古い完了の整理

    @Test
    func completedTasksOlderThanAYearAreDropped() throws {
        let clock = PolishClock(now: date(2025, 11, 1, 10))
        let first = makeViewModel(clock: clock)
        first.quickAdd("去年の作業 10分")
        first.quickAdd("まだの作業 10分")
        let old = try #require(first.tasks.first { $0.title == "去年の作業" })
        first.toggleCompletion(for: old)

        clock.now = date(2026, 11, 5, 10)
        let relaunched = makeViewModel(clock: clock)

        #expect(relaunched.tasks.map(\.title) == ["まだの作業"])
    }
}
