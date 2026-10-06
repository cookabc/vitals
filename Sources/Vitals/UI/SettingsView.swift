import SwiftUI

struct SettingsView: View {
    @AppStorage("menubarMode") private var menubarMode = MenubarMode.graphAndText.rawValue
    @AppStorage("samplingInterval") private var samplingInterval = 1.0
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
        Form {
            Section("菜单栏") {
                Picker("显示内容", selection: $menubarMode) {
                    ForEach(MenubarMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Picker("采样间隔", selection: $samplingInterval) {
                    Text("0.5 秒").tag(0.5)
                    Text("1 秒").tag(1.0)
                    Text("2 秒").tag(2.0)
                }
                .pickerStyle(.segmented)
            }
            Section("显示项目") {
                Toggle("网络", isOn: $showNetwork)
                Toggle("磁盘容量", isOn: $showDisk)
                Toggle("磁盘读写（系统页）", isOn: $showDiskActivity)
                Toggle("电池电量（顶部）", isOn: $showBattery)
                Toggle("进程", isOn: $showProcesses)
            }
            Section("告警") {
                Toggle("启用系统通知", isOn: $alertsEnabled)
                    .onChange(of: alertsEnabled) { _, enabled in
                        guard enabled else { return }
                        Task {
                            _ = await SensorHub.shared?.requestNotificationAuthorization()
                        }
                    }
                if alertsEnabled {
                    LabeledContent("CPU 高占用阈值", value: "≥ \(Int(cpuAlertThreshold))%")
                    Slider(value: $cpuAlertThreshold, in: 60...100, step: 5)
                        .accessibilityLabel("CPU 高占用阈值")
                    LabeledContent("磁盘告警阈值", value: "已用 \(Int(diskAlertThreshold))%")
                    Slider(value: $diskAlertThreshold, in: 70...100, step: 5)
                        .accessibilityLabel("磁盘告警阈值")
                    Text("CPU 需连续 30 秒超过阈值才通知；同一告警 5 分钟内不重复发送。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("通用") {
                Toggle("登录时启动", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        do {
                            try LaunchAtLogin.setEnabled(newValue)
                            launchAtLogin = newValue
                            loginError = nil
                        } catch {
                            launchAtLogin = LaunchAtLogin.isEnabled
                            loginError = error.localizedDescription
                        }
                    }
                ))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                LabeledContent("版本", value: version)
                LabeledContent("系统要求", value: "macOS 26.0+")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 620)
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }
}
