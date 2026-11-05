import Foundation

enum TaskPriority: Int, Codable, CaseIterable {
    case low
    case medium
    case high

    var displayName: String {
        switch self {
        case .low:
            return String(localized: "低")
        case .medium:
            return String(localized: "中")
        case .high:
            return String(localized: "高")
        }
    }
}

struct TaskItem: Identifiable, Equatable, Codable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var estimatedMinutes: Int
    var priority: TaskPriority

    /// このタスクを実施する予定日
    var scheduledDate: Date?

    /// このタスクを完了すべき期限
    var deadline: Date?

    var prerequisiteIDs: [UUID]

    /// 最後に追加・編集・完了切り替えなどで触れた日時。冬眠の判定に使う
    var updatedAt: Date

    /// 完了にした日時。「今日やったこと」に使う。未完了ならnil
    var completedAt: Date?

    /// 「小さく分ける」で同じ元タスクから作られた部分に共通のID（元タスクのID）
    var splitGroupID: UUID?

    /// 「今日やりたい」の印を付けた日時。付けた日だけ推薦で優先する
    var pinnedForTodayAt: Date?

    /// 頭を使わない軽い作業か。「気が乗らない」ときの推薦に使う
    var isLight: Bool

    /// くり返しのひな形（`RecurringTask`）から作られた回なら、そのID
    var recurringID: UUID?

    /// くり返しの回の日付（その日の始まり）
    var occurrenceDate: Date?

    /// 「一歩」なら、それが属する元のタスクのID。一歩のタイトルには元のタスク名を入れない
    var parentTaskID: UUID?

    /// 集中画面で計った、実際にかかった時間（分）。見積もりの初期値を現実に近づけるのに使う
    var actualMinutes: Int?

    /// 共有シートから足したときの、元のページのURL
    var link: URL?

    init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        estimatedMinutes: Int,
        priority: TaskPriority = .medium,
        scheduledDate: Date? = nil,
        deadline: Date? = nil,
        prerequisiteIDs: [UUID] = [],
        updatedAt: Date = Date(),
        completedAt: Date? = nil,
        splitGroupID: UUID? = nil,
        pinnedForTodayAt: Date? = nil,
        isLight: Bool = false,
        recurringID: UUID? = nil,
        occurrenceDate: Date? = nil,
        parentTaskID: UUID? = nil,
        actualMinutes: Int? = nil,
        link: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.estimatedMinutes = estimatedMinutes
        self.priority = priority
        self.scheduledDate = scheduledDate
        self.deadline = deadline
        self.prerequisiteIDs = prerequisiteIDs
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.splitGroupID = splitGroupID
        self.pinnedForTodayAt = pinnedForTodayAt
        self.isLight = isLight
        self.recurringID = recurringID
        self.occurrenceDate = occurrenceDate
        self.parentTaskID = parentTaskID
        self.actualMinutes = actualMinutes
        self.link = link
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        estimatedMinutes = try container.decode(Int.self, forKey: .estimatedMinutes)

        priority = try container.decodeIfPresent(
            TaskPriority.self,
            forKey: .priority
        ) ?? .medium

        scheduledDate = try container.decodeIfPresent(
            Date.self,
            forKey: .scheduledDate
        )

        deadline = try container.decodeIfPresent(
            Date.self,
            forKey: .deadline
        )

        prerequisiteIDs = try container.decode(
            [UUID].self,
            forKey: .prerequisiteIDs
        )

        // updatedAt 追加前のデータは、読み込んだ時点から数え始める
        updatedAt = try container.decodeIfPresent(
            Date.self,
            forKey: .updatedAt
        ) ?? Date()

        completedAt = try container.decodeIfPresent(
            Date.self,
            forKey: .completedAt
        )

        splitGroupID = try container.decodeIfPresent(
            UUID.self,
            forKey: .splitGroupID
        )

        pinnedForTodayAt = try container.decodeIfPresent(
            Date.self,
            forKey: .pinnedForTodayAt
        )

        isLight = try container.decodeIfPresent(
            Bool.self,
            forKey: .isLight
        ) ?? false

        recurringID = try container.decodeIfPresent(
            UUID.self,
            forKey: .recurringID
        )

        occurrenceDate = try container.decodeIfPresent(
            Date.self,
            forKey: .occurrenceDate
        )

        parentTaskID = try container.decodeIfPresent(
            UUID.self,
            forKey: .parentTaskID
        )

        actualMinutes = try container.decodeIfPresent(
            Int.self,
            forKey: .actualMinutes
        )

        link = try container.decodeIfPresent(
            URL.self,
            forKey: .link
        )
    }
}

// MARK: - 今日やりたい・軽い作業

extension TaskItem {

    /// 「気が乗らない」ときに、軽い作業の印がなくても短い作業として扱う所要時間（分）
    static let shortTaskMinutes = 15

    /// 今日「今日やりたい」の印が付いているか
    ///
    /// - Parameter dayStartOffset: 1日の区切り（0時からずらす秒数）。4時区切りなら、深夜1時に付けた印は前の日のもの
    func isPinnedForToday(
        at now: Date,
        calendar: Calendar = .current,
        dayStartOffset: TimeInterval = 0
    ) -> Bool {
        guard !isCompleted, let pinnedForTodayAt else {
            return false
        }

        return calendar.isDate(
            pinnedForTodayAt.addingTimeInterval(-dayStartOffset),
            inSameDayAs: now.addingTimeInterval(-dayStartOffset)
        )
    }

    /// 気が乗らないときでも取りかかれる、軽いか短い作業か
    var isEasyToStart: Bool {
        isLight || estimatedMinutes <= Self.shortTaskMinutes
    }
}

// MARK: - 冬眠

extension TaskItem {

    /// この期間触れていない未完了タスクは冬眠させ、推薦と今日・明日の欄から外す
    static let dormancyInterval: TimeInterval = 60 * 60 * 24 * 14

    /// 冬眠中かどうか
    ///
    /// 期限があるタスクと、予定日が今日以降のタスクは冬眠させない。
    /// 約束した日付を見えなくすると、正直な表示にならないため。
    func isDormant(at now: Date, calendar: Calendar = .current) -> Bool {
        guard !isCompleted, deadline == nil else {
            return false
        }

        if let scheduledDate,
           scheduledDate >= calendar.startOfDay(for: now) {
            return false
        }

        return updatedAt <= now.addingTimeInterval(-Self.dormancyInterval)
    }
}
