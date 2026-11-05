import SwiftUI

/// 今日終えたものだけを見せる。終わらなかったものの数は出さない
struct DoneTodayView: View {

    @Environment(\.dismiss) private var dismiss

    let tasks: [TaskItem]

    private var totalMinutes: Int {
        tasks.reduce(0) { $0 + $1.estimatedMinutes }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(tasks.count)件・約\(Self.formatMinutes(totalMinutes))")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("今日、ここまで進めました。")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                Section("終えたこと") {
                    ForEach(tasks) { task in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)

                            Text(task.title)

                            Spacer()

                            if let completedAt = task.completedAt {
                                Text(completedAt, format: .dateTime.hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("今日やったこと")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }

    /// 「55分」「1時間30分」
    static func formatMinutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60

        if hours == 0 {
            return "\(rest)分"
        }
        return rest == 0 ? "\(hours)時間" : "\(hours)時間\(rest)分"
    }
}

#Preview {
    DoneTodayView(tasks: [
        TaskItem(title: "請求書を送る", isCompleted: true, estimatedMinutes: 15, completedAt: Date()),
        TaskItem(title: "机の上を片づける", isCompleted: true, estimatedMinutes: 10, completedAt: Date())
    ])
}
