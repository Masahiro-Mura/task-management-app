import Foundation

/// アプリで使える言語
///
/// 選んだ言語は、次にアプリを開いたときから使われる（iOS がアプリの言語を決めるのは起動のときのため）。
/// 「端末の設定に合わせる」なら、iPhone の言語の設定（設定アプリ → TaskFlow → 言語 でも変えられる）に従う。
nonisolated enum AppLanguage: String, CaseIterable, Identifiable {
    case japanese = "ja"
    case english = "en"
    case french = "fr"
    case spanish = "es"
    case german = "de"
    case italian = "it"
    case portuguese = "pt-BR"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case korean = "ko"

    var id: String {
        rawValue
    }

    /// その言語自身での名前（どの言語で使っていても、自分の言語を見つけられるように）
    var nativeName: String {
        switch self {
        case .japanese: return "日本語"
        case .english: return "English"
        case .french: return "Français"
        case .spanish: return "Español"
        case .german: return "Deutsch"
        case .italian: return "Italiano"
        case .portuguese: return "Português (Brasil)"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .korean: return "한국어"
        }
    }

    /// アプリで選んだ言語を覚えておくキー
    static let storageKey = "taskFlow.language"

    /// iOS がアプリの言語を決めるのに読むキー
    static let systemKey = "AppleLanguages"

    /// アプリで選んだ言語。nil なら端末の設定に合わせる
    static func selected(in defaults: UserDefaults = .standard) -> AppLanguage? {
        defaults.string(forKey: storageKey).flatMap(AppLanguage.init(rawValue:))
    }

    /// 言語を選ぶ。nil なら端末の設定に戻す。次に開いたときから使われる
    static func select(_ language: AppLanguage?, in defaults: UserDefaults = .standard) {
        if let language {
            defaults.set(language.rawValue, forKey: storageKey)
            defaults.set([language.rawValue], forKey: systemKey)
        } else {
            defaults.removeObject(forKey: storageKey)
            defaults.removeObject(forKey: systemKey)
        }
    }

    /// 今アプリが表示に使っている言語（起動したときに決まったもの）
    static var current: AppLanguage? {
        let preferred = Bundle.main.preferredLocalizations.first ?? ""
        return AppLanguage(rawValue: preferred)
            ?? allCases.first { preferred.hasPrefix($0.rawValue) }
    }
}
