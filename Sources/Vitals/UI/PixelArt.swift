import SwiftUI

/// Original 5×7 bitmap alphabet. Integer cell positions keep labels crisp at both display scales.
struct PixelText: View {
    let text: String
    var scale: CGFloat = 1
    var color: Color = PixelPalette.text

    init(_ text: String, scale: CGFloat = 1, color: Color = PixelPalette.text) {
        self.text = text
        self.scale = scale
        self.color = color
    }

    static func supportsBitmap(_ text: String) -> Bool { text.uppercased().allSatisfy { glyphs[$0] != nil } }

    var body: some View {
        if Self.supportsBitmap(text) {
        Canvas { context, _ in
            for (index, character) in text.uppercased().enumerated() {
                let rows = Self.glyphs[character] ?? Self.glyphs["?"]!
                for (y, row) in rows.enumerated() {
                    for x in 0..<5 where row & (1 << (4 - x)) != 0 {
                        let rect = CGRect(x: CGFloat(index * 6 + x) * scale, y: CGFloat(y) * scale,
                                          width: scale, height: scale)
                        context.fill(Path(rect), with: .color(color))
                    }
                }
            }
        }
        .frame(width: CGFloat(max(0, text.count * 6 - 1)) * scale, height: 7 * scale)
        .accessibilityLabel(text)
        } else {
            Text(verbatim: text)
                .font(.system(size: 11 * scale, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(text)
        }
    }

    private static let glyphs: [Character: [Int]] = [
        "A": [14,17,17,31,17,17,17], "B": [30,17,17,30,17,17,30],
        "C": [14,17,16,16,16,17,14], "D": [30,17,17,17,17,17,30],
        "E": [31,16,16,30,16,16,31], "F": [31,16,16,30,16,16,16],
        "G": [14,17,16,23,17,17,15], "H": [17,17,17,31,17,17,17],
        "I": [31,4,4,4,4,4,31], "J": [7,2,2,2,2,18,12],
        "K": [17,18,20,24,20,18,17], "L": [16,16,16,16,16,16,31],
        "M": [17,27,21,21,17,17,17], "N": [17,25,21,19,17,17,17],
        "O": [14,17,17,17,17,17,14], "P": [30,17,17,30,16,16,16],
        "Q": [14,17,17,17,21,18,13], "R": [30,17,17,30,20,18,17],
        "S": [15,16,16,14,1,1,30], "T": [31,4,4,4,4,4,4],
        "U": [17,17,17,17,17,17,14], "V": [17,17,17,17,17,10,4],
        "W": [17,17,17,21,21,21,10], "X": [17,17,10,4,10,17,17],
        "Y": [17,17,10,4,4,4,4], "Z": [31,1,2,4,8,16,31],
        "0": [14,17,19,21,25,17,14], "1": [4,12,4,4,4,4,14],
        "2": [14,17,1,2,4,8,31], "3": [30,1,1,14,1,1,30],
        "4": [2,6,10,18,31,2,2], "5": [31,16,16,30,1,1,30],
        "6": [14,16,16,30,17,17,14], "7": [31,1,2,4,8,8,8],
        "8": [14,17,17,14,17,17,14], "9": [14,17,17,15,1,1,14],
        "%": [17,2,4,4,8,16,17], "-": [0,0,0,31,0,0,0],
        ".": [0,0,0,0,0,12,12], "/": [1,2,2,4,8,8,16],
        " ": [0,0,0,0,0,0,0], "?": [14,17,1,2,4,0,4],
    ]
}

/// Decorative isometric compute module. Status pixels are tied to real CPU load, never synthetic readings.
struct PixelMachineArt: View {
    var load: Double
    var paused: Bool

    var body: some View {
        Canvas { context, size in
            let offset = CGPoint(x: floor((size.width - 160) / 2), y: 0)
            func shape(_ vertices: [CGPoint]) -> Path {
                var p = Path()
                p.addLines(vertices)
                p.closeSubpath()
                return p
            }
            let top = shape([CGPoint(x: 18, y: 48), CGPoint(x: 80, y: 18), CGPoint(x: 146, y: 48), CGPoint(x: 84, y: 80)])
            let front = shape([CGPoint(x: 18, y: 48), CGPoint(x: 84, y: 80), CGPoint(x: 84, y: 101), CGPoint(x: 18, y: 69)])
            let side = shape([CGPoint(x: 84, y: 80), CGPoint(x: 146, y: 48), CGPoint(x: 146, y: 69), CGPoint(x: 84, y: 101)])
            let shadow = shape([CGPoint(x: 14, y: 75), CGPoint(x: 78, y: 104), CGPoint(x: 154, y: 72), CGPoint(x: 91, y: 53)])
            for y in stride(from: 0, to: 112, by: 2) {
                for x in stride(from: 0, to: 160, by: 2) {
                    let point = CGPoint(x: x + 1, y: y + 1)
                    var tint: Color?
                    if shadow.contains(point) { tint = .black.opacity(0.55) }
                    if side.contains(point) { tint = Color(red: 0.47, green: 0.35, blue: 0.18) }
                    if front.contains(point) {
                        let vent = ((x / 2) % 3 == 0) && ((y - x / 2) % 6 < 3)
                        tint = vent ? Color(red: 0.22, green: 0.19, blue: 0.15) : Color(red: 0.78, green: 0.62, blue: 0.34)
                    }
                    if top.contains(point) {
                        let grain = (x / 2 + y / 2) % 4 == 0
                        tint = grain ? Color(red: 0.85, green: 0.70, blue: 0.43) : Color(red: 0.92, green: 0.78, blue: 0.50)
                    }
                    if let tint {
                        context.fill(Path(CGRect(x: CGFloat(x) + offset.x, y: CGFloat(y), width: 2, height: 2)), with: .color(tint))
                    }
                }
            }
            // Physical-looking status light and a short stepped pulse etched on the top face.
            context.fill(Path(CGRect(x: offset.x + 91, y: 89, width: 4, height: 2)),
                         with: .color(paused ? PixelPalette.yellow : PixelPalette.cyan))
            for (x, y) in [(60,46),(62,46),(64,48),(66,50),(68,52),(70,50),(72,48),(74,46),(76,44),(78,46),(80,48),(82,48)] {
                context.fill(Path(CGRect(x: offset.x + CGFloat(x), y: CGFloat(y), width: 2, height: 2)),
                             with: .color(Color(red: 0.57, green: 0.45, blue: 0.25)))
            }
            // Sparse activity particles become brighter under actual load; they dim while sampling is paused.
            for index in 0..<12 {
                let x = 91 + (index * 17) % 57
                let y = 12 + (index * 11) % 24
                context.fill(Path(CGRect(x: offset.x + CGFloat(x), y: CGFloat(y), width: 2, height: 2)),
                             with: .color(PixelPalette.yellow.opacity(index < Int(load / 9) && !paused ? 0.7 : 0.12)))
            }
        }
    }
}
