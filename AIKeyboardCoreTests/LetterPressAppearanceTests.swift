import SwiftUI
import UIKit
import XCTest

@testable import AIKeyboardCore

/// The letter-key press has to read around the thumb, not as a 1-step fade.
///
/// **Two builds in a row were named after this and still passed against a
/// press you could not see.** 0xE4E1DB sat on the same step as the keyboard
/// chrome; 0xD4D0C8 cleared it by 0.14 luma and still read as a tint. A test
/// that only asks "is pressed darker than rest" is true of both. The
/// assertions below are the deltas those two fail.
final class LetterPressAppearanceTests: XCTestCase {

    /// 0xD4D0C8 vs `background` is 0.14 luma — under the thumb that is the
    /// chrome, not a key. The warm grey that replaced it is 0.33.
    func testAPressedLetterClearsTheKeyboardBackgroundInLightMode() {
        let pressed = luminance(Theme.Keys.letterPressed, style: .light)
        let chrome = luminance(Theme.Keys.background, style: .light)
        XCTAssertGreaterThan(
            chrome - pressed, 0.25,
            "pressed \(pressed) vs background \(chrome) — 0xD4D0C8 was 0.14")
    }

    /// Dark mode lifts rather than sinking into the chrome, and 0x7C8082 was
    /// only 0.12 luma above rest — the same 1-step fade, the other way.
    func testAPressedLetterLiftsOffItsRestingCapInDarkMode() {
        let pressed = luminance(Theme.Keys.letterPressed, style: .dark)
        let rest = luminance(Theme.Keys.letter, style: .dark)
        XCTAssertGreaterThan(
            pressed - rest, 0.15,
            "pressed \(pressed) vs rest \(rest) — 0x7C8082 was 0.12")
    }

    /// Cream-on-mid in dark is 2.5:1. The glyph stays graphite so the lighter
    /// fill can exist at all.
    func testThePressedLetterGlyphStaysGraphiteOnTheMidFill() {
        for style: UIUserInterfaceStyle in [.light, .dark] {
            let fill = luminance(Theme.Keys.letterPressed, style: style)
            let glyph = luminance(Theme.Keys.labelOnLetterPressed, style: style)
            let ratio = contrast(fill, glyph)
            XCTAssertGreaterThanOrEqual(
                ratio, 4.5,
                "\(style == .dark ? "dark" : "light") \(ratio) — cream on 0x989C9E is 2.5")
        }
    }

    // MARK: - Colour math

    private func luminance(_ color: Color, style: UIUserInterfaceStyle) -> CGFloat {
        let resolved = UIColor(color).resolvedColor(
            with: UITraitCollection(userInterfaceStyle: style))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    private func linear(_ channel: CGFloat) -> CGFloat {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    private func contrast(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        let hi = max(a, b), lo = min(a, b)
        return (hi + 0.05) / (lo + 0.05)
    }
}
