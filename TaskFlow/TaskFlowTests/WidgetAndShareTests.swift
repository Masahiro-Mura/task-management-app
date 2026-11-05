import Foundation
import Testing
@testable import TaskFlow

/// 集中のライブアクティビティの出し入れを記録する偽物
@MainActor
private final class FakeFocusActivity: FocusActivityPresenting {
    var shown: [(title: String, targetEnd: Date, isTrial: Bool)] = []
    var endCount = 0

    func show(_ attributes: FocusActivityAttributes, targetEnd: Date) {
        shown.append((attributes.taskTitle, targetEnd, attributes.isTrial))
    }

    func end() {
        endCount += 1
    }
}

@MainActor
private final class ReloadCounter {
    var count = 0
}

/// ウィジェット・共有シート・ライブアクティビティ
@MainActor
struct WidgetAndShareTests {

    private let storage = TemporaryUserDefaults(prefix: "WidgetAndShareTests")
    private let shared = TemporaryUserDefaults(prefix: "WidgetAndShareTestsShared")

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 10))!
    }

    private func makeViewModel(
        reloads: ReloadCounter? = nil,
        focusActivity: FocusActivityPresenting? = nil
    ) -> HomeViewModel {
        let fixed = now
        return HomeViewModel(
            userDefaults: storage.userDefaults,
            seedsSampleTasks: false,
            calendar: calendar,
            now: { fixed },
            sharedDefaults: shared.userDefaults,
            reloadWidgets: { reloads?.count += 1 },
            focusActivity: focusActivity
        )
    }

    // MARK: - ウィジェット

    @Test
    func snapshotFollowsTheRecommendationAndReloadsOnlyOnChange() throws {
        let reloads = ReloadCounter()
        let viewModel = makeViewModel(reloads: reloads)

        let empty = try #require(WidgetSnapshot.load(from: shared.userDefaults))
        #expect(empty.pick == nil)
        #expect(empty.emptyMessage == "やることはありません")

        viewModel.addTask(title: "請求書を送る", estimatedMinutes: 15, priority: .high, scheduledDate: nil, deadline: nil)
        let snapshot = try #require(WidgetSnapshot.load(from: shared.userDefaults))
        #expect(snapshot.pick?.title == "請求書を送る")
        #expect(snapshot.pick?.minutes == 15)
        #expect(snapshot.pick?.shortReason == viewModel.recommendation?.shortReason)

        // 中身が同じなら描き直さない
        let count = reloads.count
        viewModel.updateRecommendation()
        viewModel.updateRecommendation()
        #expect(reloads.count == count)
    }

    @Test
    func noSharedStoreMeansNoSnapshot() {
        let viewModel = HomeViewModel(userDefaults: storage.userDefaults, seedsSampleTasks: false)
        viewModel.addTask(title: "A", estimatedMinutes: 10, priority: .medium, scheduledDate: nil, deadline: nil)
        #expect(WidgetSnapshot.load(from: shared.userDefaults) == nil)
    }

    @Test
    func widgetLinksRoundTrip() {
        let id = UUID()
        let links: [WidgetLink] = [.home, .add, .focus(taskID: id, trialMinutes: 5), .focus(taskID: id, trialMinutes: nil)]

        for link in links {
            #expect(WidgetLink(url: link.url) == link)
        }
        #expect(WidgetLink(url: URL(string: "https://example.com")!) == nil)
        #expect(WidgetLink(url: URL(string: "taskflow://focus?task=nope")!) == nil)
    }

    // MARK: - 共有シート

    @Test
    func sharedItemsBecomeTasksWithTheirLink() throws {
        let viewModel = makeViewModel()
        let url = URL(string: "https://example.com/article")!

        ShareInbox.append(.init(text: "「記事」を読む 10分", link: url, sharedAt: now), to: shared.userDefaults)
        ShareInbox.append(.init(text: "牛乳を買わないと", link: nil, sharedAt: now), to: shared.userDefaults)

        #expect(viewModel.importSharedItems() == 2)
        #expect(viewModel.tasks.map(\.title) == ["「記事」を読む", "牛乳を買う"])
        #expect(viewModel.tasks.first?.link == url)
        #expect(viewModel.tasks.first?.estimatedMinutes == 10)

        // 受け箱は空になる
        #expect(viewModel.importSharedItems() == 0)
        #expect(viewModel.tasks.count == 2)
    }

    @Test
    func suggestedTitleDropsTheSiteName() {
        let url = URL(string: "https://www.example.com/a")!
        #expect(ShareInbox.suggestedTitle(pageTitle: "SwiftUIの基本 | Example", url: url) == "「SwiftUIの基本」を読む")
        #expect(ShareInbox.suggestedTitle(pageTitle: "", url: url) == "「example.com」を読む")
        #expect(ShareInbox.suggestedTitle(pageTitle: "牛乳を買う", url: nil) == "牛乳を買う")
    }

    @Test
    func linkSurvivesSavingAndOldDataStillLoads() throws {
        let task = TaskItem(title: "読む", estimatedMinutes: 10, link: URL(string: "https://example.com")!)
        let decoded = try JSONDecoder().decode(TaskItem.self, from: JSONEncoder().encode(task))
        #expect(decoded.link == task.link)

        let legacy = #"{"id":"\#(UUID().uuidString)","title":"古い","isCompleted":false,"estimatedMinutes":10,"prerequisiteIDs":[]}"#
        let old = try JSONDecoder().decode(TaskItem.self, from: Data(legacy.utf8))
        #expect(old.link == nil)
    }

    // MARK: - ライブアクティビティ

    @Test
    func focusShowsAndEndsTheLiveActivity() throws {
        let activity = FakeFocusActivity()
        let viewModel = makeViewModel(focusActivity: activity)
        viewModel.addTask(title: "資料", estimatedMinutes: 30, priority: .medium, scheduledDate: nil, deadline: nil)
        let endsAtLaunch = activity.endCount

        viewModel.startFocus(trialMinutes: 5)
        #expect(activity.shown.last?.title == "資料")
        #expect(activity.shown.last?.isTrial == true)
        #expect(activity.shown.last?.targetEnd == now.addingTimeInterval(5 * 60))

        viewModel.continueFocus()
        #expect(activity.shown.last?.targetEnd == now.addingTimeInterval(30 * 60))

        viewModel.finishFocus(completing: false)
        #expect(activity.endCount == endsAtLaunch + 1)
    }
}
