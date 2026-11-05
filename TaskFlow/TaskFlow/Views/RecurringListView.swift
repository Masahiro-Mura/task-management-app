import SwiftUI

/// くり返すタスクの一覧。ここで中身を変えたり、くり返しをやめたりする
struct RecurringListView: View {

    let recurringTasks: [RecurringTask]
    let onUpdate: (RecurringTask) -> Void
    let onDelete: (RecurringTask) -> Void

    @State private var editing: RecurringTask?
    @State private var deleting: RecurringTask?

    var body: some View {
        List {
            if recurringTasks.isEmpty {
                ContentUnavailableView(
                    "くり返すタスクはまだありません",
                    systemImage: "repeat",
                    description: Text("ホームの入力欄に「毎週月曜にゴミ出し」のように書くか、「＋」の画面の「くり返し」から追加できます。")
                )
            } else {
                ForEach(recurringTasks) { recurring in
                    Button {
                        editing = recurring
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(recurring.title)
                                .foregroundStyle(.primary)

                            Text("\(recurring.recurrence.summary)・\(recurring.estimatedMinutes)分")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleting = recurring
                        } label: {
                            Label("やめる", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("くり返し")
        .sheet(item: $editing) { recurring in
            RecurringEditView(recurring: recurring, onSave: onUpdate)
        }
        .alert(
            "このくり返しをやめますか？",
            isPresented: Binding(
                get: { deleting != nil },
                set: { if !$0 { deleting = nil } }
            ),
            presenting: deleting
        ) { recurring in
            Button("やめる", role: .destructive) {
                onDelete(recurring)
                deleting = nil
            }

            Button("キャンセル", role: .cancel) {
                deleting = nil
            }
        } message: { recurring in
            Text("「\(recurring.title)」のまだ終えていない回も消えます。終えた回は残ります。")
        }
    }
}

/// くり返すタスクの中身を変える画面
struct RecurringEditView: View {

    @Environment(\.dismiss) private var dismiss

    let recurring: RecurringTask
    let onSave: (RecurringTask) -> Void

    @State private var title: String
    @State private var estimatedMinutes: Int
    @State private var isLight: Bool
    @State private var recurrence: Recurrence?

    init(recurring: RecurringTask, onSave: @escaping (RecurringTask) -> Void) {
        self.recurring = recurring
        self.onSave = onSave
        _title = State(initialValue: recurring.title)
        _estimatedMinutes = State(initialValue: recurring.estimatedMinutes)
        _isLight = State(initialValue: recurring.isLight)
        _recurrence = State(initialValue: recurring.recurrence)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("タスク") {
                    TextField("タスク名", text: $title)

                    Stepper(
                        "所要時間：\(estimatedMinutes)分",
                        value: $estimatedMinutes,
                        in: 5...480,
                        step: 5
                    )

                    Toggle("頭を使わない軽い作業", isOn: $isLight)
                }

                RecurrenceSection(recurrence: $recurrence, allowsNone: false)
            }
            .navigationTitle("くり返しを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var updated = recurring
                        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.estimatedMinutes = estimatedMinutes
                        updated.isLight = isLight
                        if let recurrence {
                            updated.recurrence = recurrence
                        }
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
