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

// Small external shadow, then a restrained deep teal enamel surface.
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: color(0.01, 0.08, 0.10, 0.22))
context.addPath(outline)
context.setFillColor(color(0.035, 0.085, 0.12))
context.fillPath()
context.restoreGState()
context.saveGState()
context.addPath(outline)
context.clip()
context.drawLinearGradient(gradient([color(0.045, 0.16, 0.22), color(0.025, 0.055, 0.085)]),
                           start: CGPoint(x: 250, y: 924), end: CGPoint(x: 740, y: 100), options: [])
context.drawRadialGradient(gradient([color(0.15, 0.85, 0.70, 0.25), color(0.04, 0.24, 0.26, 0)]),
                           startCenter: CGPoint(x: 225, y: 870), startRadius: 0,
                           endCenter: CGPoint(x: 225, y: 870), endRadius: 830, options: [])
context.restoreGState()

// An inset rim catches light without competing with the symbol at small sizes.
context.addPath(outline)
context.setLineWidth(3)
context.setStrokeColor(color(0.58, 0.92, 0.89, 0.25))
context.strokePath()
let inner = plate.insetBy(dx: 8, dy: 8)
context.addPath(CGPath(roundedRect: inner, cornerWidth: 176, cornerHeight: 176, transform: nil))
context.setLineWidth(2)
context.setStrokeColor(color(1, 1, 1, 0.055))
context.strokePath()

let pulse = CGMutablePath()
let points: [CGPoint] = [
    CGPoint(x: 234, y: 550), CGPoint(x: 330, y: 550),
    CGPoint(x: 425, y: 332), CGPoint(x: 585, y: 712),
    CGPoint(x: 680, y: 490), CGPoint(x: 790, y: 490),
]
pulse.addLines(between: points)
context.saveGState()
context.setShadow(offset: .zero, blur: 30, color: color(0.17, 1, 0.78, 0.45))
context.addPath(pulse)
context.setLineCap(.round)
context.setLineJoin(.round)
context.setLineWidth(62)
context.setStrokeColor(color(0.35, 0.94, 0.79))
context.strokePath()
context.restoreGState()
let stroke = pulse.copy(strokingWithWidth: 62, lineCap: .round, lineJoin: .round, miterLimit: 10)
context.saveGState()
context.addPath(stroke)
context.clip()
context.drawLinearGradient(gradient([color(0.34, 0.86, 0.92), color(0.79, 1, 0.90), color(0.25, 0.91, 0.66)]),
                           start: CGPoint(x: 220, y: 700), end: CGPoint(x: 810, y: 360), options: [])
context.restoreGState()

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL,
                                                        UTType.png.identifier as CFString, 1, nil)
else { fatalError("Cannot write icon") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Cannot save icon") }
print("wrote \(output)")
