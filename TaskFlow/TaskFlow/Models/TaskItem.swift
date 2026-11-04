import Foundation

enum TaskPriority: Int, Codable, CaseIterable {
    case low
    case medium
    case high

    var displayName: String {
        switch self {
        case .low:
            return "低"
        case .medium:
            return "中"
        case .high:
            return "高"
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

    init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        estimatedMinutes: Int,
        priority: TaskPriority = .medium,
        scheduledDate: Date? = nil,
        deadline: Date? = nil,
        prerequisiteIDs: [UUID] = [],
        updatedAt: Date = Date()
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
