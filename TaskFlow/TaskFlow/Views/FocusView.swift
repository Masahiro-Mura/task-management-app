import SwiftUI

/// 推薦されたタスク1つに集中する画面。経過時間と「完了」だけを出す
struct FocusView: View {

    let task: TaskItem
    let startedAt: Date
    let onComplete: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Text("取りかかり中")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(task.title)
                    .font(.title)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
            }

            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                let elapsed = max(context.date.timeIntervalSince(startedAt), 0)

                VStack(spacing: 8) {
                    Text(Self.format(elapsed))
                        .font(.system(size: 64, weight: .light, design: .rounded))
                        .monospacedDigit()

                    // 目安を過ぎても責めず、区切りをつけてよいことだけを伝える
                    Text(
                        elapsed > TimeInterval(task.estimatedMinutes * 60)
                            ? "目安の\(task.estimatedMinutes)分を過ぎました。区切りのいいところで終えて大丈夫です"
                            : "目安 \(task.estimatedMinutes)分"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }
            }

            Spacer()

            VStack(spacing: 12) {
                Button(action: onComplete) {
                    Label("完了", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("ここで中断する", action: onStop)
                    .controlSize(.large)
            }
        }
        .padding(24)
    }

    /// 経過時間を「12:34」や「1:02:03」の形にする
    static func format(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    FocusView(
        task: TaskItem(title: "発表資料を作る（1/3）", estimatedMinutes: 30),
        startedAt: Date().addingTimeInterval(-754),
        onComplete: {},
        onStop: {}
    )
}
