import Foundation
import Testing
@testable import TaskFlow

/// どの操作も、すぐ「元に戻す」で戻せる
@MainActor
struct UndoEverythingTests {

    /// 操作ごとに、まっさらな保存先を使う（前の操作の結果を持ち越さないように）
    private final class Storages {
        var all: [TemporaryUserDefaults] = []

        func make() -> TemporaryUserDefaults {
            let storage = TemporaryUserDefaults(prefix: "UndoEverythingTests")
            all.append(storage)
            return storage
        }
    }

    private let storages = Storages()

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 10))!
    }

    /// タスク2つ・一歩・くり返し・保管が1つずつある状態
    private func makeViewModel(storage: TemporaryUserDefaults? = nil) -> HomeViewModel {
        let fixed = now
        let viewModel = HomeViewModel(
            userDefaults: (storage ?? storages.make()).userDefaults,
            seedsSampleTasks: false,
            calendar: calendar,
            now: { fixed }
        )
        viewModel.addTask(title: "A", estimatedMinutes: 10, priority: .high, scheduledDate: nil, deadline: nil)
        viewModel.addTask(title: "B", estimatedMinutes: 20, priority: .medium, scheduledDate: fixed, deadline: nil)
        viewModel.addStep(to: task("B", in: viewModel), title: "B1", minutes: 10)
        viewModel.addRecurring(title: "毎日の", estimatedMinutes: 5, recurrence: Recurrence(rule: .daily))
        viewModel.addTask(title: "しまう", estimatedMinutes: 10, priority: .low, scheduledDate: nil, deadline: nil)
        viewModel.letGo([task("しまう", in: viewModel).id])
        viewModel.dismissUndo()
        return viewModel
    }

    private func task(_ title: String, in viewModel: HomeViewModel) -> TaskItem {
        viewModel.allTasks.first { $0.title == title }!
    }

    private struct Snapshot: Equatable {
        var tasks: [TaskItem]
        var recurring: [RecurringTask]
        var archived: [TaskItem]
        var recommendedID: UUID?
        var skipped: Int
        var focusing: Bool
    }

    private func snapshot(_ viewModel: HomeViewModel) -> Snapshot {
        Snapshot(
            tasks: viewModel.allTasks,
            recurring: viewModel.recurringTasks,
            archived: viewModel.archivedTasks,
            recommendedID: viewModel.recommendation?.task.id,
            skipped: viewModel.skippedTaskCount,
            focusing: viewModel.focusSession != nil
        )
    }

    /// 操作すると中身が変わり、「元に戻す」を押すと、操作の前とまったく同じに戻る
    private func expectUndoes(
        _ name: String,
        prepare: (HomeViewModel) -> Void = { _ in },
        _ action: (HomeViewModel) throws -> Void
    ) rethrows {
        let viewModel = makeViewModel()
        prepare(viewModel)
        viewModel.dismissUndo()
        let before = snapshot(viewModel)

        try action(viewModel)
        #expect(snapshot(viewModel) != before, "\(name): 何も変わっていない")
        #expect(viewModel.undoEntry != nil, "\(name): 「元に戻す」が出ていない")

        viewModel.undo()
        #expect(snapshot(viewModel) == before, "\(name): 元に戻っていない")
        #expect(viewModel.undoEntry == nil, "\(name)")
    }

    @Test
    func everyActionCanBeUndone() throws {
        expectUndoes("完了") { $0.completeRecommendation() }
        expectUndoes("あとで") { $0.skipRecommendation() }
        expectUndoes("一覧の完了") { $0.toggleCompletion(for: task("B1", in: $0)) }
        expectUndoes("未完了に戻す", prepare: { $0.toggleCompletion(for: task("A", in: $0)) }) {
            $0.toggleCompletion(for: task("A", in: $0))
        }
        expectUndoes("削除") { $0.deleteTask(task("B", in: $0)) }
        expectUndoes("一歩の削除") { $0.deleteStep(task("B1", in: $0)) }
        expectUndoes("一歩を足す") { $0.addStep(to: task("A", in: $0), title: "A1", minutes: 5) }
        expectUndoes("一歩の並べ替え", prepare: { $0.addStep(to: task("B", in: $0), title: "B2", minutes: 5) }) {
            $0.moveOpenSteps(of: task("B", in: $0).id, fromOffsets: IndexSet(integer: 1), toOffset: 0)
        }
        expectUndoes("1行で足す") { _ = $0.quickAdd("C 15分") }
        expectUndoes("足す") { $0.addTask(title: "D", estimatedMinutes: 10, priority: .medium, scheduledDate: nil, deadline: nil) }
        expectUndoes("編集") { viewModel in
            var edited = task("A", in: viewModel)
            edited.title = "A'"
            viewModel.updateTask(edited)
        }
        expectUndoes("今日やりたい") { $0.togglePinnedForToday(task("A", in: $0)) }
        expectUndoes("明日に") { $0.reschedule([task("B", in: $0).id], to: .tomorrow) }
        expectUndoes("冬眠") { $0.hibernate(task("A", in: $0)) }
        expectUndoes("起こす", prepare: { $0.hibernate(task("A", in: $0)) }) { $0.wakeTask(task("A", in: $0)) }
        expectUndoes("小さく分ける") { viewModel in
            viewModel.splitTask(
                task("A", in: viewModel),
                into: [TaskSplitPart(title: "A-1", estimatedMinutes: 5), TaskSplitPart(title: "A-2", estimatedMinutes: 5)]
            )
        }
        expectUndoes("優先度を中に") { $0.lowerPriority(of: task("A", in: $0).id) }
        expectUndoes("手放す") { $0.letGo([task("A", in: $0).id]) }
        expectUndoes("保管から戻す") { $0.restoreArchived($0.archivedTasks[0]) }
        expectUndoes("保管から消す") { $0.deleteArchived($0.archivedTasks[0]) }
        expectUndoes("くり返しを足す") { $0.addRecurring(title: "週の", estimatedMinutes: 5, recurrence: Recurrence(rule: .weekly(weekdays: [2]))) }
        expectUndoes("くり返しを変える") { viewModel in
            var recurring = viewModel.recurringTasks[0]
            recurring.title = "毎日のX"
            viewModel.updateRecurring(recurring)
        }
        expectUndoes("くり返しをやめる") { $0.deleteRecurring($0.recurringTasks[0]) }
        expectUndoes("今回はお休み") { $0.skipOccurrence(task("毎日の", in: $0)) }
        expectUndoes("あとでを取り消す", prepare: { $0.skipRecommendation() }) { $0.clearSkips() }
        expectUndoes("集中の中断", prepare: { $0.startFocus() }) { $0.finishFocus(completing: false) }
        expectUndoes("集中から完了", prepare: { $0.startFocus() }) { $0.finishFocus(completing: true) }
        expectUndoes("例を入れる") { $0.finishOnboarding(addExamples: true) }
        try expectUndoes("読み込み") { viewModel in
            let other = HomeViewModel(
                userDefaults: storages.make().userDefaults,
                seedsSampleTasks: false
            )
            other.addTask(title: "よそ", estimatedMinutes: 10, priority: .medium, scheduledDate: nil, deadline: nil)
            try viewModel.importBackup(other.makeBackup())
        }
    }

    @Test
    func savingWithALoweredPriorityUndoesBothAtOnce() {
        let viewModel = makeViewModel()
        let before = viewModel.allTasks
        var edited = task("B", in: viewModel)
        edited.priority = .high

        viewModel.updateTask(edited, lowering: task("A", in: viewModel).id)
        #expect(task("A", in: viewModel).priority == .medium)
        #expect(task("B", in: viewModel).priority == .high)

        viewModel.undo()
        #expect(viewModel.allTasks == before)
    }

    @Test
    func nothingChangedMeansNoUndo() {
        let viewModel = makeViewModel()
        _ = viewModel.quickAdd("   ")
        viewModel.clearSkips()
        #expect(viewModel.undoEntry == nil)
    }

    @Test
    func aNewActionReplacesTheUndo() {
        let viewModel = makeViewModel()
        viewModel.completeRecommendation()
        viewModel.togglePinnedForToday(task("B", in: viewModel))
        #expect(viewModel.undoEntry?.message == "「B」を今日やりたいにしました")

        // 戻るのは直前の1つだけ
        viewModel.undo()
        #expect(task("A", in: viewModel).isCompleted)
        #expect(!task("B", in: viewModel).isPinnedForToday(at: now, calendar: calendar))
    }

    @Test
    func undoIsKeptAcrossRelaunchesOnlyAsSavedData() {
        // 戻した結果は保存される（もう一度開いても戻ったまま）
        let storage = storages.make()
        let viewModel = makeViewModel(storage: storage)
        viewModel.deleteTask(task("A", in: viewModel))
        viewModel.undo()

        let fixed = now
        let reopened = HomeViewModel(userDefaults: storage.userDefaults, seedsSampleTasks: false, calendar: calendar, now: { fixed })
        #expect(reopened.allTasks.contains { $0.title == "A" })
    }

    @Test
    func skippedTasksCanBeBroughtBackAnytime() {
        let viewModel = makeViewModel()
        viewModel.skipRecommendation()
        viewModel.dismissUndo()
        #expect(viewModel.skippedTaskCount == 1)

        viewModel.clearSkips()
        #expect(viewModel.skippedTaskCount == 0)
        #expect(viewModel.recommendation?.task.title == "A")
    }
}
