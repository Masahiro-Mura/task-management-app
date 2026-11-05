import Foundation

/// くり返しのひな形から、その日の回を出す（UIや保存に触れない純粋なロジック）
enum RecurrenceScheduler {

    /// 今日の回を出し、持ち越さない回で過ぎたものは静かに流す
    ///
    /// - Returns: タスク一覧を変えたか
    static func refreshOccurrences(
        in tasks: inout [TaskItem],
        recurringTasks: [RecurringTask],
        now: Date,
        calendar: Calendar
    ) -> Bool {
        let today = calendar.startOfDay(for: now)
        let carriesOver = Dictionary(
            uniqueKeysWithValues: recurringTasks.map { ($0.id, $0.recurrence.carriesOver) }
        )

        let before = tasks.count
        tasks.removeAll { task in
            guard let recurringID = task.recurringID,
                  let occurrenceDate = task.occurrenceDate,
                  !task.isCompleted,
                  occurrenceDate < today else {
                return false
            }
            // ひな形を消した回は、ふつうのタスクとして残す
            return !(carriesOver[recurringID] ?? true)
        }
        var changed = tasks.count != before

        for recurring in recurringTasks where recurring.occurs(on: today, calendar: calendar) {
            let alreadyExists = tasks.contains { task in
                task.recurringID == recurring.id
                    && task.occurrenceDate.map { calendar.isDate($0, inSameDayAs: today) } == true
            }

            guard !alreadyExists else {
                continue
            }

            tasks.append(
                TaskItem(
                    title: recurring.title,
                    estimatedMinutes: recurring.estimatedMinutes,
                    priority: recurring.priority,
                    scheduledDate: today,
                    updatedAt: now,
                    isLight: recurring.isLight,
                    recurringID: recurring.id,
                    occurrenceDate: today
                )
            )
            changed = true
        }

        return changed
    }
}
