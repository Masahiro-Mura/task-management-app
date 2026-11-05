import SwiftUI
import WidgetKit

// MARK: - タイムライン

/// アプリが書いた「今の1つ」の写し（`WidgetSnapshot`）を読むだけ。推薦はアプリが出す
struct TodayPickProvider: TimelineProvider {

    struct Entry: TimelineEntry {
        let date: Date
        let snapshot: WidgetSnapshot?
    }

    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), snapshot: context.isPreview ? .placeholder : load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // アプリが推薦を変えるたびに描き直すので、ここでは念のため30分ごとに読み直すだけ
        let entry = Entry(date: Date(), snapshot: load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }

    private func load() -> WidgetSnapshot? {
        SharedStore.defaults.flatMap(WidgetSnapshot.load(from:))
    }
}

// MARK: - ウィジェット

/// ホーム画面とロック画面に「今の1つ」を出す
struct TodayPickWidget: Widget {
    let kind = "TodayPickWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayPickProvider()) { entry in
            TodayPickView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("今の1つ")
        .description("今の空き時間で取りかかる1つを出します。")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryRectangular, .accessoryInline, .accessoryCircular
        ])
    }
}

struct TodayPickView: View {
    @Environment(\.widgetFamily) private var family

    let entry: TodayPickProvider.Entry

    private var pick: WidgetSnapshot.Pick? {
        entry.snapshot?.pick
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            inline
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        case .systemMedium:
            medium
        default:
            small
        }
    }

    // MARK: ロック画面

    private var inline: some View {
        Group {
            if let pick {
                Label("\(pick.title)・\(pick.minutes)分", systemImage: "sparkles")
            } else {
                Label(emptyText, systemImage: "checkmark")
            }
        }
        .widgetURL(WidgetLink.home.url)
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let pick {
                VStack(spacing: 0) {
                    Text("\(pick.minutes)")
                        .font(.title3.weight(.semibold))
                    Text("分")
                        .font(.caption2)
                }
            } else {
                Image(systemName: "checkmark")
                    .font(.title3)
            }
        }
        .widgetURL(pick.map { WidgetLink.focus(taskID: $0.taskID, trialMinutes: 5).url } ?? WidgetLink.home.url)
        .accessibilityLabel(pick.map { "今の1つ、\($0.title)、\($0.minutes)分" } ?? emptyText)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("今の1つ", systemImage: "sparkles")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let pick {
                Text(pick.title)
                    .font(.headline)
                    .lineLimit(2)
                Text("\(pick.minutes)分・\(pick.shortReason)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(emptyText)
                    .font(.headline)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(WidgetLink.home.url)
    }

    // MARK: ホーム画面

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("今の1つ", systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(.blue)

            if let pick {
                Text(pick.title)
                    .font(.headline)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)

                pills(for: pick)
            } else {
                Spacer(minLength: 0)
                Text(emptyText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(WidgetLink.home.url)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label("今の1つ", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.blue)

                if let pick {
                    Text(pick.title)
                        .font(.headline)
                        .lineLimit(3)

                    Spacer(minLength: 0)

                    pills(for: pick)
                } else {
                    Spacer(minLength: 0)
                    Text(emptyText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // 押すとアプリが開いて、そのまま始まる
            VStack(spacing: 8) {
                if let pick {
                    Link(destination: WidgetLink.focus(taskID: pick.taskID, trialMinutes: nil).url) {
                        actionLabel("始める", systemImage: "play.fill", prominent: true)
                    }
                    Link(destination: WidgetLink.focus(taskID: pick.taskID, trialMinutes: 5).url) {
                        actionLabel("5分だけ", systemImage: "timer", prominent: false)
                    }
                } else {
                    Link(destination: WidgetLink.add.url) {
                        actionLabel("追加", systemImage: "plus", prominent: true)
                    }
                }
            }
            .frame(width: 104)
        }
        .widgetURL(WidgetLink.home.url)
    }

    private func pills(for pick: WidgetSnapshot.Pick) -> some View {
        HStack(spacing: 4) {
            Text("\(pick.minutes)分")
            if let step = pick.stepLabel {
                Text("・\(step)")
            }
            Text("・\(pick.shortReason)")
                .foregroundStyle(.blue)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func actionLabel(_ title: String, systemImage: String, prominent: Bool) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 40)
            .foregroundStyle(prominent ? Color.white : Color.blue)
            .background(prominent ? Color.blue : Color.blue.opacity(0.12), in: Capsule())
    }

    private var emptyText: String {
        guard let snapshot = entry.snapshot else {
            return "TaskFlow を開いてください"
        }
        return snapshot.emptyMessage
    }
}

#Preview(as: .systemMedium) {
    TodayPickWidget()
} timeline: {
    TodayPickProvider.Entry(date: .now, snapshot: .placeholder)
}
