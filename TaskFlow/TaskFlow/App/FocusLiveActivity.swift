import ActivityKit
import Foundation

/// 集中のライブアクティビティを出し入れする（テストでは何もしない偽物を渡せる）
protocol FocusActivityPresenting {
    /// 出す。すでに出ていれば中身を入れ替える
    func show(_ attributes: FocusActivityAttributes, targetEnd: Date)

    /// 下げる
    func end()
}

/// ActivityKit を使う本物
///
/// ライブアクティビティを出すには、アプリの Info に `NSSupportsLiveActivities = YES` が要る。
/// 設定がないときや、ユーザーがオフにしているときは何もしない。
struct SystemFocusActivity: FocusActivityPresenting {

    func show(_ attributes: FocusActivityAttributes, targetEnd: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }

        let state = FocusActivityAttributes.ContentState(targetEnd: targetEnd)
        let content = ActivityContent(state: state, staleDate: nil)
        let running = Activity<FocusActivityAttributes>.activities

        // 同じ集中（同じタスク・同じ開始）なら、目安だけ入れ替える
        if let current = running.first(where: {
            $0.attributes.taskID == attributes.taskID && $0.attributes.startedAt == attributes.startedAt
        }) {
            Task {
                await current.update(content)
            }
            return
        }

        endAll(running)
        _ = try? Activity.request(attributes: attributes, content: content)
    }

    func end() {
        endAll(Activity<FocusActivityAttributes>.activities)
    }

    private func endAll(_ activities: [Activity<FocusActivityAttributes>]) {
        for activity in activities {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
