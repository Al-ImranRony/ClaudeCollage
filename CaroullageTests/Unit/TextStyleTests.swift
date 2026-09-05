//
//  TextStyleTests.swift
//  CaroullageTests
//
//  The tier-2 text presentation model. The decode tests matter more than they look:
//  every already-saved project must keep rendering exactly as it does today, which
//  means a snapshot written before this field existed has to decode to `.plain`.
//

import XCTest
import CoreGraphics
import UIKit
@testable import Caroullage

final class TextStyleTests: XCTestCase {

    func testTheDefaultStyleIsPlain() {
        XCTAssertEqual(TextStyle().kind, .plain)
    }

    func testEveryKindIsRoundTripped() throws {
        for kind in TextStyle.Kind.allCases {
            let style = TextStyle(kind: kind, colorHex: "#112233", width: 9)
            let data = try JSONEncoder().encode(style)
            let decoded = try JSONDecoder().decode(TextStyle.self, from: data)
            XCTAssertEqual(decoded, style, "\(kind) must survive a round trip")
        }
    }

    func testAnUnknownKindFallsBackToPlainRatherThanThrowing() throws {
        // A project written by a future build must still open in this one.
        let json = Data(##"{"kind":"hologram","colorHex":"#000000","width":6}"##.utf8)
        let decoded = try JSONDecoder().decode(TextStyle.self, from: json)
        XCTAssertEqual(decoded.kind, .plain)
    }

    func testAnEmptyObjectDecodesToTheDefaults() throws {
        let decoded = try JSONDecoder().decode(TextStyle.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, TextStyle())
    }

    func testAnOverlaySavedBeforeStylesExistedDecodesToPlain() throws {
        // The exact shape a pre-change snapshot has: no `style` key at all.
        let json = Data(#"""
        {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","text":"hi","fontName":"SFProDisplay-Semibold",
         "fontSize":64,"colorHex":"#000000","alignmentRaw":"center","letterSpacing":0,
         "lineHeight":1.1,"opacity":1,"isBold":false,"isItalic":false,"isUnderlined":false,
         "frameX":0,"frameY":0,"frameWidth":1,"frameHeight":1}
        """#.utf8)

        let overlay = try JSONDecoder().decode(TextOverlay.self, from: json)

        XCTAssertEqual(overlay.style, TextStyle())
        XCTAssertEqual(overlay.text, "hi")
    }

    func testAnOverlayRoundTripsItsStyle() throws {
        var overlay = TextOverlay(text: "hi")
        overlay.style = TextStyle(kind: .stroke, colorHex: "#FF0000", width: 4)

        let data = try JSONEncoder().encode(overlay)
        let decoded = try JSONDecoder().decode(TextOverlay.self, from: data)

        XCTAssertEqual(decoded.style, overlay.style)
    }

    func testANegativeWidthIsClampedOnDecode() throws {
        // A corrupt or hand-edited project must not produce a negative stroke width
        // or a negative-radius shadow downstream.
        let json = Data(##"{"kind":"stroke","colorHex":"#000000","width":-5}"##.utf8)
        let decoded = try JSONDecoder().decode(TextStyle.self, from: json)
        XCTAssertEqual(decoded.width, 0)
    }

    func testStylesDifferingOnlyInWidthAreNotEqual() {
        XCTAssertNotEqual(
            TextStyle(kind: .stroke, colorHex: "#000000", width: 4),
            TextStyle(kind: .stroke, colorHex: "#000000", width: 8))
    }

    // MARK: - Rendering

    private func attributes(for style: TextStyle) -> [NSAttributedString.Key: Any] {
        var overlay = TextOverlay(text: "Hello", fontSize: 64)
        overlay.style = style
        let string = TextRendering.attributedString(for: overlay, fontScale: 1)
        return string.attributes(at: 0, effectiveRange: nil)
    }

    func testPlainAddsNoStrokeAndNoShadow() {
        let attrs = attributes(for: TextStyle(kind: .plain))
        XCTAssertNil(attrs[.strokeWidth])
        XCTAssertNil(attrs[.shadow])
        XCTAssertNil(attrs[.backgroundColor])
    }

    func testStrokeUsesANegativeWidthSoTheFillIsKept() {
        // A POSITIVE .strokeWidth draws the outline ONLY and hollows the glyph out.
        // Negative means "stroke and fill", which is what a caption outline needs.
        let attrs = attributes(for: TextStyle(kind: .stroke, colorHex: "#FF0000", width: 4))
        let width = try? XCTUnwrap(attrs[.strokeWidth] as? CGFloat)
        XCTAssertNotNil(width)
        XCTAssertLessThan(width ?? 0, 0)
        XCTAssertNotNil(attrs[.strokeColor])
    }

    func testShadowAndGlowBothInstallAShadow() {
        XCTAssertNotNil(attributes(for: TextStyle(kind: .shadow))[.shadow])
        XCTAssertNotNil(attributes(for: TextStyle(kind: .glow))[.shadow])
    }

    func testStrokeWidthScalesWithTheCanvas() {
        // Reference-canvas points must scale like fontSize does, or a thumbnail
        // gets a stroke as thick as the full-resolution export.
        var overlay = TextOverlay(text: "Hello", fontSize: 64)
        overlay.style = TextStyle(kind: .stroke, colorHex: "#000000", width: 8)

        let full = TextRendering.attributedString(for: overlay, fontScale: 1)
            .attributes(at: 0, effectiveRange: nil)[.strokeWidth] as? CGFloat
        let half = TextRendering.attributedString(for: overlay, fontScale: 0.5)
            .attributes(at: 0, effectiveRange: nil)[.strokeWidth] as? CGFloat

        XCTAssertNotNil(full)
        XCTAssertNotNil(half)
        XCTAssertEqual(abs(half ?? 0), abs(full ?? 0) / 2, accuracy: 0.01)
    }

    /// Reads back the RGB of one pixel from a rendered `CGImage` (established
    /// pattern in this suite — see `EmptyCellChromeTests`/`RendererChromeTests`).
    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &pixels, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let offset = (y * image.width + x) * 4
        return (Int(pixels[offset]), Int(pixels[offset + 1]), Int(pixels[offset + 2]))
    }

    /// `#FFCC00`, the pill colour used below, within anti-aliasing/colour-space tolerance.
    private func isPillGold(_ p: (r: Int, g: Int, b: Int)) -> Bool {
        abs(p.r - 255) <= 2 && abs(p.g - 204) <= 2 && abs(p.b - 0) <= 2
    }

    func testPillBackgroundHugsTheMeasuredTextInsteadOfSpanningTheWholeBox() throws {
        // Short text in a WIDE box: a pill sized from the frame (the bug) paints
        // almost the entire box, while a pill sized from the measured text (the
        // fix) hugs just the glyphs. The two sample points below distinguish them
        // without depending on exact font metrics.
        var overlay = TextOverlay(text: "Hi", fontSize: 32,
                                  colorHex: "#000000",
                                  frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        overlay.style = TextStyle(kind: .pill, colorHex: "#FFCC00", width: 16)
        let canvasSize = CGSize(width: 300, height: 120)
        let absoluteFrame = CGRect(origin: .zero, size: canvasSize)
        let fontScale: CGFloat = 1

        // Ground truth for where the glyphs actually land, measured the same way
        // `draw` measures height — used here for width too, so the test doesn't
        // hardcode font metrics.
        let attributed = TextRendering.attributedString(for: overlay, fontScale: fontScale)
        let measured = attributed.boundingRect(
            with: CGSize(width: absoluteFrame.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let textOriginX = (absoluteFrame.width - measured.width) / 2   // centered alignment
        let textMidY = Int((absoluteFrame.height - measured.height) / 2 + measured.height / 2)

        // Scale must be pinned to 1 (as `VideoOverlayRenderer` does) so the CGImage's
        // pixel grid matches the point-space geometry below 1:1 — otherwise the
        // simulator's device scale silently multiplies every coordinate.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        let image = renderer.image { ctx in
            TextRendering.draw(overlay, in: absoluteFrame, fontScale: fontScale, context: ctx.cgContext)
        }.cgImage
        let cgImage = try XCTUnwrap(image)

        // A few points inside the tight pill's left padding — left of the glyphs
        // themselves (so ink-free), but only inside the PILL once its width comes
        // from the measured text rather than the whole frame.
        let insideTightPill = pixel(cgImage, x: Int(textOriginX - 4), y: textMidY)
        // Deep inside the box but far from the short "Hi" — covered by a
        // full-width pill, but well outside a tight one.
        let farFromText = pixel(cgImage, x: 6, y: textMidY)

        XCTAssertTrue(isPillGold(insideTightPill), "the pill must still reach just past the measured text")
        XCTAssertFalse(isPillGold(farFromText), "a pill must not span the whole text-box width — this is the full-width-span bug")
    }

    func testHighlightSetsTheBackgroundColorAttributeInsteadOfPaintingInDraw() {
        // `.backgroundColor` is an NSAttributedString attribute, so it renders
        // identically wherever `attributedString(for:fontScale:)` is consumed —
        // the live canvas's UILabel AND both export paths. This is what guarantees
        // canvas/export parity for `.highlight` (unlike `.pill`, which paints
        // separately in `draw` and must be reproduced on the canvas by hand).
        let attrs = attributes(for: TextStyle(kind: .highlight, colorHex: "#FFFF00", width: 6))
        let background = attrs[.backgroundColor] as? UIColor
        XCTAssertEqual(background?.hexStringRGB, "#FFFF00")
    }
}
