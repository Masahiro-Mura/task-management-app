import Foundation

/// くり返しのきまり
nonisolated struct Recurrence: Codable, Equatable, Hashable {

    enum Rule: Codable, Equatable, Hashable {
        case daily
        /// 曜日（1=日曜 … 7=土曜、`Calendar` の weekday と同じ）
        case weekly(weekdays: [Int])
        /// 毎月その日。月に日がなければその月の最終日（31日 → 2月は28日など）
        case monthly(day: Int)
        /// 始めた日から数えて n 日ごと
        case everyNDays(Int)
    }

    var rule: Rule

    /// 日本の祝日はお休み
    var skipsHolidays = false

    /// やり残した回を次の日に持ち越すか。ゴミ出しのような習慣は持ち越さない（静かに流す）のが既定
    var carriesOver = false

    /// 曜日の短い表記（日曜はじまり）。使っている言語に合わせる（日本語なら「日」「月」…）
    static var weekdaySymbols: [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .current
        return calendar.shortWeekdaySymbols
    }

    /// 曜日の読み上げ用の名前（日本語なら「日曜日」）
    static var weekdayNames: [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .current
        return calendar.weekdaySymbols
    }

    /// 「毎週 月・木」「毎月20日」「3日ごと」のような短い説明
    var summary: String {
        var text: String
        switch rule {
        case .daily:
            text = String(localized: "毎日")
        case .weekly(let weekdays):
            // 月曜はじまりで並べる
            let ordered = weekdays.sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }
            let days = ordered.map { Self.weekdaySymbols[($0 - 1) % 7] }
                .joined(separator: String(localized: "weekday.separator", defaultValue: "・", comment: "曜日を並べるときの区切り"))
            text = String(localized: "毎週 \(days)")
        case .monthly(let day):
            text = String(localized: "毎月\(day)日")
        case .everyNDays(let n):
            text = String(localized: "\(n)日ごと")
        }

        if skipsHolidays {
            text = String(localized: "\(text)（祝日は休み）")
        }
        return text
    }
}

/// くり返すタスクのひな形。回ごとに、その日のタスク（`TaskItem`）を作る
struct RecurringTask: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var estimatedMinutes: Int
    var priority: TaskPriority
    var isLight: Bool
    var recurrence: Recurrence

    /// くり返しを始めた日（その日の始まり）。「n日ごと」の数え始め
    var startDate: Date

    /// 「今回はお休み」にした日（その日の始まり）
    var skippedDays: [Date]

    init(
        id: UUID = UUID(),
        title: String,
        estimatedMinutes: Int,
        priority: TaskPriority = .medium,
        isLight: Bool = false,
        recurrence: Recurrence,
        startDate: Date,
        skippedDays: [Date] = []
    ) {
        self.id = id
        self.title = title
        self.estimatedMinutes = estimatedMinutes
        self.priority = priority
        self.isLight = isLight
        self.recurrence = recurrence
        self.startDate = startDate
        self.skippedDays = skippedDays
    }

    /// その日に回があるか
    func occurs(on date: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)

        guard day >= calendar.startOfDay(for: startDate) else {
            return false
        }

        if skippedDays.contains(where: { calendar.isDate($0, inSameDayAs: day) }) {
            return false
        }

        if recurrence.skipsHolidays, JapaneseHolidays.isHoliday(day, calendar: calendar) {
            return false
        }

        switch recurrence.rule {
        case .daily:
            return true

        case .weekly(let weekdays):
            return weekdays.contains(calendar.component(.weekday, from: day))

        case .monthly(let targetDay):
            let dayOfMonth = calendar.component(.day, from: day)
            let lastDay = calendar.range(of: .day, in: .month, for: day)?.count ?? 31
            return dayOfMonth == min(targetDay, lastDay)

        case .everyNDays(let n):
            guard n > 0 else {
                return false
            }
            let elapsed = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: startDate),
                to: day
            ).day ?? 0
            return elapsed % n == 0
        }
    }
}

/// 日本の祝日（振替休日・国民の休日を含む）
///
/// 春分・秋分の日は前年2月に正式に決まるため、分かっている年だけを持つ。年に1回、次の年を足す。
/// 載っていない年は祝日なしとして扱う（「祝日はお休み」が効かないだけで、回は出る）。
nonisolated enum JapaneseHolidays {

    /// "yyyy-MM-dd"
    static let dates: Set<String> = [
        // 2026年
        "2026-01-01", "2026-01-12", "2026-02-11", "2026-02-23", "2026-03-20",
        "2026-04-29", "2026-05-03", "2026-05-04", "2026-05-05", "2026-05-06",
        "2026-07-20", "2026-08-11", "2026-09-21", "2026-09-22", "2026-09-23",
        "2026-10-12", "2026-11-03", "2026-11-23",
        // 2027年
        "2027-01-01", "2027-01-11", "2027-02-11", "2027-02-23", "2027-03-21",
        "2027-03-22", "2027-04-29", "2027-05-03", "2027-05-04", "2027-05-05",
        "2027-07-19", "2027-08-11", "2027-09-20", "2027-09-23", "2027-10-11",
        "2027-11-03", "2027-11-23"
    ]

    /// 祝日の一覧を持っている年
    static let coveredYears: ClosedRange<Int> = 2026...2027

    static func isHoliday(_ date: Date, calendar: Calendar = .current) -> Bool {
        let components = calendar.dateComponents([.year, .month, .day], from: date)

        guard let year = components.year, let month = components.month, let day = components.day else {
            return false
        }

        return dates.contains(String(format: "%04d-%02d-%02d", year, month, day))
    }
}
