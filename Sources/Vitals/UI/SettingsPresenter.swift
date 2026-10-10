import AppKit
import SwiftUI

/// Keep SwiftUI's single Settings scene, but explicitly activate and focus it for an LSUIElement app.
@MainActor
final class SettingsPresenter {
    static let shared = SettingsPresenter()
    private weak var settingsWindow: NSWindow?
    private var presentationRequested = false

    func present(using openSettings: OpenSettingsAction) {
        presentationRequested = true
        NSApp.activate()
        openSettings()
        if let settingsWindow {
            focus(settingsWindow)
        }
    }

    func register(_ window: NSWindow) {
        settingsWindow = window
        guard presentationRequested else { return }
        // The first Settings window is attached asynchronously by SwiftUI.
        // Wait for that attachment, rather than guessing a delay or a private window identifier.
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.presentationRequested else { return }
            self.focus(window)
        }
    }

    private func focus(_ window: NSWindow) {
        presentationRequested = false
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

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
            if managesSettings { SettingsPresenter.shared.register(window) }
        }
    }
}
