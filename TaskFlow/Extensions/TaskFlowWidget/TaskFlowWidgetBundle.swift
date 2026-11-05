import SwiftUI
import WidgetKit

/// TaskFlow のウィジェット一式
@main
struct TaskFlowWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayPickWidget()
        FocusLiveActivityWidget()
    }
}
