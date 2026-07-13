import Foundation

struct TaskItem: Identifiable, Equatable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var estimatedMinutes: Int

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
        scheduledDate: Date? = nil,
        deadline: Date? = nil,
        prerequisiteIDs: [UUID] = []
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.estimatedMinutes = estimatedMinutes
        self.scheduledDate = scheduledDate
        self.deadline = deadline
        self.prerequisiteIDs = prerequisiteIDs
    }
}
