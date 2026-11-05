import SwiftUI

/// 大きいタスクの「一歩」の一覧。ホームには最初の一歩だけを出し、2歩目以降はここで見る
///
/// 先の一歩まで一度に見えると気が重くなるので、ここは自分から開いたときだけ見る場所にする。
struct StepsView: View {

    @Environment(\.dismiss) private var dismiss

    @ObservedObject var viewModel: HomeViewModel
    let parentID: UUID

    @State private var newStepTitle = ""
    @State private var newStepMinutes = HomeViewModel.defaultFirstStepMinutes
    @State private var suggestions: [String] = []
    @State private var suggestionsAreFromAI = false
    @State private var editMode: EditMode = .inactive

    private var parent: TaskItem? {
        viewModel.tasks.first { $0.id == parentID }
    }

    private var doneSteps: [TaskItem] {
        viewModel.steps(of: parentID).filter(\.isCompleted)
    }

    private var openSteps: [TaskItem] {
        viewModel.steps(of: parentID).filter { !$0.isCompleted }
    }

    private var canAdd: Bool {
        !newStepTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                if !doneSteps.isEmpty {
                    Section("済んだ一歩") {
                        ForEach(Array(doneSteps.enumerated()), id: \.element.id) { offset, step in
                            stepRow(step, number: offset + 1)
                        }
                    }
                }

                Section {
                    if openSteps.isEmpty {
                        Text("まだ決めていません。下で最初の一歩を足してください。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(openSteps.enumerated()), id: \.element.id) { offset, step in
                            stepRow(step, number: doneSteps.count + offset + 1)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        viewModel.deleteStep(step)
                                    } label: {
                                        Label("取り消す", systemImage: "trash")
                                    }
                                }
                        }
                        .onMove { source, destination in
                            viewModel.moveOpenSteps(of: parentID, fromOffsets: source, toOffset: destination)
                        }
                    }
                } header: {
                    Text("これからの一歩")
                } footer: {
                    Text("ホームには、いちばん上の一歩だけが出ます。順番は左上の「並べ替え」、取り消しは左へスワイプ。")
                }

                Section {
                    TextField("次の一歩（例：机の上だけ片づける）", text: $newStepTitle)
                        .submitLabel(.done)
                        .onSubmit(addStep)

                    Stepper("所要時間：\(newStepMinutes)分", value: $newStepMinutes, in: 5...30, step: 5)

                    Button("一歩を足す", action: addStep)
                        .disabled(!canAdd)
                } header: {
                    Text("一歩を足す")
                }

                if !suggestions.isEmpty {
                    Section {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                newStepTitle = suggestion
                            } label: {
                                HStack {
                                    Text(suggestion)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if newStepTitle == suggestion {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("候補（タップで入ります）")
                    } footer: {
                        Text(
                            suggestionsAreFromAI
                                ? "候補は端末内のAIで作りました。データは端末の外に出ません。"
                                : "候補はタスク名の言葉から選んだ例です。"
                        )
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle(parent.map { CompletionMessages.baseTitle(of: $0.title) } ?? String(localized: "一歩"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // 英語の「Edit」にならないよう、自分で言葉を決めたボタンにする
                    Button(editMode.isEditing ? "完了" : "並べ替え") {
                        withAnimation {
                            editMode = editMode.isEditing ? .inactive : .active
                        }
                    }
                    .disabled(openSteps.count < 2)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
            .task {
                guard let parent else {
                    return
                }
                let result = await StepSuggester.suggestions(for: CompletionMessages.baseTitle(of: parent.title))
                suggestions = result.steps
                suggestionsAreFromAI = result.isFromAI
            }
        }
    }

    private func stepRow(_ step: TaskItem, number: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(number)歩目")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(step.isCompleted ? Color.secondary : Color.accentColor)
                .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .strikethrough(step.isCompleted)
                    .foregroundStyle(step.isCompleted ? .secondary : .primary)

                Text("\(step.estimatedMinutes)分")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if step.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func addStep() {
        guard canAdd, let parent else {
            return
        }

        viewModel.addStep(to: parent, title: newStepTitle, minutes: newStepMinutes)
        newStepTitle = ""
    }
}
