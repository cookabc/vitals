import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// 生成 macOS App 图标（1024×1024，圆角矩形内含 CPU 曲线），用法: swift make_icon.swift <输出.png>
let size = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
else {
    fatalError("cannot create context")
}

let inset: CGFloat = 100
let cornerRadius: CGFloat = 186
let rect = CGRect(x: inset, y: inset, width: CGFloat(size) - inset * 2, height: CGFloat(size) - inset * 2)
let rounded = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

context.addPath(rounded)
context.clip()

let backgroundGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(red: 0.08, green: 0.09, blue: 0.15, alpha: 1),
        CGColor(red: 0.16, green: 0.19, blue: 0.31, alpha: 1),
    ] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    backgroundGradient,
    start: CGPoint(x: 0, y: CGFloat(size)),
    end: CGPoint(x: CGFloat(size), y: 0),
    options: []
)

context.setFillColor(CGColor(red: 0.35, green: 0.55, blue: 1.0, alpha: 0.12))
context.fillEllipse(in: CGRect(x: -150, y: 520, width: 900, height: 700))

let values: [Double] = [14, 22, 18, 36, 28, 52, 42, 66, 56, 82, 70, 92]
let chartRect = CGRect(x: 190, y: 330, width: 644, height: 390)
let stepX = chartRect.width / CGFloat(values.count - 1)
func point(_ index: Int, _ value: Double) -> CGPoint {
    CGPoint(
        x: chartRect.minX + CGFloat(index) * stepX,
        y: chartRect.minY + chartRect.height * CGFloat(value / 100)
    )
}

let areaPath = CGMutablePath()
areaPath.move(to: CGPoint(x: chartRect.minX, y: chartRect.minY))
for (index, value) in values.enumerated() { areaPath.addLine(to: point(index, value)) }
areaPath.addLine(to: CGPoint(x: chartRect.maxX, y: chartRect.minY))
areaPath.closeSubpath()

context.saveGState()
context.addPath(areaPath)
context.clip()
let areaGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(red: 0.24, green: 0.83, blue: 0.65, alpha: 0.55),
        CGColor(red: 0.31, green: 0.66, blue: 1.0, alpha: 0.0),
    ] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    areaGradient,
    start: CGPoint(x: 512, y: chartRect.minY),
    end: CGPoint(x: 512, y: chartRect.maxY),
    options: []
)
context.restoreGState()

let linePath = CGMutablePath()
for (index, value) in values.enumerated() {
    let p = point(index, value)
    if index == 0 { linePath.move(to: p) } else { linePath.addLine(to: p) }
}
context.addPath(linePath)
context.setStrokeColor(CGColor(red: 0.34, green: 0.80, blue: 0.98, alpha: 1))
context.setLineWidth(30)
context.setLineJoin(.round)
context.setLineCap(.round)
context.strokePath()

let lastPoint = point(values.count - 1, values.last!)
context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
context.fillEllipse(in: CGRect(x: lastPoint.x - 30, y: lastPoint.y - 30, width: 60, height: 60))
context.setStrokeColor(CGColor(red: 0.34, green: 0.80, blue: 0.98, alpha: 1))
context.setLineWidth(14)
context.strokeEllipse(in: CGRect(x: lastPoint.x - 30, y: lastPoint.y - 30, width: 60, height: 60))

context.addPath(rounded)
context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
context.setLineWidth(6)
context.strokePath()

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: output) as CFURL,
        UTType.png.identifier as CFString, 1, nil
      )
else {
    fatalError("cannot write image")
}
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print("wrote \(output)")
