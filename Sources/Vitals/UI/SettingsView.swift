import SwiftUI

struct SettingsView: View {
    @Environment(\.appLanguage) private var language

    private func tr(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.text(key, language: language, arguments: arguments)
    }

    @AppStorage("appLanguage") private var languageRaw = AppLanguage.system.rawValue
    @AppStorage("menubarMode") private var menubarMode = MenubarMode.graphAndText.rawValue
    @AppStorage("samplingInterval") private var samplingInterval = 1.0
    @AppStorage("showCPU") private var showCPU = true
    @AppStorage("showGPU") private var showGPU = true
    @AppStorage("showMemory") private var showMemory = true
    @AppStorage("showSensors") private var showSensors = true
    @AppStorage("showNetwork") private var showNetwork = true
    @AppStorage("showDisk") private var showDisk = true
    @AppStorage("showDiskActivity") private var showDiskActivity = true
    @AppStorage("showBattery") private var showBattery = true
    @AppStorage("showProcesses") private var showProcesses = true
    @AppStorage("alertsEnabled") private var alertsEnabled = false
    @AppStorage("cpuAlertThreshold") private var cpuAlertThreshold = 90.0
    @AppStorage("diskAlertThreshold") private var diskAlertThreshold = 85.0

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                PixelText(tr("settings.title"), scale: 2)
                Spacer()
                Text("VITALS / \(version)").foregroundStyle(PixelPalette.muted)
            }
            .padding(.vertical, 6)
            ScrollView {
                VStack(spacing: 8) {
                    PixelSection(tr("settings.language")) {
                        PixelChoice(selection: $languageRaw, options: [
                            (tr("language.system"), AppLanguage.system.rawValue),
                            (tr("language.chinese"), AppLanguage.simplifiedChinese.rawValue),
                            (tr("language.english"), AppLanguage.english.rawValue)
                        ])
                    }
                    PixelSection(tr("settings.menu")) {
                        Text(tr("settings.mode")).foregroundStyle(PixelPalette.muted)
                        PixelChoice(selection: $menubarMode, options: MenubarMode.allCases.map { (tr($0.titleKey), $0.rawValue) })
                        Text(tr("settings.interval")).foregroundStyle(PixelPalette.muted)
                        PixelChoice(selection: $samplingInterval, options: [(tr("settings.seconds", "0.5"), 0.5), (tr("settings.seconds", "1"), 1), (tr("settings.seconds", "2"), 2)])
                    }
                    PixelSection(tr("settings.modules")) {
                        Text(tr("settings.modulesHelp"))
                            .font(.system(size: 10)).foregroundStyle(PixelPalette.muted)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 20), GridItem(.flexible())], spacing: 4) {
                            Toggle("CPU", isOn: $showCPU)
                            Toggle(tr("settings.gpu"), isOn: $showGPU)
                            Toggle(tr("settings.memory"), isOn: $showMemory)
                            Toggle(tr("settings.network"), isOn: $showNetwork)
                            Toggle(tr("settings.disk"), isOn: $showDisk)
                            Toggle(tr("settings.diskActivity"), isOn: $showDiskActivity)
                            Toggle(tr("settings.sensors"), isOn: $showSensors)
                            Toggle(tr("battery.title"), isOn: $showBattery)
                            Toggle(tr("settings.processes"), isOn: $showProcesses)
                        }
                        .toggleStyle(PixelToggleStyle())
                        Text(tr("settings.availability"))
                            .font(.system(size: 10)).foregroundStyle(PixelPalette.muted)
                    }
                    PixelSection(tr("settings.alerts"), color: PixelPalette.yellow) {
                        Toggle(tr("settings.notifications"), isOn: $alertsEnabled)
                            .toggleStyle(PixelToggleStyle())
                            .onChange(of: alertsEnabled) { _, enabled in
                                guard enabled else { return }
                                Task { _ = await SensorHub.shared?.requestNotificationAuthorization() }
                            }
                        if alertsEnabled {
                            threshold(tr("settings.cpuThreshold"), value: $cpuAlertThreshold, range: 60...100)
                            threshold(tr("settings.diskThreshold"), value: $diskAlertThreshold, range: 70...100)
                            Text(tr("settings.alertHelp"))
                                .font(.system(size: 10)).foregroundStyle(PixelPalette.muted)
                        }
                    }
                    PixelSection(tr("settings.general")) {
                        Toggle(tr("settings.launch"), isOn: Binding(
                            get: { launchAtLogin },
                            set: { newValue in
                                do {
                                    try LaunchAtLogin.setEnabled(newValue)
                                    launchAtLogin = newValue
                                    loginError = nil
                                } catch {
                                    launchAtLogin = LaunchAtLogin.isEnabled
                                    loginError = "settings.loginError"
                                }
                            }
                        )).toggleStyle(PixelToggleStyle())
                        if let loginError { Text(tr(loginError)).foregroundStyle(PixelPalette.red) }
                        PixelReadout(label: tr("settings.requirements"), value: "macOS 26.0+")
                        Text(tr("settings.sources"))
                            .font(.system(size: 10)).foregroundStyle(PixelPalette.muted)
                    }
                }
            }
        }
        .padding(16)
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(PixelPalette.text)
        .frame(width: 550, height: 640)
        .background(PixelPalette.background)
        .background(SettingsWindowRegistration())
        .preferredColorScheme(.dark)
        .tint(PixelPalette.cyan)
    }

    private func threshold(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title).foregroundStyle(PixelPalette.muted)
            Spacer()
            Button("−") { value.wrappedValue = max(range.lowerBound, value.wrappedValue - 5) }
                .disabled(value.wrappedValue <= range.lowerBound)
                .accessibilityLabel(tr("action.decrease", title))
            Text("≥ \(Int(value.wrappedValue))%").frame(width: 64)
            Button("+") { value.wrappedValue = min(range.upperBound, value.wrappedValue + 5) }
                .disabled(value.wrappedValue >= range.upperBound)
                .accessibilityLabel(tr("action.increase", title))
        }
        .buttonStyle(PixelButtonStyle())
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }
}
