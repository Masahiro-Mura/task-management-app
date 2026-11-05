import SwiftUI

/// 大きいタスクの「最初の一歩」だけを決める画面
///
/// 全部を分けると、それ自体が大きな作業になってしまう。最初の5分で何をするかだけ決めれば、推薦に出る。
struct FirstStepView: View {

    @Environment(\.dismiss) private var dismiss

    let task: TaskItem
    let onSave: (String, Int) -> Void

    @State private var stepTitle = ""
    @State private var minutes = HomeViewModel.defaultFirstStepMinutes
    @State private var suggestions: [String] = []
    @State private var suggestionsAreFromAI = false
    @State private var isLoadingSuggestions = true

    private var canSave: Bool {
        !stepTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("例：机の上だけ片づける", text: $stepTitle)

                    Stepper(
                        "所要時間：\(minutes)分",
                        value: $minutes,
                        in: 5...30,
                        step: 5
                    )
                } header: {
                    Text("「\(CompletionMessages.baseTitle(of: task.title))」の最初の5分で何をする？")
                } footer: {
                    Text("決めるのは最初の一歩だけで大丈夫です。終わったら、次の一歩を聞きます。")
                }

                Section {
                    if isLoadingSuggestions {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("候補を考えています")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                stepTitle = suggestion
                            } label: {
                                HStack {
                                    Text(suggestion)
                                        .foregroundStyle(.primary)

                                    Spacer()

                                    if stepTitle == suggestion {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("候補（タップで入ります）")
                } footer: {
                    if !isLoadingSuggestions {
                        Text(
                            suggestionsAreFromAI
                                ? "候補は端末内のAIで作りました。データは端末の外に出ません。"
                                : "候補はタスク名の言葉から選んだ例です。"
                        )
                    }
                }
            }
            .navigationTitle("最初の一歩")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("決める") {
                        onSave(stepTitle, minutes)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .task {
                let result = await StepSuggester.suggestions(for: CompletionMessages.baseTitle(of: task.title))
                suggestions = result.steps
                suggestionsAreFromAI = result.isFromAI
                isLoadingSuggestions = false
            }
        }
    }
}

#Preview {
    FirstStepView(task: TaskItem(title: "部屋の片付け", estimatedMinutes: 90)) { _, _ in }
}
