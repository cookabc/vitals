import Foundation

enum AppLanguage: String, CaseIterable, Sendable {
    case system, english = "en", simplifiedChinese = "zh-Hans"

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "system") ?? .system
    }
    func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard self == .system else { return self }
        for identifier in preferredLanguages {
            let code = identifier.lowercased()
            if code.hasPrefix("zh") { return .simplifiedChinese }
            if code.hasPrefix("en") { return .english }
        }
        return .english
    }
    var locale: Locale {
        let code = resolved() == .simplifiedChinese ? "zh_Hans" : "en"
        return Locale(identifier: code + "_" + (Locale.current.region?.identifier ?? "US"))
    }
}

enum L10n {
    private static let english = localizedBundle("en")
    private static let chinese = localizedBundle("zh-Hans")

    private static func localizedBundle(_ code: String) -> Bundle {
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"), let bundle = Bundle(path: path) else { return .main }
        return bundle
    }

    static func text(_ key: String, language: AppLanguage = .current, arguments: [CVarArg] = []) -> String {
        let resolved = language.resolved()
        let bundle = resolved == .simplifiedChinese ? chinese : english
        let format = bundle.localizedString(forKey: key, value: key, table: "Localizable")
        return arguments.isEmpty ? format : String(format: format, locale: resolved.locale, arguments: arguments)
    }
}
