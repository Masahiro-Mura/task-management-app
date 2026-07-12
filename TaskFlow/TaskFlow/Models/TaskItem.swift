import Foundation

struct TaskItem: Identifiable, Equatable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var estimatedMinutes: Int
    var deadline: Date?
    var prerequisiteIDs: [UUID]

    init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        estimatedMinutes: Int,
        deadline: Date? = nil,
        prerequisiteIDs: [UUID] = []
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.estimatedMinutes = estimatedMinutes
        self.deadline = deadline
        self.prerequisiteIDs = prerequisiteIDs
    }
}
