import SwiftUI

/// 持ち越しを1回でまとめて整理する画面。1件ずつ日付を選び直さなくていいようにする
struct CarryOverView: View {

    @Environment(\.dismiss) private var dismiss

    let tasks: [TaskItem]
    let onApply: (Set<UUID>, HomeViewModel.RescheduleOption) -> Void

    @State private var selection: Set<UUID>

    init(
        tasks: [TaskItem],
        onApply: @escaping (Set<UUID>, HomeViewModel.RescheduleOption) -> Void
    ) {
        self.tasks = tasks
        self.onApply = onApply
        _selection = State(initialValue: Set(tasks.map(\.id)))
    }

    private let options: [HomeViewModel.RescheduleOption] = [
        .today, .tomorrow, .nextMonday, .clearDates, .hibernate
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(tasks) { task in
                        Button {
                            if selection.contains(task.id) {
                                selection.remove(task.id)
                            } else {
                                selection.insert(task.id)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selection.contains(task.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selection.contains(task.id) ? Color.accentColor : Color.secondary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title)
                                        .foregroundStyle(.primary)

                                    Text("所要時間：\(task.estimatedMinutes)分")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("持ち越し \(tasks.count)件")
                } footer: {
                    Text("予定どおりにいかないのは、よくあることです。まとめて置き直しましょう。")
                }

                Section("選んだ\(selection.count)件を") {
                    ForEach(options, id: \.self) { option in
                        Button(option.title) {
                            onApply(selection, option)
                            dismiss()
                        }
                        .disabled(selection.isEmpty)
                    }
                }
            }
            .navigationTitle("持ち越しを整理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(selection.count == tasks.count ? "すべて外す" : "すべて選ぶ") {
                        selection = selection.count == tasks.count ? [] : Set(tasks.map(\.id))
                    }
                }
            }
        }
    }
}

#Preview {
    CarryOverView(
        tasks: [
            TaskItem(title: "申請書を出す", estimatedMinutes: 15),
            TaskItem(title: "買い物", estimatedMinutes: 20)
        ]
    ) { _, _ in }
}
