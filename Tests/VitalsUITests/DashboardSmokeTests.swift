import XCTest

/// 关键路径冒烟测试。
///
/// Vitals 是 LSUIElement 菜单栏 app，状态项不在被测 app 的常规元素树里，
/// 因此复用 DEBUG 的 `--debug-panel` 钩子把同一个 PopoverView 装进普通窗口来驱动。
/// 注意：测的是真实渲染路径，没有为测试另写替身视图。
@MainActor
final class DashboardSmokeTests: XCTestCase {

    private enum ID {
        static let cpuValue = "vitals.panel.cpuValue"
        static let updatedAt = "vitals.panel.updatedAt"
        static let pause = "vitals.panel.pause"
        static let details = "vitals.panel.details"
    }

    private static let bundleID = "com.cookabc.vitals"
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run {
            continueAfterFailure = false
            app = XCUIApplication(bundleIdentifier: Self.bundleID)
            app.launchArguments = ["--debug-panel", "-samplingInterval", "1"]
            app.launch()
            // 面板窗口必须先出现，否则后续断言全是在测启动失败。
            XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15),
                          "debug-panel 窗口未出现：确认以 Debug 配置构建，且 --debug-panel 钩子仍生效")
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            app?.terminate()
            app = nil
        }
        try await super.tearDown()
    }

    /// 面板渲染出 CPU 数值，说明采样数据真的走通了 hub -> body -> 屏幕。
    func test_cpuValueRenders() {
        // PixelText uses Canvas, whose accessibility element need not be a StaticText.
        let cpu = app.descendants(matching: .any).matching(identifier: ID.cpuValue).firstMatch
        XCTAssertTrue(cpu.waitForExistence(timeout: 15))
        XCTAssertFalse(cpu.label.isEmpty, "CPU 数值标签为空")
        XCTAssertTrue(cpu.label.hasSuffix("%"), "CPU 数值应带百分号，实际：\(cpu.label)")
    }

    /// live 状态下时间戳持续推进，等价于"主循环仍在更新 UI"。
    func test_timestampAdvancesWhileLive() throws {
        let stamp = app.staticTexts[ID.updatedAt]
        XCTAssertTrue(stamp.waitForExistence(timeout: 15))
        // macOS exposes a Text's displayed content through AXValue; AXLabel can be empty.
        let before = try XCTUnwrap(stamp.value as? String)
        XCTAssertFalse(before.isEmpty)
        let advances = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", before), object: stamp)
        wait(for: [advances], timeout: 4)
    }

    /// 暂停后 UI 冻结，且按钮可再次点动——验证控制路径与渲染都还活着。
    func test_pauseFreezesTimestamp() throws {
        let pause = app.buttons[ID.pause]
        XCTAssertTrue(pause.waitForExistence(timeout: 15))
        pause.click()

        let stamp = app.staticTexts[ID.updatedAt]
        XCTAssertTrue(stamp.waitForExistence(timeout: 15))
        let frozen = try XCTUnwrap(stamp.value as? String)
        XCTAssertFalse(frozen.isEmpty)
        let changesWhilePaused = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", frozen), object: stamp)
        changesWhilePaused.isInverted = true
        wait(for: [changesWhilePaused], timeout: 4)

        pause.click()
        let resumes = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", frozen), object: stamp)
        wait(for: [resumes], timeout: 5)
    }

    /// 详情/总览来回切换不崩、不留空白面板。
    func test_detailsToggleKeepsPanelUsable() {
        let details = app.buttons[ID.details]
        XCTAssertTrue(details.waitForExistence(timeout: 15))
        details.click()
        XCTAssertTrue(app.windows.firstMatch.exists)
        details.click()
        let cpu = app.descendants(matching: .any).matching(identifier: ID.cpuValue).firstMatch
        XCTAssertTrue(cpu.waitForExistence(timeout: 15), "切回总览后 CPU 面板消失")
    }
}
