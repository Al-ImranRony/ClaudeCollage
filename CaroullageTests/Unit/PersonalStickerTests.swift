//
//  PersonalStickerTests.swift
//  CaroullageTests
//
//  Step 05 batch B — personal (image-backed) stickers.
//
//  The lift itself needs Vision and so is device-only, but everything the app
//  does with the RESULT is testable here: the overlay stays backward compatible,
//  the one rendering funnel that guarantees preview == export handles bitmaps,
//  and a missing bitmap degrades safely rather than turning into a star the user
//  never chose.
//

import XCTest
import CoreGraphics
import SwiftData
import UIKit
@testable import Caroullage

final class PersonalStickerTests: XCTestCase {

    private func makeSubject(width: Int = 60, height: Int = 40) -> CGImage {
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.7, blue: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    // MARK: - Model compatibility

    func testOverlayDefaultsToASymbolSticker() {
        // Every sticker that existed before Step 05 must stay a symbol sticker.
        XCTAssertNil(StickerOverlay().imageID)
    }

    func testLegacySnapshotWithoutImageIDStillDecodes() throws {
        // A persisted overlay from an earlier build has no `imageID` key at all.
        let legacy = """
        {"id":"\(UUID().uuidString)","stickerID":"basic.star","symbolName":"star.fill",
         "colorHex":"#E86A2A","opacity":1,"centerX":0.5,"centerY":0.5,
         "sizeNorm":0.28,"rotation":0}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(StickerOverlay.self, from: legacy)
        XCTAssertNil(decoded.imageID, "Absent means symbol sticker")
        XCTAssertEqual(decoded.symbolName, "star.fill")
    }

    func testImageBackedOverlayRoundTrips() throws {
        let imageID = UUID()
        let overlay = StickerOverlay(stickerID: "personal.x", imageID: imageID)
        let data = try JSONEncoder().encode(overlay)
        let decoded = try JSONDecoder().decode(StickerOverlay.self, from: data)
        XCTAssertEqual(decoded.imageID, imageID)
    }

    // MARK: - Rendering (the preview == export funnel)

    func testPersonalStickerRendersItsOwnBitmap() {
        let overlay = StickerOverlay(imageID: UUID())
        let source = makeSubject()
        let rendered = StickerRendering.image(for: overlay, sidePx: 100, source: source)

        XCTAssertNotNil(rendered)
        // Its own pixels, at its own aspect — not squared off into a symbol box.
        XCTAssertEqual(rendered?.size.width ?? 0, 60, accuracy: 1)
        XCTAssertEqual(rendered?.size.height ?? 0, 40, accuracy: 1)
    }

    func testPersonalStickerWithNoBitmapDrawsNothing() {
        // A library entry deleted, or a project opened where the bitmap is absent.
        // Falling back to the default star would put a sticker on the canvas that
        // the user never chose, which is worse than drawing nothing.
        let overlay = StickerOverlay(imageID: UUID())
        XCTAssertNil(StickerRendering.image(for: overlay, sidePx: 100, source: nil))
    }

    func testSymbolStickerIsUnaffectedByTheNewParameter() {
        let overlay = StickerOverlay(symbolName: "star.fill")
        XCTAssertNotNil(StickerRendering.image(for: overlay, sidePx: 100))
        XCTAssertNotNil(StickerRendering.image(for: overlay, sidePx: 100, source: makeSubject()),
                        "A stray source must not break the symbol path")
    }

    func testOpacityAppliesToAPersonalSticker() {
        var overlay = StickerOverlay(imageID: UUID())
        overlay.opacity = 0.5
        XCTAssertNotNil(StickerRendering.image(for: overlay, sidePx: 100, source: makeSubject()))
    }

    // MARK: - Store

    @MainActor
    private func makeStore() throws -> PersonalStickerStore {
        let schema = Schema([CollageProject.self, CollageCell.self, PersonalSticker.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return PersonalStickerStore(container: container)
    }

    @MainActor
    func testSavingAndReadingBackASticker() throws {
        let store = try makeStore()
        XCTAssertTrue(store.isEmpty())

        let id = try XCTUnwrap(store.save(makeSubject()))
        XCTAssertFalse(store.isEmpty())

        let restored = try XCTUnwrap(store.image(for: id))
        XCTAssertEqual(restored.width, 60)
        XCTAssertEqual(restored.height, 40)
    }

    @MainActor
    func testSavedSubjectKeepsItsAlpha() throws {
        // PNG, not JPEG — a lifted subject without alpha is just a rectangle.
        let store = try makeStore()
        let ctx = CGContext(
            data: nil, width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 5, y: 5, width: 10, height: 10))   // corners stay transparent
        let subject = ctx.makeImage()!

        let id = try XCTUnwrap(store.save(subject))
        let restored = try XCTUnwrap(store.image(for: id))

        var pixels = [UInt8](repeating: 0, count: 20 * 20 * 4)
        let read = CGContext(
            data: &pixels, width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 80,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        read.draw(restored, in: CGRect(x: 0, y: 0, width: 20, height: 20))
        XCTAssertEqual(pixels[3], 0, "The transparent corner survived the round trip")
    }

    @MainActor
    func testNewestStickerIsOfferedFirst() throws {
        let store = try makeStore()
        _ = store.save(makeSubject(width: 10, height: 10))
        let second = try XCTUnwrap(store.save(makeSubject(width: 20, height: 20)))

        XCTAssertEqual(store.allStickers().first?.id, second,
                       "A just-lifted subject should be the first one offered")
    }

    @MainActor
    func testResolvingImagesForOverlays() throws {
        let store = try makeStore()
        let id = try XCTUnwrap(store.save(makeSubject()))
        let overlays = [
            StickerOverlay(imageID: id),
            StickerOverlay(symbolName: "star.fill"),   // symbol: contributes nothing
        ]

        let resolved = store.images(for: overlays)
        XCTAssertEqual(resolved.count, 1)
        XCTAssertNotNil(resolved[id])
    }

    @MainActor
    func testDeletingRemovesItFromTheLibrary() throws {
        let store = try makeStore()
        let id = try XCTUnwrap(store.save(makeSubject()))
        store.delete(id: id)

        XCTAssertTrue(store.isEmpty())
        XCTAssertNil(store.image(for: id))
    }

    @MainActor
    func testUnknownIDResolvesToNothing() throws {
        let store = try makeStore()
        XCTAssertNil(store.image(for: UUID()))
    }
}

private func XCTAssertEqual(
    _ lhs: CGFloat, _ rhs: CGFloat, accuracy: CGFloat,
    file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertLessThanOrEqual(abs(lhs - rhs), accuracy,
                             "\(lhs) is not within \(accuracy) of \(rhs)", file: file, line: line)
}
