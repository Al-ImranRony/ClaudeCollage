//
//  StickerOverlayRenderingTests.swift
//  ClaudeCollageTests
//
//  Step 03a slice 6 — the sticker model, shared rendering helper, catalog, and
//  template seeding. Mirrors the slice-5 text coverage: backward-compatible state
//  decoding (pre-sticker projects keep loading), the overlay's defensive Codable,
//  the normalized-geometry math that keeps the live canvas and export in sync, and
//  proof the renderer actually composites a sticker.
//

import XCTest
import UIKit
@testable import ClaudeCollage

final class StickerOverlayRenderingTests: XCTestCase {

    // MARK: - GridEditorState carries stickers through the undo/persistence codec

    func testStateEncodesAndDecodesStickerOverlays() throws {
        var state = GridEditorState(template: .twoUpHorizontal)
        state.stickerOverlays = [
            StickerOverlay(stickerID: "celebration.star", symbolName: "star.fill",
                           colorHex: "#F5C542", center: CGPoint(x: 0.7, y: 0.3),
                           sizeNorm: 0.2, rotation: 0.5),
        ]
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(GridEditorState.self, from: data)

        XCTAssertEqual(decoded.stickerOverlays.count, 1)
        XCTAssertEqual(decoded.stickerOverlays[0].symbolName, "star.fill")
        XCTAssertEqual(decoded.stickerOverlays[0].center.x, 0.7, accuracy: 0.0001)
        XCTAssertEqual(decoded.stickerOverlays[0].rotation, 0.5, accuracy: 0.0001)
        XCTAssertEqual(decoded, state, "Stickers are part of the value snapshot / undo unit")
    }

