import Foundation

/// 1行の入力から、タスク名と所要時間を読み取る
///
/// 末尾に書かれた時間だけを読む。例：
/// - 「請求書を送る 15分」→ 請求書を送る / 15分
/// - 「資料を読む 1時間」→ 資料を読む / 60分
/// - 「発表準備 1時間30分」→ 発表準備 / 90分
/// - 「メール返信 ２０分」（全角）→ メール返信 / 20分
/// - 「散歩 20m」「勉強 1h」→ 20分 / 60分
/// 時間がなければ `defaultMinutes` を使う。所要時間は5〜480分に収め、5分単位に切り上げる。
enum QuickAddParser {

    struct Result: Equatable {
        var title: String
        var estimatedMinutes: Int
    }

    static let minuteRange = 5...480

    /// - Returns: タイトルが空ならnil
    static func parse(_ text: String, defaultMinutes: Int) -> Result? {
        let normalized = halfwidthDigits(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            return nil
        }

        guard let match = normalized.firstMatch(of: durationPattern) else {
            return Result(title: normalized, estimatedMinutes: clamp(defaultMinutes))
        }

        let hours = match.output.hours.flatMap { Int($0) } ?? 0
        let minutes = match.output.minutes.flatMap { Int($0) } ?? 0
        let total = hours * 60 + minutes

        let title = String(normalized[..<match.range.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 時間しか書かれていないときは、時間ではなくタスク名として扱う
        guard !title.isEmpty, total > 0 else {
            return Result(title: normalized, estimatedMinutes: clamp(defaultMinutes))
        }

        return Result(title: title, estimatedMinutes: clamp(total))
    }

    /// 末尾の「1時間30分」「15分」「1h」「20m」などに一致する
    private static let durationPattern = #/\s*(?:(?<hours>\d+)\s*(?:時間|h))?\s*(?:(?<minutes>\d+)\s*(?:分|m))?\s*$/#

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
