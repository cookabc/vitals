import AppIntents

/// 注册到「快捷指令」App 的动作：暂停 / 继续监控。
struct ToggleMonitoringIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.title"
    static let description = IntentDescription("intent.description")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let hub = SensorHub.shared else {
            return .result(dialog: IntentDialog(stringLiteral: L10n.text("intent.notRunning")))
        }
        hub.togglePause()
        return .result(dialog: IntentDialog(stringLiteral: L10n.text(hub.isPaused ? "intent.paused" : "intent.resumed")))
    }
}