    func testLegacyStateWithoutStickersDecodesToEmpty() throws {
        // A pre-slice-6 project blob has no `stickerOverlays` key.
        let state = GridEditorState(template: .twoUpHorizontal)
        let data = try JSONEncoder().encode(state)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "stickerOverlays")
        let stripped = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(GridEditorState.self, from: stripped)
        XCTAssertEqual(decoded.stickerOverlays, [], "Missing stickers key must decode to an empty list")
    }

    func testStickerDecodesWithDefaultsForMissingFields() throws {
        let json = Data("""
        { "id": "\(UUID().uuidString)", "symbolName": "heart.fill" }
        """.utf8)
        let overlay = try JSONDecoder().decode(StickerOverlay.self, from: json)
        XCTAssertEqual(overlay.symbolName, "heart.fill")
        XCTAssertEqual(overlay.opacity, 1, accuracy: 0.0001)
        XCTAssertEqual(overlay.sizeNorm, 0.28, accuracy: 0.0001, "Missing size falls back to the default")
        XCTAssertEqual(overlay.center, CGPoint(x: 0.5, y: 0.5))
    }

    // MARK: - Shared rendering math (preview == export)

    func testNormalizedStickerResolvesToCenteredSquareBox() {
        let overlay = StickerOverlay(center: CGPoint(x: 0.5, y: 0.25), sizeNorm: 0.2)
        let rect = StickerRendering.frame(for: overlay, in: CGSize(width: 1000, height: 2000))
        // Side = 0.2 × width = 200; centred at (500, 500).
        XCTAssertEqual(rect, CGRect(x: 400, y: 400, width: 200, height: 200))
    }

    func testStickerImageResolvesSymbolAndFallsBack() {
        let good = StickerOverlay(symbolName: "star.fill")
        XCTAssertNotNil(StickerRendering.image(for: good, sidePx: 64))

        let bad = StickerOverlay(symbolName: "totally.not.a.symbol.xyz")
        XCTAssertNotNil(StickerRendering.image(for: bad, sidePx: 64),
                        "A missing symbol must fall back rather than render blank")
    }

    // MARK: - Export path actually composites the sticker

    func testRendererDrawsStickerOverlay() throws {
        let canvas = CGSize(width: 200, height: 200)
        let blank = RenderRequest(canvasSize: canvas, background: .white, cells: [])
        let withSticker = RenderRequest(
            canvasSize: canvas, background: .white, cells: [],
            stickerOverlays: [StickerOverlay(symbolName: "star.fill", colorHex: "#000000",
                                             center: CGPoint(x: 0.5, y: 0.5), sizeNorm: 0.6)]
        )
        let renderer = CollageRenderer()
        let a = try XCTUnwrap(renderer.render(blank, scale: 1))
        let b = try XCTUnwrap(renderer.render(withSticker, scale: 1))
        XCTAssertGreaterThan(Self.darkPixelCount(b), Self.darkPixelCount(a),
                             "Rendering a sticker must add ink to the canvas")
    }

    // MARK: - Sticker catalog

    @MainActor
    func testCatalogLoadsThreePacksOfTwenty() {
        let catalog = StickerCatalog(bundle: Bundle(for: CollageRenderer.self))
        let packs = catalog.loadPacks()
        XCTAssertEqual(packs.count, 3, "Three bundled sticker packs")
        let ids = Set(packs.map(\.id))
        XCTAssertEqual(ids, ["basic", "nature", "celebration"])
        for pack in packs {
            XCTAssertEqual(pack.stickers.count, 20, "\(pack.id): a pack ships 20 stickers")
        }
        // Every sticker id is globally unique so seeding/lookup is unambiguous.
        let allIDs = packs.flatMap { $0.stickers.map(\.id) }
        XCTAssertEqual(Set(allIDs).count, allIDs.count, "Sticker ids must be unique across packs")
        XCTAssertNotNil(catalog.entry(for: "celebration.star"))
    }

    // MARK: - Template sticker zones seed overlays

    @MainActor
    func testTemplateStickerZonesSeedOverlays() throws {
        let template = try TemplateParser().parse(data: Data("""
        {
          "id": "st", "name": "Sticker Test", "category": "birthday", "isPremium": false,
          "canvasAspectRatio": "1:1",
          "cells": [
            { "id": "p", "type": "photo", "shape": "rectangle",
              "frame": { "x": 0.1, "y": 0.1, "width": 0.8, "height": 0.6 } },
            { "id": "s", "type": "sticker", "stickerID": "celebration.star",
              "frame": { "x": 0.6, "y": 0.6, "width": 0.2, "height": 0.2 } }
          ],
          "background": { "type": "solid", "color": "#FFFFFF" }
        }
        """.utf8))

        let stickers = TemplateService.stickerOverlays(for: template)
        XCTAssertEqual(stickers.count, 1)
        XCTAssertEqual(stickers[0].stickerID, "celebration.star")
        XCTAssertEqual(stickers[0].symbolName, "star.fill", "Resolved from the sticker catalog")
        XCTAssertEqual(stickers[0].center.x, 0.7, accuracy: 0.0001, "Zone centre → sticker centre")
        XCTAssertEqual(stickers[0].sizeNorm, 0.2, accuracy: 0.0001, "Zone width → sticker size")
    }

    // MARK: - View model add / remove is undoable

    @MainActor
    func testViewModelAddAndRemoveStickerAreUndoable() {
        let vm = GridEditorViewModel()
        XCTAssertTrue(vm.stickerOverlays.isEmpty)

        let id = vm.addSticker(StickerOverlay(stickerID: "basic.star", symbolName: "star.fill"))
        XCTAssertEqual(vm.stickerOverlays.count, 1)

        vm.removeSticker(id: id)
        XCTAssertTrue(vm.stickerOverlays.isEmpty)

        vm.undo()   // undo the removal → sticker returns
        XCTAssertEqual(vm.stickerOverlays.count, 1)
        vm.undo()   // undo the addition → empty again
        XCTAssertTrue(vm.stickerOverlays.isEmpty)
    }

    // MARK: - Helpers

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
