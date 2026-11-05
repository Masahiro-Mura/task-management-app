import Foundation

/// 書いた文を、タスクらしい名前に整える（規則だけで、AIは使わない）
///
/// 例：
/// - 「先生にメール送らないといけない」→「先生にメール送る」
/// - 「あ、レポート書かなきゃ！」→「レポート書く」
/// - 「部屋の掃除しないと」→「部屋の掃除する」
/// - 「TODO: 請求書の確認」→「請求書の確認」
///
/// 迷う形（「〜たい」「〜ます」など）は、読み違えないよう変えない。
nonisolated enum TitleNormalizer {

    static func normalize(_ title: String) -> String {
        var text = title.trimmingCharacters(in: .whitespacesAndNewlines)

        text = stripLeadingFillers(text)
        text = stripEndPunctuation(text)
        text = baseForm(of: text)
        text = stripEndPunctuation(text)

        // 整えた結果が短すぎるなら、元のまま
        guard text.count >= 2 else {
            return title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    // MARK: - 前後の飾り

    private static let leadingFillers = [
        "あ、", "あっ、", "あー、", "あー", "えっと、", "えっと", "えーと、", "えーと",
        "そういえば、", "そういえば", "とりあえず", "TODO:", "TODO：", "todo:", "ToDo:",
        "やること：", "やること:", "メモ：", "メモ:"
    ]

    private static func stripLeadingFillers(_ text: String) -> String {
        var result = text
        var changed = true

        while changed {
            changed = false
            for filler in leadingFillers where result.hasPrefix(filler) {
                result = String(result.dropFirst(filler.count)).trimmingCharacters(in: .whitespaces)
                changed = true
            }
        }
        return result
    }

    private static let endPunctuation = CharacterSet(charactersIn: "。．.！!？?、…〜~ 　")

    private static func stripEndPunctuation(_ text: String) -> String {
        var scalars = text.unicodeScalars
        while let last = scalars.last, endPunctuation.contains(last) {
            scalars.removeLast()
        }
        return String(String.UnicodeScalarView(scalars))
    }

    // MARK: - 言い切りの形に

    /// 「〜する」に直す言い回し（長いものから順に調べる）
    private static let suruEndings = [
        "しなければならない", "しなければいけない", "しなくてはいけない", "しなくちゃいけない",
        "しないといけない", "しなきゃいけない", "しておかないと", "しとかないと",
        "する必要がある", "しなければ", "しなくちゃ", "しなきゃ", "しないと",
        "する予定", "しておく", "しとく", "します", "したい", "しよう"
    ]

    /// 「〜ないと」などの、打ち消しの言い回し（長いものから順に調べる）
    private static let negativeEndings = [
        "なければならない", "なければいけない", "なくてはいけない", "なくちゃいけない",
        "ないといけない", "なきゃいけない", "なければ", "なくちゃ", "なきゃ", "ないと"
    ]

    /// 五段活用の「ない」の前（あ段）→ 言い切り（う段）
    private static let godanBase: [Character: Character] = [
        "わ": "う", "か": "く", "が": "ぐ", "さ": "す", "た": "つ",
        "な": "ぬ", "ば": "ぶ", "ま": "む", "ら": "る"
    ]

    /// 一段活用の「ない」の前に来る音（い段・え段）。後ろに「る」を足す
    private static let ichidanStems: Set<Character> = [
        "い", "き", "ぎ", "し", "じ", "ち", "に", "ひ", "び", "み", "り",
        "え", "け", "げ", "せ", "ぜ", "て", "で", "ね", "へ", "べ", "め", "れ"
    ]

    private static func baseForm(of text: String) -> String {
        // 「〜する」系
        for ending in suruEndings where text.hasSuffix(ending) && text.count > ending.count {
            return String(text.dropLast(ending.count)) + "する"
        }

        // 「来ないと」→「来る」
        for ending in negativeEndings where text.hasSuffix("来" + ending) || text.hasSuffix("こ" + ending) {
            return String(text.dropLast(ending.count + 1)) + "来る"
        }

        // 「送らないと」→「送る」、「食べないと」→「食べる」
        for ending in negativeEndings where text.hasSuffix(ending) && text.count > ending.count + 1 {
            var stem = String(text.dropLast(ending.count))
            guard let last = stem.last else {
                continue
            }

            if let base = godanBase[last] {
                stem.removeLast()
                return stem + String(base)
            }

            if ichidanStems.contains(last) || isKanji(last) {
                return stem + "る"
            }

            return text
        }

        // 「買うこと」→「買う」（「こと」の前が言い切りの音のときだけ）
        if text.hasSuffix("こと"), text.count > 3 {
            let stem = text.dropLast(2)
            if let last = stem.last, "うくぐすつぬぶむる".contains(last) {
                return String(stem)
            }
        }

        return text
    }

    private static func isKanji(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { (0x4E00...0x9FFF).contains($0.value) }
    }
}
