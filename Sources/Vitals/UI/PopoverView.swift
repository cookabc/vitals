import SwiftUI

struct PopoverView: View {
    var hub: SensorHub
    var body: some View { LocalizedContent { PixelDashboardView(hub: hub) } }
}
