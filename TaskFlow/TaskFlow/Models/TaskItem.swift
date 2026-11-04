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

    init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        estimatedMinutes: Int,
        priority: TaskPriority = .medium,
        scheduledDate: Date? = nil,
        deadline: Date? = nil,
        prerequisiteIDs: [UUID] = []
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.estimatedMinutes = estimatedMinutes
        self.priority = priority
        self.scheduledDate = scheduledDate
        self.deadline = deadline
        self.prerequisiteIDs = prerequisiteIDs
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
    }
}
