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
}
