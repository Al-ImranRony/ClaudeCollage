//
//  TextOverlayRenderingTests.swift
//  ClaudeCollageTests
//
//  Step 03a slice 5 — the text-zone model + shared rendering helper. Guards the
//  backward-compatible state decoding (so pre-slice-5 projects keep loading), the
//  overlay's defensive Codable, and the normalized-frame / font-trait math that
//  keeps the live canvas and the export in sync.
//

import XCTest
import UIKit
@testable import ClaudeCollage

final class TextOverlayRenderingTests: XCTestCase {

    // MARK: - GridEditorState carries overlays through the undo/persistence codec

    func testStateEncodesAndDecodesTextOverlays() throws {
        var state = GridEditorState(template: .twoUpHorizontal)
        state.textOverlays = [
            TextOverlay(text: "Hello", fontSize: 80, alignment: .leading,
                        isBold: true, frame: CGRect(x: 0.1, y: 0.2, width: 0.6, height: 0.1)),
        ]
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(GridEditorState.self, from: data)

        XCTAssertEqual(decoded.textOverlays.count, 1)
        XCTAssertEqual(decoded.textOverlays[0].text, "Hello")
        XCTAssertTrue(decoded.textOverlays[0].isBold)
        XCTAssertEqual(decoded.textOverlays[0].alignment, .leading)
        XCTAssertEqual(decoded.textOverlays[0].frame.origin.x, 0.1, accuracy: 0.0001)
        XCTAssertEqual(decoded, state, "Overlays are part of the value snapshot / undo unit")
    }

    func testLegacyStateWithoutOverlaysDecodesToEmpty() throws {
        // A Step 01–04 project blob has no `textOverlays` key. Encode a real state,
        // strip the key, and confirm it still loads (backward compatibility).
        let state = GridEditorState(template: .twoUpHorizontal)
        let data = try JSONEncoder().encode(state)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "textOverlays")
        let stripped = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(GridEditorState.self, from: stripped)
        XCTAssertEqual(decoded.textOverlays, [], "Missing overlays key must decode to an empty list")
    }

    // MARK: - TextOverlay defensive decoding

    func testOverlayDecodesWithoutNewStyleFields() throws {
        // A minimal object missing bold/italic/underline should default them false.
        let json = Data("""
        { "id": "\(UUID().uuidString)", "text": "Hi", "fontName": "Georgia", "fontSize": 40,
          "colorHex": "#112233", "alignmentRaw": "center", "letterSpacing": 0, "lineHeight": 1.2,
          "opacity": 1, "frameX": 0, "frameY": 0, "frameWidth": 1, "frameHeight": 0.2 }
        """.utf8)
        let overlay = try JSONDecoder().decode(TextOverlay.self, from: json)
        XCTAssertFalse(overlay.isBold)
        XCTAssertFalse(overlay.isItalic)
        XCTAssertFalse(overlay.isUnderlined)
        XCTAssertEqual(overlay.colorHex, "#112233")
    }

    // MARK: - Shared rendering math (preview == export)

    func testNormalizedFrameResolvesToAbsolutePixels() {
        let overlay = TextOverlay(frame: CGRect(x: 0.1, y: 0.25, width: 0.5, height: 0.2))
        let rect = TextRendering.frame(for: overlay, in: CGSize(width: 1000, height: 2000))
        XCTAssertEqual(rect, CGRect(x: 100, y: 500, width: 500, height: 400))
    }

    func testFontScaleScalesPointSize() {
        let overlay = TextOverlay(fontSize: 100)
        let full = TextRendering.font(for: overlay, fontScale: 1)
        let half = TextRendering.font(for: overlay, fontScale: 0.5)
        XCTAssertEqual(full.pointSize, 100, accuracy: 0.5)
        XCTAssertEqual(half.pointSize, 50, accuracy: 0.5)
    }

    func testBoldItalicApplyAsSymbolicTraits() {
        let overlay = TextOverlay(fontName: "Georgia", isBold: true, isItalic: true)
        let font = TextRendering.font(for: overlay, fontScale: 1)
        let traits = font.fontDescriptor.symbolicTraits
        XCTAssertTrue(traits.contains(.traitBold))
        XCTAssertTrue(traits.contains(.traitItalic))
    }

    func testUnnamedFontFallsBackInsteadOfBlank() {
        let overlay = TextOverlay(fontName: "TotallyNotAFont-Regular", fontSize: 48)
        let font = TextRendering.font(for: overlay, fontScale: 1)
        XCTAssertEqual(font.pointSize, 48, accuracy: 0.5, "A missing face must resolve to a real fallback font")
    }

    func testHexRoundTripsThroughUIColor() {
        XCTAssertEqual(UIColor(hex: "#E86A2A").hexStringRGB, "#E86A2A")
        XCTAssertEqual(UIColor(hex: "#000000").hexStringRGB, "#000000")
    }

    // MARK: - Export path actually composites the text

    /// The done-criterion is preview == export; the live canvas and the renderer
    /// share `TextRendering`, and here we prove the renderer path draws the text at
    /// all — a request with a visible overlay must differ from one without.
    func testRendererDrawsTextOverlay() throws {
        let canvas = CGSize(width: 200, height: 200)
        let blank = RenderRequest(canvasSize: canvas, background: .white, cells: [])
        let withText = RenderRequest(
            canvasSize: canvas, background: .white, cells: [],
            textOverlays: [TextOverlay(text: "ABC", fontSize: 48, colorHex: "#000000",
                                       frame: CGRect(x: 0.05, y: 0.35, width: 0.9, height: 0.3))],
            textFontScale: 1
        )
        let renderer = CollageRenderer()
        let a = try XCTUnwrap(renderer.render(blank, scale: 1))
        let b = try XCTUnwrap(renderer.render(withText, scale: 1))
        XCTAssertNotEqual(Self.darkPixelCount(a), Self.darkPixelCount(b),
                          "Rendering an overlay must add ink to the canvas")
        XCTAssertGreaterThan(Self.darkPixelCount(b), 0, "Black text on white must leave dark pixels")
    }

    /// Counts near-black pixels in a CGImage (rough ink measure for the assertion above).
    private static func darkPixelCount(_ image: CGImage) -> Int {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var count = 0
        for i in stride(from: 0, to: pixels.count, by: 4) where
            pixels[i] < 80 && pixels[i + 1] < 80 && pixels[i + 2] < 80 { count += 1 }
        return count
    }
}
