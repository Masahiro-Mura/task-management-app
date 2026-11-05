import Foundation
import Testing
@testable import TaskFlow

/// 重く感じやすいタスクに、最初の一歩の案を出す
@MainActor
struct FirstStepIdeaTests {

    private let storage = TemporaryUserDefaults(prefix: "FirstStepIdeaTests")

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 10))!
    }

    /// 案を作るのに渡されたタスク名を覚えておく
    private final class SuggesterLog {
        var titles: [String] = []
    }

    private func makeViewModel(log: SuggesterLog = SuggesterLog()) -> HomeViewModel {
        let fixed = now
        return HomeViewModel(
            userDefaults: storage.userDefaults,
            seedsSampleTasks: false,
            calendar: calendar,
            now: { fixed },
            suggestSteps: { title in
                await MainActor.run { log.titles.append(title) }
                return StepSuggester.Suggestions(steps: ["目次を見る", "1ページ読む"], isFromAI: true)
            }
        )
    }

    private func task(_ title: String, in viewModel: HomeViewModel) -> TaskItem {
        viewModel.allTasks.first { $0.title == title }!
    }

    @Test
    func onlyHeavyTasksWithoutStepsGetAnIdea() {
        let viewModel = makeViewModel()
        viewModel.addTask(title: "長い", estimatedMinutes: 60, priority: .medium, scheduledDate: nil, deadline: nil)
        viewModel.addTask(title: "短い", estimatedMinutes: 10, priority: .medium, scheduledDate: nil, deadline: nil)

        #expect(viewModel.shouldSuggestFirstStep(for: task("長い", in: viewModel)))
        #expect(!viewModel.shouldSuggestFirstStep(for: task("短い", in: viewModel)))

        // 一歩を決めたら、もう出さない（一歩そのものにも出さない）
        viewModel.addStep(to: task("長い", in: viewModel), title: "一歩", minutes: 5)
        #expect(!viewModel.shouldSuggestFirstStep(for: task("長い", in: viewModel)))
        #expect(!viewModel.shouldSuggestFirstStep(for: task("一歩", in: viewModel)))
    }

    @Test
    func aShortTaskPutOffOnceGetsAnIdeaToo() {
        let viewModel = makeViewModel()
        viewModel.addTask(title: "短い", estimatedMinutes: 10, priority: .high, scheduledDate: nil, deadline: nil)

        viewModel.skipRecommendation()
        #expect(viewModel.shouldSuggestFirstStep(for: task("短い", in: viewModel)))
    }

    @Test
    func ideasAreMadeOnceAndRemadeWhenTheNameChanges() async {
        let log = SuggesterLog()
        let viewModel = makeViewModel(log: log)
        viewModel.addTask(title: "論文を読む", estimatedMinutes: 60, priority: .medium, scheduledDate: nil, deadline: nil)

        await viewModel.loadFirstStepIdeas(for: task("論文を読む", in: viewModel))
        await viewModel.loadFirstStepIdeas(for: task("論文を読む", in: viewModel))
        #expect(log.titles == ["論文を読む"])
        #expect(viewModel.firstStepIdeas[task("論文を読む", in: viewModel).id]?.steps.first == "目次を見る")

        var renamed = task("論文を読む", in: viewModel)
        renamed.title = "本を読む"
        viewModel.updateTask(renamed)
        await viewModel.loadFirstStepIdeas(for: task("本を読む", in: viewModel))
        #expect(log.titles == ["論文を読む", "本を読む"])
    }

    @Test
    func startingFromAnIdeaAddsAFiveMinuteStepAndFocusesOnIt() throws {
        let viewModel = makeViewModel()
        viewModel.addTask(title: "論文を読む", estimatedMinutes: 60, priority: .medium, scheduledDate: nil, deadline: nil)
        let before = viewModel.allTasks

        let stepID = try #require(viewModel.startWithFirstStep("目次を見る", of: task("論文を読む", in: viewModel)))
        let step = try #require(viewModel.allTasks.first { $0.id == stepID })
        #expect(step.title == "目次を見る")
        #expect(step.estimatedMinutes == HomeViewModel.ideaStepMinutes)
        #expect(step.parentTaskID == task("論文を読む", in: viewModel).id)
        #expect(viewModel.focusSession?.taskID == stepID)

        // 一度の「元に戻す」で、一歩も集中もなかったことになる
        viewModel.undo()
        #expect(viewModel.allTasks == before)
        #expect(viewModel.focusSession == nil)
    }

    @Test
    func lightModeStaysNamedTheSame() {
        // 状態はラベルでなく、オン・オフで示す（ここでは切り替えが効くことだけ確かめる）
        let viewModel = makeViewModel()
        viewModel.setPrefersLight(true)
        #expect(viewModel.prefersLight)
        viewModel.setPrefersLight(false)
        #expect(!viewModel.prefersLight)
    }
}
