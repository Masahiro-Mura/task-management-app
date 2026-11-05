import Foundation
import Testing
@testable import TaskFlow

struct QuickAddParserTests {

    private func parse(_ text: String) -> QuickAddParser.Result? {
        QuickAddParser.parse(text, defaultMinutes: 30)
    }

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
        #expect(parse(text) == QuickAddParser.Result(title: title, estimatedMinutes: minutes))
    }

    @Test
    func usesDefaultWhenNoDurationIsWritten() {
        #expect(parse("牛乳を買う") == QuickAddParser.Result(title: "牛乳を買う", estimatedMinutes: 30))
    }

    @Test
    func keepsKatakanaAsIs() {
        #expect(parse("メールを書く")?.title == "メールを書く")
    }

    @Test
    func roundsUpTo5MinutesAndClamps() {
        #expect(parse("電話 7分")?.estimatedMinutes == 10)
        #expect(parse("大掃除 10時間")?.estimatedMinutes == 480)
        #expect(parse("一瞬 0分")?.title == "一瞬 0分")
    }

    @Test
    func durationOnlyIsTreatedAsTitle() {
        #expect(parse("15分") == QuickAddParser.Result(title: "15分", estimatedMinutes: 30))
    }

    @Test
    func emptyInputReturnsNil() {
        #expect(parse("   ") == nil)
    }
}
