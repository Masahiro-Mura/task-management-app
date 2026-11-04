import Foundation
import Testing
@testable import TaskFlow

@MainActor
struct TaskItemTests {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    /// 2026-11-05 12:00（日本時間）
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 12))!
    }

    private func daysAgo(_ days: Double) -> Date {
        now.addingTimeInterval(-60 * 60 * 24 * days)
    }

    @Test
    func untouchedFor13DaysIsNotDormant() {
        let task = TaskItem(title: "A", estimatedMinutes: 10, updatedAt: daysAgo(13))

        #expect(!task.isDormant(at: now, calendar: calendar))
    }

    @Test
    func untouchedFor14DaysIsDormant() {
        let task = TaskItem(title: "A", estimatedMinutes: 10, updatedAt: daysAgo(14))

        #expect(task.isDormant(at: now, calendar: calendar))
    }

    @Test
    func completedTaskIsNeverDormant() {
        let task = TaskItem(
            title: "A",
            isCompleted: true,
            estimatedMinutes: 10,
            updatedAt: daysAgo(30)
        )

        #expect(!task.isDormant(at: now, calendar: calendar))
    }

    @Test
    func taskWithDeadlineIsNeverDormant() {
        let task = TaskItem(
            title: "A",
            estimatedMinutes: 10,
            deadline: daysAgo(20),
            updatedAt: daysAgo(30)
        )

        #expect(!task.isDormant(at: now, calendar: calendar))
    }

    @Test
    func taskScheduledForTodayOrLaterIsNotDormant() {
        let earlierToday = calendar.startOfDay(for: now).addingTimeInterval(60 * 60)

        let today = TaskItem(
            title: "今日",
            estimatedMinutes: 10,
            scheduledDate: earlierToday,
            updatedAt: daysAgo(30)
        )
        let future = TaskItem(
            title: "来週",
            estimatedMinutes: 10,
            scheduledDate: now.addingTimeInterval(60 * 60 * 24 * 7),
            updatedAt: daysAgo(30)
        )

        #expect(!today.isDormant(at: now, calendar: calendar))
        #expect(!future.isDormant(at: now, calendar: calendar))
    }

    @Test
    func taskScheduledInThePastCanBeDormant() {
        let task = TaskItem(
            title: "先月",
            estimatedMinutes: 10,
            scheduledDate: daysAgo(20),
            updatedAt: daysAgo(20)
        )

        #expect(task.isDormant(at: now, calendar: calendar))
    }

    @Test
    func updatedAtIsPreservedThroughEncoding() throws {
        let task = TaskItem(title: "A", estimatedMinutes: 10, updatedAt: daysAgo(3))

        let data = try JSONEncoder().encode(task)
        let decoded = try JSONDecoder().decode(TaskItem.self, from: data)

        #expect(decoded.updatedAt == task.updatedAt)
    }

    @Test
    func legacyTaskWithoutUpdatedAtStartsCountingFromLoadTime() throws {
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "title": "古いデータ",
            "isCompleted": false,
            "estimatedMinutes": 15,
            "prerequisiteIDs": []
        }
        """

        let before = Date()
        let decoded = try JSONDecoder().decode(TaskItem.self, from: Data(json.utf8))

        #expect(decoded.updatedAt >= before)
        #expect(!decoded.isDormant(at: Date()))
    }
}
