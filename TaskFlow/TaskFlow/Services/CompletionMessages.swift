import Foundation

/// 完了したときに出す、ひとことの文
enum CompletionMessages {

    /// - Parameters:
    ///   - finishedGroup: 分けたタスクの最後の1つで、全部が終わったとき true
    ///   - randomIndex: 文を選ぶための数。テストでは固定する
    static func message(
        for task: TaskItem,
        finishedGroup: Bool,
        randomIndex: Int = Int.random(in: 0..<1000)
    ) -> String {

        if finishedGroup {
            return String(localized: "「\(baseTitle(of: task.title))」が全部終わりました")
        }

        let messages = [
            String(localized: "ひとつ片づきました"),
            String(localized: "\(task.estimatedMinutes)分ぶん、前に進みました"),
            String(localized: "いい区切りです"),
            String(localized: "おつかれさまです")
        ]

        return messages[abs(randomIndex) % messages.count]
    }

    /// 「発表資料を作る（3/3）」→「発表資料を作る」
    static func baseTitle(of title: String) -> String {
        title.replacing(#/（\d+/\d+）$/#, with: "")
    }
}
