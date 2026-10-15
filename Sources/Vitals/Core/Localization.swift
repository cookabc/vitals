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
    var locale: Locale { L10n.locale(for: self) }
}

enum L10n {
    private static let english = localizedBundle("en")
    private static let chinese = localizedBundle("zh-Hans")
    private static let region = Locale.current.region?.identifier ?? "US"
    /// 面板一帧要取几十条文案与读数，Locale 每种语言只在进程内构造一次。
    private static let locales: [AppLanguage: Locale] = [
        .english: Locale(identifier: "en_\(region)"),
        .simplifiedChinese: Locale(identifier: "zh_Hans_\(region)")
    ]

    static func locale(for language: AppLanguage) -> Locale {
        let resolved = language == .system ? language.resolved() : language
        return locales[resolved] ?? Locale(identifier: "en_\(region)")
    }

    private static func localizedBundle(_ code: String) -> Bundle {
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"), let bundle = Bundle(path: path) else { return .main }
        return bundle
    }

    /// `language` 期望是已解析的语言（视图层用环境里的值）；只有 `.system` 才再查一次偏好语言。
    static func text(_ key: String, language: AppLanguage = .current, arguments: [CVarArg] = []) -> String {
        let resolved = language == .system ? language.resolved() : language
        let bundle = resolved == .simplifiedChinese ? chinese : english
        let format = bundle.localizedString(forKey: key, value: key, table: "Localizable")
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: locales[resolved] ?? locale(for: language), arguments: arguments)
    }
}
