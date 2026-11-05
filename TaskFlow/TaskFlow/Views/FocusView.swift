import SwiftUI

/// 推薦されたタスク1つに集中する画面。経過時間と「完了」だけを出す
///
/// 「5分だけやる」のときは5分を目安にし、5分たったら続けるか、ここまでにするかを選べる。
struct FocusView: View {

    let task: TaskItem
    let startedAt: Date

    /// 「5分だけやる」のときの目安（分）。nilならタスクの所要時間
    var trialMinutes: Int? = nil

    let onComplete: () -> Void
    let onStop: () -> Void
    var onContinue: () -> Void = {}

    private var targetMinutes: Int {
        trialMinutes ?? task.estimatedMinutes
    }

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            let elapsed = max(context.date.timeIntervalSince(startedAt), 0)
            let reachedTarget = elapsed >= TimeInterval(targetMinutes * 60)

            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 12) {
                    Text(trialMinutes == nil ? "取りかかり中" : "まずは\(targetMinutes)分だけ")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(task.title)
                        .font(.title)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 8) {
                    Text(Self.format(elapsed))
                        .font(.system(size: 64, weight: .light, design: .rounded))
                        .monospacedDigit()

                    Text(statusText(reachedTarget: reachedTarget))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                actions(reachedTarget: reachedTarget)
            }
            .padding(24)
            .animation(.easeInOut, value: reachedTarget)
        }
    }

    /// 目安を過ぎても責めず、区切りをつけてよいことだけを伝える
    private func statusText(reachedTarget: Bool) -> String {
        switch (trialMinutes, reachedTarget) {
        case (nil, false):
            return "目安 \(targetMinutes)分"
        case (nil, true):
            return "目安の\(targetMinutes)分を過ぎました。区切りのいいところで終えて大丈夫です"
        case (_?, false):
            return "\(targetMinutes)分たったら、続けるかどうか選べます"
        case (_?, true):
            return "\(targetMinutes)分、手をつけられました。続けますか？"
        }
    }

    @ViewBuilder
    private func actions(reachedTarget: Bool) -> some View {
        VStack(spacing: 12) {
            if trialMinutes != nil, reachedTarget {
                Button(action: onContinue) {
                    Label("続ける", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                HStack(spacing: 12) {
                    Button(action: onStop) {
                        Text("ここまでにする")
                            .frame(maxWidth: .infinity)
                    }

                    Button(action: onComplete) {
                        Label("完了", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else {
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
        task: TaskItem(title: "部屋を片づける", estimatedMinutes: 90),
        startedAt: Date().addingTimeInterval(-301),
        trialMinutes: 5,
        onComplete: {},
        onStop: {}
    )
}
