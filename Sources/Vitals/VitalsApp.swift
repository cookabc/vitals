import SwiftUI

#if DEBUG
import AppKit

/// 视觉走查辅助：`--debug-panel` 启动时把浮窗内容放进普通窗口，便于截屏检查。
/// 发布版（Release）不含此钩子。
final class DebugPanelDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard CommandLine.arguments.contains("--debug-panel") else { return }
        guard let hub = SensorHub.shared else { return }
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 300, width: 352, height: 475),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Vitals Debug Panel"
        window.contentView = NSHostingView(rootView: PopoverView(hub: hub))
        window.makeKeyAndOrderFront(nil)
    }
}
#endif

@main
struct VitalsApp: App {
    #if DEBUG
    @NSApplicationDelegateAdaptor(DebugPanelDelegate.self) private var debugDelegate
    #endif

    @State private var hub: SensorHub

    init() {
        let created = SensorHub()
        _hub = State(initialValue: created)
        created.start()
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(hub: hub)
        } label: {
            MenuBarLabelView(hub: hub)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
