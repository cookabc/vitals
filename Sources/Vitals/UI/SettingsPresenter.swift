import AppKit
import SwiftUI

/// Finds only the window hosting SettingsView, without touching the menu bar panel or other windows.
struct SettingsWindowRegistration: NSViewRepresentable {
    var titleKey = "window.settings"
    var managesSettings = true
    @Environment(\.appLanguage) private var language
    func makeNSView(context: Context) -> RegistrationView {
        let view = RegistrationView()
        view.settingsTitle = L10n.text(titleKey, language: language)
        view.managesSettings = managesSettings
        return view
    }
    func updateNSView(_ nsView: RegistrationView, context: Context) {
        nsView.settingsTitle = L10n.text(titleKey, language: language)
        nsView.window?.title = nsView.settingsTitle
    }

    final class RegistrationView: NSView {
        var settingsTitle = "Vitals"
        var managesSettings = true
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.title = settingsTitle
        }
    }
}
