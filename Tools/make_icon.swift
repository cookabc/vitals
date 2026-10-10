import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Vitals identity: a single V-shaped pulse, shared with the monochrome menu bar mark.
// Usage: swift Tools/make_icon.swift <1024px output.png>
let size = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.setAllowsAntialiasing(true)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}
func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
}
let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
let outline = CGPath(roundedRect: plate, cornerWidth: 184, cornerHeight: 184, transform: nil)

// Flat midnight plate with a quiet terminal border.
context.addPath(outline)
context.setFillColor(color(0.045, 0.055, 0.085))
context.fillPath()
context.addPath(outline)
context.setLineWidth(6)
context.setStrokeColor(color(0.18, 0.21, 0.28))
context.strokePath()
for y in stride(from: 220, through: 804, by: 32) {
    for x in stride(from: 220, through: 804, by: 32) {
        context.setFillColor(color(0.18, 0.21, 0.28, 0.45))
        context.fill(CGRect(x: x, y: y, width: 4, height: 4))
    }
}

let pulse = CGMutablePath()
let points: [CGPoint] = [
    CGPoint(x: 234, y: 550), CGPoint(x: 330, y: 550),
    CGPoint(x: 425, y: 332), CGPoint(x: 585, y: 712),
    CGPoint(x: 680, y: 490), CGPoint(x: 790, y: 490),
]
pulse.addLines(between: points)
let stroke = pulse.copy(strokingWithWidth: 62, lineCap: .square, lineJoin: .miter, miterLimit: 10)
context.setShouldAntialias(false)
for y in stride(from: 256, through: 768, by: 16) {
    for x in stride(from: 192, through: 832, by: 16) {
        if stroke.contains(CGPoint(x: x + 8, y: y + 8)) {
            context.setFillColor(color(0.25, 0.87, 0.81))
            context.fill(CGRect(x: x, y: y, width: 16, height: 16))
        }
    }
}
context.setFillColor(color(0.98, 0.80, 0.31))
context.fill(CGRect(x: 744, y: 232, width: 32, height: 16))
context.setFillColor(color(0.70, 0.86, 0.30))
context.fill(CGRect(x: 696, y: 232, width: 32, height: 16))

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL,
                                                        UTType.png.identifier as CFString, 1, nil)
else { fatalError("Cannot write icon") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Cannot save icon") }
print("wrote \(output)")
