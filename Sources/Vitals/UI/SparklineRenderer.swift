import AppKit

/// 用 CoreGraphics 渲染菜单栏内的 CPU 迷你面积图。
enum SparklineRenderer {
    static func image(values: [Double], size: CGSize, color: NSColor) -> NSImage {
        let samples = Array(values.suffix(120).map { min(100, max(0, $0)) })
        let sRGB = color.usingColorSpace(.sRGB)?.cgColor
            ?? CGColor(red: 0.31, green: 0.66, blue: 1.0, alpha: 1)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return true }
            guard samples.count > 1 else {
                context.setStrokeColor(sRGB.copy(alpha: 0.5) ?? sRGB)
                context.setLineWidth(1.2)
                context.move(to: CGPoint(x: rect.minX, y: rect.midY))
                context.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                context.strokePath()
                return true
            }
            let stepX = rect.width / CGFloat(samples.count - 1)
            func point(_ index: Int) -> CGPoint {
                CGPoint(
                    x: rect.minX + CGFloat(index) * stepX,
                    y: rect.minY + 1.5 + (rect.height - 3) * CGFloat(samples[index] / 100)
                )
            }

            let areaPath = CGMutablePath()
            areaPath.move(to: CGPoint(x: rect.minX, y: rect.minY + 1))
            for index in samples.indices { areaPath.addLine(to: point(index)) }
            areaPath.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + 1))
            areaPath.closeSubpath()

            context.saveGState()
            context.addPath(areaPath)
            context.clip()
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [sRGB.copy(alpha: 0.55), sRGB.copy(alpha: 0.02)] as CFArray,
                locations: [0, 1]
            )
            context.drawLinearGradient(
                gradient ?? CGGradient(colorSpace: CGColorSpaceCreateDeviceRGB(), colorComponents: [0, 0, 0, 0, 0, 0, 0, 0], locations: [0, 1], count: 2)!,
                start: CGPoint(x: rect.midX, y: rect.minY),
                end: CGPoint(x: rect.midX, y: rect.maxY),
                options: []
            )
            context.restoreGState()

            let linePath = CGMutablePath()
            for index in samples.indices {
                let p = point(index)
                if index == 0 { linePath.move(to: p) } else { linePath.addLine(to: p) }
            }
            context.addPath(linePath)
            context.setStrokeColor(sRGB.copy(alpha: 0.95) ?? sRGB)
            context.setLineWidth(1.6)
            context.setLineJoin(.round)
            context.setLineCap(.round)
            context.strokePath()

            let last = point(samples.count - 1)
            let dotRect = CGRect(x: last.x - 2.4, y: last.y - 2.4, width: 4.8, height: 4.8)
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
            context.fillEllipse(in: dotRect)
            context.setStrokeColor(sRGB)
            context.setLineWidth(1.2)
            context.strokeEllipse(in: dotRect)
            return true
        }
        image.isTemplate = false
        return image
    }
}

/// Vector template image stays legible on either menu bar appearance, including selection.
enum VitalsMark {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return true }
            let path = CGMutablePath()
            path.addLines(between: [
                CGPoint(x: 1.5, y: 10), CGPoint(x: 4.5, y: 10),
                CGPoint(x: 7.3, y: 3), CGPoint(x: 12.2, y: 15),
                CGPoint(x: 15.1, y: 8), CGPoint(x: 18.5, y: 8),
            ])
            context.addPath(path)
            context.setLineWidth(1.8)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setStrokeColor(NSColor.black.cgColor)
            context.strokePath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Vitals"
        return image
    }()
}
