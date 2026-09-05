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

    func testDrawingAPillStyleProducesDifferentPixelsThanPlain() {
        // The pill background is painted in `draw`, not in the attributes, so this
        // is the only way to prove it lands.
        func render(_ style: TextStyle) -> Data? {
            var overlay = TextOverlay(text: "Hello",
                                      colorHex: "#000000",
                                      frame: CGRect(x: 0, y: 0, width: 1, height: 1))
            overlay.style = style
            let size = CGSize(width: 200, height: 100)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.pngData { ctx in
                TextRendering.draw(overlay,
                                   in: CGRect(origin: .zero, size: size),
                                   fontScale: 0.2,
                                   context: ctx.cgContext)
            }
        }

        let plain = render(TextStyle(kind: .plain))
        let pill = render(TextStyle(kind: .pill, colorHex: "#FFCC00", width: 6))

        XCTAssertNotNil(plain)
        XCTAssertNotNil(pill)
        XCTAssertNotEqual(plain, pill, "A pill background must actually be painted")
    }
}
