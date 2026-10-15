import SwiftUI

extension EnvironmentValues {
    @Entry var appLanguage: AppLanguage = .system
}

/// The menu bar popover, manually hosted debug panel and Settings scene share the same live preference.
struct LocalizedContent<Content: View>: View {
    @AppStorage("appLanguage") private var languageRaw = AppLanguage.system.rawValue
    var content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        // 这里解析一次，视图树里的每次取文案就不用再查偏好语言。
        let language = (AppLanguage(rawValue: languageRaw) ?? .system).resolved()
        content.environment(\.appLanguage, language).environment(\.locale, language.locale)
    }
}
