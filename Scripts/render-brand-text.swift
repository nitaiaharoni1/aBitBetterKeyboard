#!/usr/bin/env swift

import AppKit

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count == 13 else {
    fail(
        "Usage: render-brand-text OUTPUT WIDTH HEIGHT X TOP MAX_WIDTH SIZE WEIGHT TRACKING COLOR LINE_HEIGHT TEXT"
    )
}

let arguments = CommandLine.arguments
guard
    let width = Int(arguments[2]),
    let height = Int(arguments[3]),
    let x = Double(arguments[4]),
    let top = Double(arguments[5]),
    let maxWidth = Double(arguments[6]),
    let size = Double(arguments[7]),
    let tracking = Double(arguments[9]),
    let lineHeight = Double(arguments[11])
else {
    fail("Text geometry must use numeric values")
}

let weights: [String: NSFont.Weight] = [
    "regular": .regular,
    "medium": .medium,
    "semibold": .semibold,
    "bold": .bold,
    "heavy": .heavy,
    "black": .black,
]
guard let weight = weights[arguments[8]] else {
    fail("Weight must be regular, medium, semibold, bold, heavy, or black")
}

let colorText = arguments[10].trimmingCharacters(in: CharacterSet(charactersIn: "#"))
guard colorText.count == 6, let colorValue = Int(colorText, radix: 16) else {
    fail("Color must be a six-digit hexadecimal value")
}

let color = NSColor(
    calibratedRed: CGFloat((colorValue >> 16) & 0xff) / 255,
    green: CGFloat((colorValue >> 8) & 0xff) / 255,
    blue: CGFloat(colorValue & 0xff) / 255,
    alpha: 1
)
// NSImage renders at the Mac's 2x backing scale. Work in points at half the
// requested pixel geometry so the resulting PNG has the exact pixel size the
// App Store compositor asked for.
let backingScale = 2.0
let paragraph = NSMutableParagraphStyle()
paragraph.minimumLineHeight = lineHeight / backingScale
paragraph.maximumLineHeight = lineHeight / backingScale
paragraph.lineBreakMode = .byClipping

let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: size / backingScale, weight: weight),
    .foregroundColor: color,
    .kern: tracking / backingScale,
    .paragraphStyle: paragraph,
]
let text = arguments[12] as NSString
let image = NSImage(
    size: NSSize(width: Double(width) / backingScale, height: Double(height) / backingScale),
    flipped: true
) { bounds in
    NSColor.clear.setFill()
    bounds.fill()
    text.draw(
        in: NSRect(
            x: x / backingScale,
            y: top / backingScale,
            width: maxWidth / backingScale,
            height: (Double(height) - top) / backingScale
        ),
        withAttributes: attributes
    )
    return true
}

var proposedRect = NSRect(origin: .zero, size: image.size)
guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
    fail("Could not render SF Pro text")
}
let representation = NSBitmapImageRep(cgImage: cgImage)
representation.size = image.size
guard let png = representation.representation(using: .png, properties: [:]) else {
    fail("Could not encode SF Pro text as PNG")
}

do {
    try png.write(to: URL(fileURLWithPath: arguments[1]), options: .atomic)
} catch {
    fail("Could not write \(arguments[1]): \(error)")
}
