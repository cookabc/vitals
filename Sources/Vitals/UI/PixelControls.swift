import SwiftUI

struct PixelSection<Content: View>: View {
    var title: String
    var color: Color
    var content: Content
    init(_ title: String, color: Color = PixelPalette.cyan, @ViewBuilder content: () -> Content) {
        self.title = title
        self.color = color
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PixelText(title, color: color)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pixelPanel()
    }
}

struct PixelReadout: View {
    var label: String
    var value: String
    var color: Color = PixelPalette.text
    var body: some View {
        HStack {
            Text(label).foregroundStyle(PixelPalette.muted)
            Spacer(minLength: 12)
            Text(value).foregroundStyle(color).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

struct PixelToggleStyle: ToggleStyle {
    @Environment(\.appLanguage) private var language

    private func tr(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.text(key, language: language, arguments: arguments)
    }

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                ZStack {
                    Rectangle().strokeBorder(PixelPalette.edge, lineWidth: 1).frame(width: 14, height: 14)
                    if configuration.isOn { Rectangle().fill(PixelPalette.cyan).frame(width: 8, height: 8) }
                }
                configuration.label
                Spacer(minLength: 0)
                Text(configuration.isOn ? tr("state.on") : tr("state.off"))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(configuration.isOn ? PixelPalette.cyan : PixelPalette.muted)
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? tr("state.enabled") : tr("state.disabled"))
    }
}

struct PixelChoice<Value: Hashable>: View {
    @Binding var selection: Value
    var options: [(String, Value)]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button { selection = option.1 } label: {
                    Text(option.0).frame(maxWidth: .infinity).padding(.vertical, 7)
                        .foregroundStyle(selection == option.1 ? PixelPalette.background : PixelPalette.muted)
                        .background(selection == option.1 ? PixelPalette.cyan : PixelPalette.track)
                        .overlay { Rectangle().strokeBorder(PixelPalette.edge, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.1 ? .isSelected : [])
            }
        }
    }
}
