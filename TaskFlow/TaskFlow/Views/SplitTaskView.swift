import SwiftUI

/// 大きいタスクを、順番に取りかかれる小さいタスクに分ける画面
struct SplitTaskView: View {

    @Environment(\.dismiss) private var dismiss

    let task: TaskItem
    let onSplit: ([TaskSplitPart]) -> Void

    /// 編集中の1つ分。並べ替えや件数の変更でも行を見分けられるようにIDを持たせる
    private struct EditablePart: Identifiable {
        let id = UUID()
        var part: TaskSplitPart
    }

    @State private var count: Int
    @State private var parts: [EditablePart]
    @State private var isFillingSuggestions = false

    init(
        task: TaskItem,
        onSplit: @escaping ([TaskSplitPart]) -> Void
    ) {
        self.task = task
        self.onSplit = onSplit

        let initialCount = task.estimatedMinutes >= 60 ? 3 : 2
        _count = State(initialValue: initialCount)
        _parts = State(
            initialValue: TaskSplitter.defaultParts(for: task, count: initialCount)
                .map { EditablePart(part: $0) }
        )
    }

    private var canSplit: Bool {
        parts.allSatisfy {
            !$0.part.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// 候補の分だけ、上から順に名前を入れる（残りはそのまま）
    private func fillWithSuggestions() {
        isFillingSuggestions = true

        Task {
            let base = CompletionMessages.baseTitle(of: task.title)
            let suggestions = await StepSuggester.suggestions(for: base).steps

            for (index, suggestion) in suggestions.enumerated() where index < parts.count {
                parts[index].part.title = "\(base)：\(suggestion)"
            }

            isFillingSuggestions = false
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(
                        "\(count)つに分ける",
                        value: $count,
                        in: TaskSplitter.partCountRange
                    )
                } footer: {
                    Text("上から順に取りかかれるようになります。元のタスク「\(task.title)」（\(task.estimatedMinutes)分）は、分けたタスクに置き換わります。")
                }

                Section {
                    Button {
                        fillWithSuggestions()
                    } label: {
                        if isFillingSuggestions {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("候補を考えています")
                            }
                        } else {
                            Label("候補から名前を入れる", systemImage: "wand.and.stars")
                        }
                    }
                    .disabled(isFillingSuggestions)
                }

                ForEach(Array($parts.enumerated()), id: \.element.id) { index, $item in
                    Section("\(index + 1)つ目") {
                        TextField("タスク名", text: $item.part.title)

                        Stepper(
                            "所要時間：\(item.part.estimatedMinutes)分",
                            value: $item.part.estimatedMinutes,
                            in: 5...480,
                            step: 5
                        )
                    }
                }
            }
            .navigationTitle("小さく分ける")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("分ける") {
                        onSplit(
                            parts.map { item in
                                TaskSplitPart(
                                    title: item.part.title.trimmingCharacters(in: .whitespacesAndNewlines),
                                    estimatedMinutes: item.part.estimatedMinutes
                                )
                            }
                        )
                        dismiss()
                    }
                    .disabled(!canSplit)
                }
            }
            .onChange(of: count) { _, newCount in
                parts = TaskSplitter.defaultParts(for: task, count: newCount)
                    .map { EditablePart(part: $0) }
            }
        }
    }
}

#Preview {
    SplitTaskView(
        task: TaskItem(title: "発表資料を作る", estimatedMinutes: 90)
    ) { _ in }
}
