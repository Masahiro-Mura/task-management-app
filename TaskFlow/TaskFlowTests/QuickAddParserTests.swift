import Foundation
import Testing
@testable import TaskFlow

struct QuickAddParserTests {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    /// 2026-11-05（木）10:00（日本時間）
    private var now: Date {
        date(2026, 11, 5, 10)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    private func parse(
        _ text: String,
        ignoring: Set<QuickAddParser.Part> = []
    ) -> QuickAddParser.Result? {
        QuickAddParser.parse(text, defaultMinutes: 30, now: now, calendar: calendar, ignoring: ignoring)
    }

    // MARK: - 所要時間

    @Test(arguments: [
        ("請求書を送る 15分", "請求書を送る", 15),
        ("資料を読む 1時間", "資料を読む", 60),
        ("発表準備 1時間30分", "発表準備", 90),
        ("メール返信 ２０分", "メール返信", 20),
        ("散歩 20m", "散歩", 20),
        ("勉強 1h", "勉強", 60),
        ("請求書を送る15分", "請求書を送る", 15),
        ("掃除　10分", "掃除", 10)
    ])
    func readsTrailingDuration(text: String, title: String, minutes: Int) {
        let result = parse(text)

        #expect(result?.title == title)
        #expect(result?.estimatedMinutes == minutes)
        #expect(result?.durationWasWritten == true)
    }

    @Test
    func usesDefaultWhenNoDurationIsWritten() {
        let result = parse("牛乳を買う")

        #expect(result?.title == "牛乳を買う")
        #expect(result?.estimatedMinutes == 30)
        #expect(result?.durationWasWritten == false)
        #expect(result?.scheduledDate == nil)
        #expect(result?.deadline == nil)
    }

    @Test
    func keepsKatakanaAndLeadingKanaAsIs() {
        #expect(parse("メールを書く")?.title == "メールを書く")
        #expect(parse("はがきを出す")?.title == "はがきを出す")
        #expect(parse("にんじんを買う")?.title == "にんじんを買う")
    }

    @Test
    func roundsUpTo5MinutesAndClamps() {
        #expect(parse("電話 7分")?.estimatedMinutes == 10)
        #expect(parse("大掃除 10時間")?.estimatedMinutes == 480)
        #expect(parse("一瞬 0分")?.title == "一瞬 0分")
    }

    @Test
    func onlyDurationOrOnlyDateIsTreatedAsTitle() {
        #expect(parse("15分")?.title == "15分")
        #expect(parse("15分")?.durationWasWritten == false)

        #expect(parse("明日")?.title == "明日")
        #expect(parse("明日")?.scheduledDate == nil)
    }

    @Test
    func emptyInputReturnsNil() {
        #expect(parse("   ") == nil)
    }

    // MARK: - 予定日と時刻

    @Test
    func readsTomorrowWithTime() {
        let result = parse("明日の15時に資料作成")

        #expect(result?.title == "資料作成")
        #expect(result?.scheduledDate == date(2026, 11, 6, 15))
        #expect(result?.includesTime == true)
        #expect(result?.deadline == nil)
        #expect(result?.estimatedMinutes == 30)
    }

    @Test(arguments: [
        ("今日 掃除", 5),
        ("明日 掃除", 6),
        ("明後日に掃除", 7),
        ("木曜に掃除", 5),
        ("金曜に掃除", 6),
        ("月曜に掃除", 9),
        ("今週金曜に掃除", 6),
        ("来週月曜に掃除", 9),
        ("来週の木曜に掃除", 12)
    ])
    func readsRelativeDaysAndWeekdays(text: String, day: Int) {
        let result = parse(text)

        #expect(result?.title == "掃除")
        #expect(result?.scheduledDate == date(2026, 11, day))
        #expect(result?.includesTime == false)
    }

    @Test
    func readsMonthDayAndRollsPastDatesToNextYear() {
        #expect(parse("11/20 15:30 打ち合わせ")?.scheduledDate == date(2026, 11, 20, 15, 30))
        #expect(parse("11/20 15:30 打ち合わせ")?.title == "打ち合わせ")
        #expect(parse("11月3日に申込")?.scheduledDate == date(2027, 11, 3))
        #expect(parse("2/30に申込")?.scheduledDate == nil)
    }

    @Test
    func readsTimeVariants() {
        #expect(parse("午後3時に電話")?.scheduledDate == date(2026, 11, 5, 15))
        #expect(parse("15時半から会議")?.scheduledDate == date(2026, 11, 5, 15, 30))
        #expect(parse("15時半から会議")?.title == "会議")
        // 日付なしで過ぎた時刻は明日
        #expect(parse("9時に電話")?.scheduledDate == date(2026, 11, 6, 9))
    }

    @Test
    func minutesAfterHourAreTimeNotDuration() {
        let result = parse("資料 明日15時30分")

        #expect(result?.title == "資料")
        #expect(result?.scheduledDate == date(2026, 11, 6, 15, 30))
        #expect(result?.estimatedMinutes == 30)
        #expect(result?.durationWasWritten == false)
    }

    @Test
    func hoursOfDurationAreNotReadAsTime() {
        let result = parse("1時間で資料")

        #expect(result?.scheduledDate == nil)
        #expect(result?.title == "1時間で資料")
    }

    // MARK: - 期限

    @Test
    func untilMakesItADeadlineAtEndOfDay() {
        let result = parse("金曜までにレポート 2時間")

        #expect(result?.title == "レポート")
        #expect(result?.deadline == date(2026, 11, 6, 23, 59, 59))
        #expect(result?.scheduledDate == nil)
        #expect(result?.estimatedMinutes == 120)
    }

    @Test
    func deadlineAfterTitleDropsTheJoiningParticle() {
        let result = parse("レポートを金曜までに")

        #expect(result?.title == "レポート")
        #expect(result?.deadline == date(2026, 11, 6, 23, 59, 59))
    }

    @Test
    func deadlineWithTime() {
        #expect(parse("明日17時までに見積もり")?.deadline == date(2026, 11, 6, 17))
    }

    // MARK: - 読み取りを外す

    @Test
    func ignoringKeepsTheWordsInTheTitle() {
        let ignoredWhen = parse("3時のおやつ", ignoring: [.when])
        #expect(ignoredWhen?.title == "3時のおやつ")
        #expect(ignoredWhen?.scheduledDate == nil)

        let ignoredDuration = parse("ラジオ体操 5分", ignoring: [.duration])
        #expect(ignoredDuration?.title == "ラジオ体操 5分")
        #expect(ignoredDuration?.estimatedMinutes == 30)
    }

    // MARK: - 表示

    @Test
    func describesDatesShortly() {
        #expect(QuickAddParser.describe(date(2026, 11, 5, 15), includesTime: true, now: now, calendar: calendar) == "今日 15:00")
        #expect(QuickAddParser.describe(date(2026, 11, 6), includesTime: false, now: now, calendar: calendar) == "明日")
        #expect(QuickAddParser.describe(date(2026, 11, 7), includesTime: false, now: now, calendar: calendar) == "明後日")
        #expect(QuickAddParser.describe(date(2026, 11, 9, 9, 5), includesTime: true, now: now, calendar: calendar) == "11/9(月) 9:05")
    }
}
