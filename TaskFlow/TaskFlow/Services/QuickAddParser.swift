import Foundation

/// 1行の入力から、タスク名・所要時間・予定日・期限を読み取る
///
/// 例：
/// - 「請求書を送る 15分」→ 請求書を送る / 15分
/// - 「明日の15時に資料作成」→ 資料作成 / 予定日 明日15:00
/// - 「金曜までにレポート 2時間」→ レポート / 期限 金曜の終わり / 120分
/// - 「メール返信 ２０分」（全角数字）→ メール返信 / 20分
///
/// 読む日付：今日・明日・明後日・（今週／来週）◯曜・11/20・11月20日
/// 読む時刻：15時・15時30分・15時半・15:30・午後3時
/// 「まで」「までに」が付けば期限、なければ予定日。所要時間は末尾だけを読み、5〜480分・5分単位に切り上げる。
/// 「軽」「軽い」「（軽）」を単語として書くと、頭を使わない軽い作業の印になる（例：「メール整理 軽 10分」）。
/// 「毎日」「毎週月曜」「毎週月・木」「毎月20日」「3日ごと」と書くと、くり返すタスクになる（例：「毎週月曜にゴミ出し 5分」）。
/// 「〜しないと」「〜しなきゃ」のような書き方は、タスクらしい名前に整える（`TitleNormalizer`）。
nonisolated enum QuickAddParser {

    /// 読み取る項目。読み取り結果の表示でタップすると、その項目を外せる
    enum Part: Hashable {
        case when
        case duration
        case light
        case `repeat`

        /// 書いた文をタスクらしい名前に整えること（「送らないと」→「送る」など）
        case rename
    }

    struct Result: Equatable {
        var title: String
        var estimatedMinutes: Int
        var scheduledDate: Date? = nil
        var deadline: Date? = nil

        /// 日付に時刻まで書かれていたか
        var includesTime = false

        /// 所要時間が書かれていたか（書かれていなければ既定の時間）
        var durationWasWritten = false

        /// 「軽」と書かれていたか
        var isLight = false

        /// くり返しが書かれていたら、そのきまり
        var recurrence: Recurrence? = nil

        /// 名前を整えたとき、整える前の名前（整えなかったらnil）
        var unrenamedTitle: String? = nil
    }

    static let minuteRange = 5...480

    /// 「11/3」のように過ぎた日付を書いたとき、この日数以内なら今年の日付として読む
    static let recentPastDays = 60

    /// - Parameter ignoring: 読み取らずにタイトルの文字のまま残す項目
    /// - Returns: タイトルが空ならnil
    static func parse(
        _ text: String,
        defaultMinutes: Int,
        now: Date = Date(),
        calendar: Calendar = .current,
        ignoring: Set<Part> = []
    ) -> Result? {

        var remaining = halfwidthDigits(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !remaining.isEmpty else {
            return nil
        }

        let original = remaining
        var result = Result(title: original, estimatedMinutes: clamp(defaultMinutes))

        // 軽い作業の印（単語として書かれたものだけ）
        if !ignoring.contains(.light),
           let match = remaining.firstMatch(of: lightPattern) {
            result.isLight = true
            remaining.replaceSubrange(match.range, with: " ")
            remaining = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // くり返し（「毎週月曜」の「月曜」を日付として読まないよう、日付より先に読む）
        if !ignoring.contains(.repeat),
           let match = remaining.firstMatch(of: repeatPattern),
           let rule = repeatRule(
               daily: match.output.daily != nil,
               weekdays: match.output.weekdays.map(String.init),
               monthDay: match.output.monthDay.flatMap { Int($0) },
               every: match.output.every.flatMap { Int($0) }
           ) {
            result.recurrence = Recurrence(rule: rule)
            remaining.replaceSubrange(match.range, with: " ")
            remaining = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 所要時間（末尾）
        if !ignoring.contains(.duration),
           let match = remaining.firstMatch(of: durationPattern) {
            let hours = match.output.hours.flatMap { Int($0) } ?? 0
            let minutes = match.output.minutes.flatMap { Int($0) } ?? 0
            let total = hours * 60 + minutes

            // 「15時30分」の「30分」は時刻の一部なので、所要時間としては読まない
            let isPartOfTime = match.range.lowerBound > remaining.startIndex
                && remaining[remaining.index(before: match.range.lowerBound)] == "時"

            if total > 0, !isPartOfTime {
                result.estimatedMinutes = clamp(total)
                result.durationWasWritten = true
                remaining = String(remaining[..<match.range.lowerBound])
            }
        }

        // 日付・時刻
        if !ignoring.contains(.when),
           let match = remaining.matches(of: whenPattern).first(where: {
               $0.output.date != nil || $0.output.time != nil
           }),
           let resolved = resolveWhen(
               date: match.output.date.map(String.init),
               ampm: match.output.ampm.map(String.init),
               time: match.output.time.map(String.init),
               isDeadline: match.output.until != nil,
               now: now,
               calendar: calendar
           ) {
            if match.output.until != nil {
                result.deadline = resolved.date
            } else {
                result.scheduledDate = resolved.date
            }
            result.includesTime = resolved.includesTime

            let before = remaining[..<match.range.lowerBound]
            let after = remaining[match.range.upperBound...]

            if after.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // 「レポートを金曜までに」のように後ろに付いていたら、つなぎの助詞を1文字だけ外す
                var trimmed = before.trimmingCharacters(in: .whitespacesAndNewlines)
                if let last = trimmed.last, "をはのに、".contains(last) {
                    trimmed.removeLast()
                }
                remaining = trimmed
            } else {
                remaining = String(before) + String(after)
            }
        }

        let title = remaining.trimmingCharacters(in: .whitespacesAndNewlines)

        // 日付や時間しか書かれていないときは、読み取らずにタスク名として扱う
        guard !title.isEmpty else {
            return Result(title: original, estimatedMinutes: clamp(defaultMinutes))
        }

        result.title = title

        if !ignoring.contains(.rename) {
            let renamed = TitleNormalizer.normalize(title)
            if renamed != title {
                result.title = renamed
                result.unrenamedTitle = title
            }
        }
        return result
    }

    // MARK: - 表示

    /// 読み取った日付の短い表示。「今日 15:00」「明日」「11/20(金)」など
    static func describe(
        _ date: Date,
        includesTime: Bool,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {

        let startOfToday = calendar.startOfDay(for: now)
        let days = calendar.dateComponents(
            [.day],
            from: startOfToday,
            to: calendar.startOfDay(for: date)
        ).day ?? 0

        let dayText: String
        switch days {
        case 0:
            dayText = "今日"
        case 1:
            dayText = "明日"
        case 2:
            dayText = "明後日"
        default:
            let month = calendar.component(.month, from: date)
            let day = calendar.component(.day, from: date)
            let weekday = weekdaySymbols[calendar.component(.weekday, from: date) - 1]
            dayText = "\(month)/\(day)(\(weekday))"
        }

        guard includesTime else {
            return dayText
        }

        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return dayText + String(format: " %d:%02d", hour, minute)
    }

    // MARK: - 読み取りの中身

    /// 「毎日」「毎週月曜」「毎週月・木」「毎月20日」「3日ごと」と、そのあとのつなぎの助詞
    private static let repeatPattern = #/(?:(?<daily>毎日)|毎週(?<weekdays>[月火水木金土日](?:[・、,]?[月火水木金土日])*)曜?日?|毎月(?<monthDay>\d{1,2})日|(?<every>\d{1,3})日ごと)\s*(?:に|の|は|、)?/#

    private static func repeatRule(
        daily: Bool,
        weekdays: String?,
        monthDay: Int?,
        every: Int?
    ) -> Recurrence.Rule? {
        if daily {
            return .daily
        }

        if let weekdays {
            let values = weekdays.compactMap { character -> Int? in
                weekdaySymbols.firstIndex(of: String(character)).map { $0 + 1 }
            }
            let unique = Array(Set(values)).sorted()
            return unique.isEmpty ? nil : .weekly(weekdays: unique)
        }

        if let monthDay, (1...31).contains(monthDay) {
            return .monthly(day: monthDay)
        }

        if let every {
            return every == 1 ? .daily : (2...365).contains(every) ? .everyNDays(every) : nil
        }

        return nil
    }

    /// 前後が空白か端にある「軽」「軽い」と、かっこ付きの「（軽）」「(軽)」
    private static let lightPattern = #/(?:^|\s)軽い?(?=\s|$)|（軽）|\(軽\)/#

    /// 末尾の「1時間30分」「15分」「1h」「20m」などに一致する
    private static let durationPattern = #/\s*(?:(?<hours>\d+)\s*(?:時間|h))?\s*(?:(?<minutes>\d+)\s*(?:分|m))?\s*$/#

    /// 「明日の15時に」「金曜までに」「11/20 15:30」などに一致する。日付と時刻のどちらかがあるものだけを使う
    private static let whenPattern = #/(?<date>今日|きょう|明後日|あさって|明日|あした|あす|(?:今週|来週)の?[月火水木金土日]曜日?|[月火水木金土日]曜日?|\d{1,2}\/\d{1,2}|\d{1,2}月\d{1,2}日)?\s*の?\s*(?<ampm>午前|午後)?\s*(?<time>\d{1,2}:\d{2}|\d{1,2}時(?!間)(?:\d{1,2}分|半)?)?\s*(?<until>までに|まで)?\s*(?:から|[にはでの、])?/#

    private static let weekdaySymbols = ["日", "月", "火", "水", "木", "金", "土"]

    private static func resolveWhen(
        date dateText: String?,
        ampm: String?,
        time timeText: String?,
        isDeadline: Bool,
        now: Date,
        calendar: Calendar
    ) -> (date: Date, includesTime: Bool)? {

        let startOfToday = calendar.startOfDay(for: now)

        let day: Date
        if let dateText {
            guard let resolved = resolveDay(dateText, startOfToday: startOfToday, calendar: calendar) else {
                return nil
            }
            day = resolved
        } else {
            day = startOfToday
        }

        guard let timeText else {
            // 時刻がなければ、期限はその日の終わり、予定日はその日の始まり
            if isDeadline,
               let endOfDay = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: day) {
                return (endOfDay, false)
            }
            return (day, false)
        }

        guard let (parsedHour, minute) = parseTime(timeText) else {
            return nil
        }

        var hour = parsedHour

        if ampm == "午後", hour < 12 {
            hour += 12
        } else if ampm == "午前", hour == 12 {
            hour = 0
        }

        guard (0...23).contains(hour), (0...59).contains(minute),
              var date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) else {
            return nil
        }

        // 日付なしで今日のその時刻が過ぎていたら、明日のその時刻とみなす
        if dateText == nil, date < now,
           let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) {
            date = tomorrow
        }

        return (date, true)
    }

    private static func resolveDay(
        _ text: String,
        startOfToday: Date,
        calendar: Calendar
    ) -> Date? {

        func offset(_ days: Int) -> Date? {
            calendar.date(byAdding: .day, value: days, to: startOfToday)
        }

        switch text {
        case "今日", "きょう":
            return startOfToday
        case "明日", "あした", "あす":
            return offset(1)
        case "明後日", "あさって":
            return offset(2)
        default:
            break
        }

        if let symbol = text.first(where: { weekdaySymbols.contains(String($0)) }),
           text.contains("曜"),
           let target = weekdaySymbols.firstIndex(of: String(symbol)) {
            // 週は月曜はじまりとして数える（月=0 … 日=6）
            let mondayBased = { (sundayBased: Int) in (sundayBased + 6) % 7 }
            let today = mondayBased(calendar.component(.weekday, from: startOfToday) - 1)
            let goal = mondayBased(target)

            if text.hasPrefix("来週") {
                return offset(7 - today + goal)
            }
            if text.hasPrefix("今週") {
                return offset(goal - today)
            }
            // 「金曜」だけなら、今日を含めて次に来るその曜日
            return offset((goal - today + 7) % 7)
        }

        let numbers = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard numbers.count == 2 else {
            return nil
        }

        let year = calendar.component(.year, from: startOfToday)
        guard let thisYear = calendar.date(from: DateComponents(year: year, month: numbers[0], day: numbers[1])),
              calendar.component(.month, from: thisYear) == numbers[0] else {
            return nil
        }

        // 少し前の日付（60日以内）は今年のもの（期限切れ・持ち越し）として読む。それより前なら来年のその日
        if thisYear < startOfToday,
           let limit = calendar.date(byAdding: .day, value: -recentPastDays, to: startOfToday),
           thisYear < limit {
            return calendar.date(byAdding: .year, value: 1, to: thisYear)
        }
        return thisYear
    }

    private static func parseTime(_ text: String) -> (Int, Int)? {
        let numbers = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }

        guard let hour = numbers.first else {
            return nil
        }

        if text.hasSuffix("半") {
            return (hour, 30)
        }
        return (hour, numbers.count > 1 ? numbers[1] : 0)
    }

    /// 全角数字だけを半角にする（カタカナなどはそのまま）
    private static func halfwidthDigits(_ text: String) -> String {
        String(
            text.unicodeScalars.map { scalar in
                // U+FF10「０」〜 U+FF19「９」
                if (0xFF10...0xFF19).contains(scalar.value),
                   let halfwidth = Unicode.Scalar(scalar.value - 0xFEE0) {
                    return Character(halfwidth)
                }

                return Character(scalar)
            }
        )
    }

    private static func clamp(_ minutes: Int) -> Int {
        let roundedUp = Int((Double(minutes) / 5).rounded(.up)) * 5
        return min(max(roundedUp, minuteRange.lowerBound), minuteRange.upperBound)
    }
}
