import AppKit
import SwiftUI
import Testing

@testable import Vitals

/// app-hosted 的 UI 层冒烟测试与渲染耗时基线。
///
/// 默认测试无需开发者证书；单独的 VitalsUI scheme 承担 XCUITest。
/// 这里用 NSHostingView 在宿主 app 进程内
/// 真实加载 PopoverView 并强制绘制成位图，验的是同一条渲染路径，且 ad-hoc 签名即可运行。
///
/// 覆盖内容：界面确实画出了东西（非空白）、状态变化确实反映到像素、面板渲染耗时基线。
@MainActor
@Suite("Dashboard 渲染冒烟")
struct DashboardRenderTests {

    /// 把面板真实渲染成位图。挂进一个不上屏的窗口，让 SwiftUI 走完布局。
    private func paint(_ hub: SensorHub) -> NSBitmapImageRep {
        let host = NSHostingView(rootView: PopoverView(hub: hub))
        let frame = NSRect(x: 0, y: 0, width: VitalsTheme.panelWidth, height: VitalsTheme.panelHeight)
        host.frame = frame

        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderOut(nil)
        host.layoutSubtreeIfNeeded()

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            Issue.record("无法为面板创建缓存位图，渲染路径未验证")
            return NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        window.contentView = nil
        return rep
    }

    /// 与四角底色不同的像素占比。用于判定"画面上有内容"而非空白面板。
    private func inkCoverage(_ rep: NSBitmapImageRep) -> Double {
        let w = rep.pixelsWide, h = rep.pixelsHigh
        guard w > 8, h > 8, let base = rep.colorAt(x: 2, y: 2) else { return 0 }
        var counted = 0, inked = 0
        var x = 0
        while x < w {
            var y = 0
            while y < h {
                if let c = rep.colorAt(x: x, y: y) {
                    let delta =
                        abs(c.redComponent - base.redComponent)
                        + abs(c.greenComponent - base.greenComponent)
                        + abs(c.blueComponent - base.blueComponent)
                    if delta > 0.12 { inked += 1 }
                    counted += 1
                }
                y += 3
            }
            x += 3
        }
        return counted > 0 ? Double(inked) / Double(counted) : 0
    }

    private func differingPixels(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> Int {
        let w = min(a.pixelsWide, b.pixelsWide), h = min(a.pixelsHigh, b.pixelsHigh)
        var differs = 0
        for x in stride(from: 0, to: w, by: 2) {
            for y in stride(from: 0, to: h, by: 2) {
                guard let ca = a.colorAt(x: x, y: y), let cb = b.colorAt(x: x, y: y) else { continue }
                let delta =
                    abs(ca.redComponent - cb.redComponent)
                    + abs(ca.greenComponent - cb.greenComponent)
                    + abs(ca.blueComponent - cb.blueComponent)
                if delta > 0.12 { differs += 1 }
            }
        }
        return differs
    }

    /// 不启动采样循环：hub 用默认值，渲染结果与本机负载无关，基线才可重复。
    private func makeHub() -> SensorHub { SensorHub() }

    @Test("面板绘制出内容")
    func paintsNonBlankPanel() {
        let rep = paint(makeHub())
        #expect(rep.pixelsWide >= Int(VitalsTheme.panelWidth) - 2)
        #expect(rep.pixelsHigh >= Int(VitalsTheme.panelHeight) - 2)
        let coverage = inkCoverage(rep)
        #expect(coverage > 0.02, "画面接近空白（覆盖率 \(coverage)），渲染链路可能已断")
    }

    @Test("暂停状态改变会真正反映到像素")
    func pauseChangesOutput() {
        let hub = makeHub()
        let live = paint(hub)
        hub.isPaused = true
        let paused = paint(hub)
        let differs = differingPixels(live, paused)
        #expect(differs > 10, "切换暂停后画面无变化（差异像素 \(differs)），状态未驱动 UI")
    }

    /// 烘焙成位图的机身静态像素：验证方向与几何没在迁移到离屏位图时翻掉。
    /// 顶面（b≈0.50）与正面（b≈0.34）的蓝色分量差是稳定的相对特征，
    /// 因此比较两点而不是比绝对值——TIFF 的色彩空间转换会整体平移分量。
    @Test("机身位图方向正确")
    func plateIsUpright() throws {
        let data = try #require(PixelMachinePlate.image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: data))
        #expect(rep.pixelsWide == 160 && rep.pixelsHigh == 112)
        let topFace = try #require(rep.colorAt(x: 80, y: 26)?.usingColorSpace(.sRGB))
        let frontFace = try #require(rep.colorAt(x: 80, y: 86)?.usingColorSpace(.sRGB))
        #expect(
            topFace.blueComponent > frontFace.blueComponent + 0.05,
            "顶面 b=\(topFace.blueComponent) 未高于正面 b=\(frontFace.blueComponent)，机身位图可能上下颠倒")
    }

    /// 渲染耗时基线。上限是先宽后紧：拿到真实分布后再逐次压低，用作回归门禁。
    @Test("面板渲染耗时在预算内")
    func renderCost() {
        let hub = makeHub()
        _ = paint(hub)  // 预热：首次含字体与图层建立开销，不计入基线
        var samples: [UInt64] = []
        samples.reserveCapacity(24)
        for _ in 0..<24 {
            let start = DispatchTime.now().uptimeNanoseconds
            _ = paint(hub)
            samples.append((DispatchTime.now().uptimeNanoseconds - start) / 1000)
        }
        samples.sort()
        let p50 = samples[samples.count / 2]
        let p95 = samples[max(0, Int(Double(samples.count) * 0.95) - 1)]
        print("RENDER_US p50=\(p50) p95=\(p95) max=\(samples.last!) n=\(samples.count)")
        #expect(p95 < 150_000, "单次面板渲染 p95 已达 \(p95)us，超过 150ms 预算")
    }
}
