import SwiftUI

@main
struct VitalsApp: App {
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
