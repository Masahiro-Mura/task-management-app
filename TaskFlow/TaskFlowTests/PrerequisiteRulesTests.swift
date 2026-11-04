import Foundation
import Testing
@testable import TaskFlow

@MainActor
struct PrerequisiteRulesTests {

    private func selectableTitles(
        for task: TaskItem,
        in tasks: [TaskItem]
    ) -> [String] {
        PrerequisiteRules.selectablePrerequisites(for: task, in: tasks).map(\.title)
    }

    @Test
    func excludesTheTaskItself() {
        let task = TaskItem(title: "自分", estimatedMinutes: 10)
        let other = TaskItem(title: "ほか", estimatedMinutes: 10)

        #expect(selectableTitles(for: task, in: [task, other]) == ["ほか"])
    }

    @Test
    func excludesDirectAndIndirectDependents() {
        // A ← B ← C（CはBを、BはAを前提にしている）。Aの前提にBやCを選ぶと循環する
        let a = TaskItem(title: "A", estimatedMinutes: 10)
        let b = TaskItem(title: "B", estimatedMinutes: 10, prerequisiteIDs: [a.id])
        let c = TaskItem(title: "C", estimatedMinutes: 10, prerequisiteIDs: [b.id])
        let unrelated = TaskItem(title: "無関係", estimatedMinutes: 10)

        let tasks = [a, b, c, unrelated]

        #expect(selectableTitles(for: a, in: tasks) == ["無関係"])
        #expect(selectableTitles(for: c, in: tasks) == ["A", "B", "無関係"])
        #expect(PrerequisiteRules.dependents(of: a.id, in: tasks) == [b.id, c.id])
    }

    @Test
    func keepsCompletedTaskOnlyWhenAlreadySelected() {
        let doneSelected = TaskItem(title: "済み・選択中", isCompleted: true, estimatedMinutes: 10)
        let doneOther = TaskItem(title: "済み", isCompleted: true, estimatedMinutes: 10)
        let task = TaskItem(
            title: "本体",
            estimatedMinutes: 10,
            prerequisiteIDs: [doneSelected.id]
        )

        #expect(selectableTitles(for: task, in: [doneSelected, doneOther, task]) == ["済み・選択中"])
    }
}
