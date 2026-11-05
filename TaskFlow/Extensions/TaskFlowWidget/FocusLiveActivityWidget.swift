import ActivityKit
import SwiftUI
import WidgetKit

/// 集中しているあいだのロック画面とダイナミックアイランド
///
/// 経過時間を数え上げる（残り時間で急かさない）。目安の時間は小さく添えるだけ。
struct FocusLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            lockScreen(context)
                .padding(16)
                .activityBackgroundTint(Color.blue.opacity(0.12))
                .widgetURL(WidgetLink.focus(taskID: context.attributes.taskID, trialMinutes: nil).url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.attributes.isTrial ? "timer" : "play.fill")
                        .foregroundStyle(.blue)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    elapsed(context)
                        .font(.title3.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.taskTitle)
                            .font(.headline)
                            .lineLimit(1)
                        Text(targetText(context))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: context.attributes.isTrial ? "timer" : "play.fill")
                    .foregroundStyle(.blue)
            } compactTrailing: {
                elapsed(context)
                    .monospacedDigit()
                    .frame(maxWidth: 48)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(.blue)
            }
            .widgetURL(WidgetLink.focus(taskID: context.attributes.taskID, trialMinutes: nil).url)
        }
    }

    private func lockScreen(_ context: ActivityViewContext<FocusActivityAttributes>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: context.attributes.isTrial ? "timer" : "play.fill")
                .font(.title2)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.taskTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(targetText(context))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            elapsed(context)
                .font(.title2.monospacedDigit().weight(.semibold))
        }
    }

    /// 始めてからの時間（数え上げ）
    private func elapsed(_ context: ActivityViewContext<FocusActivityAttributes>) -> some View {
        Text(context.attributes.startedAt, style: .timer)
            .multilineTextAlignment(.trailing)
    }

    private func targetText(_ context: ActivityViewContext<FocusActivityAttributes>) -> String {
        let minutes = Int(context.state.targetEnd.timeIntervalSince(context.attributes.startedAt) / 60)
        return context.attributes.isTrial ? "\(minutes)分だけ" : "目安 \(minutes)分"
    }
}
