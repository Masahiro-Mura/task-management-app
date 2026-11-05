import Foundation
import Testing
@testable import TaskFlow

/// 多言語対応と、アプリ内の言語の選択
@MainActor
struct LocalizationTests {

    private let storage = TemporaryUserDefaults(prefix: "LocalizationTests")

    /// その言語の訳を、端末の言語に関係なく引く
    private func localized(_ key: String, in language: AppLanguage) throws -> String {
        let path = try #require(Bundle.main.path(forResource: language.rawValue, ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    @Test
    func everyLanguageShipsWithTheApp() {
        for language in AppLanguage.allCases {
            #expect(Bundle.main.path(forResource: language.rawValue, ofType: "lproj") != nil, "\(language.rawValue)")
        }
    }

    @Test
    func everyLanguageTranslatesTheHomeScreen() throws {
        for language in AppLanguage.allCases where language != .japanese {
            for key in ["今やること", "始める", "あとで", "reason.leadAndFit"] {
                let text = try localized(key, in: language)
                #expect(text != key, "\(language.rawValue): \(key)")
            }
        }
        #expect(try localized("始める", in: .english) == "Start")
        #expect(try localized("始める", in: .korean) == "시작")
    }

    @Test
    func reasonsKeepTheirNumbersInEveryLanguage() throws {
        for language in AppLanguage.allCases where language != .japanese {
            let format = try localized("reason.leadAndFit", in: language)
            let text = String(format: format, "X", 15, 45)
            #expect(text.contains("15") && text.contains("45") && text.contains("X"), "\(language.rawValue): \(text)")
        }
    }

    @Test
    func choosingALanguageSetsWhatIOSReadsAtLaunch() {
        let defaults = storage.userDefaults

        // テストを動かす言語（-testLanguage）が起動引数として先に読まれるので、保存したものを直接見る
        func saved() -> [String: Any] {
            defaults.persistentDomain(forName: storage.suiteName) ?? [:]
        }

        AppLanguage.select(.french, in: defaults)
        #expect(AppLanguage.selected(in: defaults) == .french)
        #expect(saved()[AppLanguage.systemKey] as? [String] == ["fr"])

        AppLanguage.select(nil, in: defaults)
        #expect(AppLanguage.selected(in: defaults) == nil)
        #expect(saved()[AppLanguage.systemKey] == nil)
    }

    @Test
    func nativeNamesAreDistinct() {
        let names = AppLanguage.allCases.map(\.nativeName)
        #expect(Set(names).count == names.count)
    }
}
