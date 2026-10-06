import AppIntents

/// 注册到「快捷指令」App 的动作：暂停 / 继续监控。
struct ToggleMonitoringIntent: AppIntent {
    static let title: LocalizedStringResource = "暂停或继续 Vitals 监控"
    static let description = IntentDescription("切换 Vitals 菜单栏监控的暂停状态。")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let hub = SensorHub.shared else {
            return .result(dialog: "Vitals 未在运行")
        }
        hub.togglePause()
        return .result(dialog: hub.isPaused ? "已暂停监控" : "已继续监控")
    }
}
