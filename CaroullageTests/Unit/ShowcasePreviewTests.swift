//
//  ShowcasePreviewTests.swift
//  CaroullageTests
//
//  Step 07 — the load-bearing guarantee of the Home showcase: a preview is the
//  template rendered through the SAME `CollageRenderer` the editor and exporter
//  use, with the bundled sample photos composited into the template's REAL zones.
//  That is what makes "you can recreate exactly what you tapped" structural
//  rather than aspirational, so these tests hold the shared path in place:
//  every showcased id renders, an un-showcased id degrades to nil (the caller
//  falls back to the schematic rather than presenting empty wells as a showcase),
//  carousels composite into a swipeable strip, results cache, and — the one that
//  actually proves photography landed — a showcase preview's pixels differ from
//  the empty schematic thumbnail's at the same size.
//

import XCTest
@testable import Caroullage

@MainActor
final class ShowcasePreviewTests: XCTestCase {

    /// The app bundle — the unit test bundle carries none of the app's resources.
    private var appBundle: Bundle { Bundle(for: CollageRenderer.self) }

    private func makeCatalog() -> SampleContentCatalog {
        SampleContentCatalog(bundle: appBundle)
    }

    private func makeTemplateService() -> TemplateService {
        let service = TemplateService(bundle: appBundle)
        service.loadBundledTemplates()
        service.loadBundledCarouselTemplates()
        return service
    }

    /// A `CGImage`'s raw backing bytes, for proving two renders differ.
    private func pixelData(_ image: CGImage) -> Data? {
        image.dataProvider?.data as Data?
    }

    // MARK: - Templates

    func testShowcasePreviewRendersForEveryManifestTemplate() throws {
        let catalog = makeCatalog()
        let service = makeTemplateService()
        let entries = try XCTUnwrap(catalog.manifest?.templates)

        for id in entries.keys {
            let template = try XCTUnwrap(
                service.templates.first { $0.id == id },
                "\(id): manifest names a template that is not in the bundled catalog"
            )
            XCTAssertNotNil(
                service.showcasePreview(for: template, sampleContent: catalog),
                "\(id): every showcased template must produce a photo-real preview"
            )
        }
    }

    func testShowcasePreviewNilWithoutManifestEntry() throws {
        let catalog = makeCatalog()
        let service = makeTemplateService()

        // Parsed from JSON with an id the manifest cannot know, rather than
        // hunting the catalog for a template nobody dressed.
        //
        // It used to do the hunting, and that made the test quietly dependent on
        // the catalog being incompletely dressed — so it broke the moment the
        // Templates tab went photo-real and all thirty-three gained photography.
        // The behaviour under test was never "some template is undressed"; it is
        // "no manifest entry means nil", and an id the manifest has never heard
        // of states that directly and permanently.
        let json = """
        {
          "id": "not-in-any-manifest", "name": "Unknown", "category": "test",
          "isPremium": false, "canvasAspectRatio": "1:1",
          "cells": [
            { "type": "photo", "shape": "rectangle",
              "frame": { "x": 0, "y": 0, "width": 1, "height": 1 } }
          ]
        }
        """
        let undressed = try TemplateParser().parse(data: Data(json.utf8))
        XCTAssertNil(catalog.samplePhotos(forTemplateID: undressed.id),
                     "the fixture must genuinely be absent from the manifest")

        XCTAssertNil(
            service.showcasePreview(for: undressed, sampleContent: catalog),
            "\(undressed.id): without sample photos the caller must fall back to the "
                + "schematic thumbnail, not be handed a preview of empty wells"
        )
    }

    // MARK: - Carousels

    func testCarouselShowcaseCompositesFrames() throws {
        let catalog = makeCatalog()
        let service = makeTemplateService()
        let entries = try XCTUnwrap(catalog.manifest?.carousels)

        for id in entries.keys {
            let template = try XCTUnwrap(
                service.carouselTemplates.first { $0.id == id },
                "\(id): manifest names a carousel that is not in the bundled catalog"
            )
            let preview = try XCTUnwrap(
                service.showcasePreview(for: template, sampleContent: catalog),
                "\(id): every showcased carousel must produce a photo-real strip"
            )
            if template.frames.count >= 2 {
                XCTAssertGreaterThan(
                    preview.width, preview.height,
                    "\(id): a multi-frame carousel must composite side by side — a strip "
                        + "taller than it is wide means only one frame was rendered"
                )
            }
        }
    }

    // MARK: - Caching

    func testShowcasePreviewIsCached() throws {
        let catalog = makeCatalog()
        let service = makeTemplateService()
        let id = try XCTUnwrap(catalog.manifest?.templates.keys.sorted().first)
        let template = try XCTUnwrap(service.templates.first { $0.id == id })

        XCTAssertNotNil(service.showcasePreview(for: template, sampleContent: catalog))

        let start = CFAbsoluteTimeGetCurrent()
        let second = service.showcasePreview(for: template, sampleContent: catalog)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertNotNil(second)
        XCTAssertLessThan(
            elapsed, 0.05,
            "the second request must be a cache hit — \(elapsed)s says it re-rendered"
        )
    }

    // MARK: - Photography actually landed

    func testShowcasePreviewDiffersFromEmptyThumbnail() throws {
        let catalog = makeCatalog()
        let service = makeTemplateService()
        let id = try XCTUnwrap(catalog.manifest?.templates.keys.sorted().first)
        let template = try XCTUnwrap(service.templates.first { $0.id == id })

        // Same `maxDimension` for both, so differing sizes cannot be what makes
        // the comparison pass — the bytes have to differ because photos were
        // composited where the schematic draws empty wells.
        let dimension: CGFloat = 320
        let showcase = try XCTUnwrap(
            service.showcasePreview(for: template, sampleContent: catalog, maxDimension: dimension)
        )
        let schematic = try XCTUnwrap(service.thumbnail(for: template, maxDimension: dimension))

        XCTAssertEqual(showcase.width, schematic.width)
        XCTAssertEqual(showcase.height, schematic.height)

        let showcaseBytes = try XCTUnwrap(pixelData(showcase))
        let schematicBytes = try XCTUnwrap(pixelData(schematic))
        XCTAssertNotEqual(
            showcaseBytes, schematicBytes,
            "\(id): the showcase preview is pixel-identical to the empty schematic — "
                + "no sample photography was composited in"
        )
    }

    // MARK: - Art-zone alignment

    /// A pixel's RGB, read from `image` at (`x`, `y`) in TOP-LEFT coordinates —
    /// x rightward from 0, y DOWNWARD from 0 — the same convention every `frame`
    /// in this codebase uses. Matches the sampling helper already proven out in
    /// `RendererChromeTests`/`EmptyCellChromeTests`: drawing the whole image into
    /// a same-size buffer context at (0, 0) and indexing the buffer by `y * width`
    /// keeps row 0 of the buffer at the visual top — verified independently
    /// against a known-content probe image before trusting it here, since a
    /// CGImage's raw row order flipping is exactly the kind of bug this app has
    /// been bitten by before.
    private static func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &pixels, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let clampedX = min(max(x, 0), image.width - 1)
        let clampedY = min(max(y, 0), image.height - 1)
        let offset = (clampedY * image.width + clampedX) * 4
        return (pixels[offset], pixels[offset + 1], pixels[offset + 2])
    }

    /// Manhattan distance between two RGB triples — small if the colours are
    /// close, large if they are not. Used instead of exact equality because the
    /// renderer resamples the source photo into the cell, and JPEG/interpolation
    /// both nudge individual bytes by a little.
    private static func colorDistance(_ a: (r: UInt8, g: UInt8, b: UInt8), _ b: (r: UInt8, g: UInt8, b: UInt8)) -> Int {
        abs(Int(a.r) - Int(b.r)) + abs(Int(a.g) - Int(b.g)) + abs(Int(a.b) - Int(b.b))
    }

    /// A synthetic template — 7 zones stacked top to bottom, alternating
    /// `.photo` / `.art` / `.photo` / `.art` / `.photo` / `.art` / `.photo` — used
    /// only to exercise the alignment guard in `showcasePreview(for:
    /// CollageTemplate...)`. No bundled template has an `.art` zone today, so
    /// without this the guard is provably dead code. Deliberately reuses
    /// "grid-4cell-square" as its id: that is a REAL manifest entry (4 named
    /// photos), which lets this test drive the actual `SampleContentCatalog` and
    /// its real bundled sample photography — no synthetic manifest or fixture
    /// images needed, because the template value handed to `showcasePreview` is
    /// independent of whatever the bundled catalog registers under that id.
    /// `TemplateCell` and `CollageTemplate` are both `Decodable`-only (no
    /// memberwise initializer survives their custom `init(from:)`), so this goes
    /// through `TemplateParser` like any real template JSON would.
    private static let interleavedZonesTemplateJSON: Data = """
    {
      "id": "grid-4cell-square",
      "name": "Test Interleaved Zones",
      "category": "grid",
      "isPremium": false,
      "canvasAspectRatio": "1:1",
      "cells": [
        { "id": "r0", "type": "photo", "frame": { "x": 0, "y": 0.000000, "width": 1, "height": 0.142857 } },
        { "id": "r1", "type": "art",   "frame": { "x": 0, "y": 0.142857, "width": 1, "height": 0.142857 } },
        { "id": "r2", "type": "photo", "frame": { "x": 0, "y": 0.285714, "width": 1, "height": 0.142857 } },
        { "id": "r3", "type": "art",   "frame": { "x": 0, "y": 0.428571, "width": 1, "height": 0.142857 } },
        { "id": "r4", "type": "photo", "frame": { "x": 0, "y": 0.571428, "width": 1, "height": 0.142857 } },
        { "id": "r5", "type": "art",   "frame": { "x": 0, "y": 0.714285, "width": 1, "height": 0.142857 } },
        { "id": "r6", "type": "photo", "frame": { "x": 0, "y": 0.857142, "width": 1, "height": 0.142857 } }
      ],
      "background": { "type": "solid", "color": "#FFFFFF" }
    }
    """.data(using: .utf8)!

    /// The load-bearing test for the `.photo`/`.art` lockstep guard: proves the
    /// RIGHT photo lands on the RIGHT zone, not merely that a non-nil image came
    /// back. "grid-4cell-square" dresses in order [sample_portrait_01,
    /// sample_travel_01, sample_couple_01, sample_food_01]; consumed in that
    /// order against this template's photo/art/photo/art/photo/art/photo rows,
    /// row 2 (the 2nd `.photo` zone) must show sample_travel_01 and row 6 (the
    /// 4th) must show sample_food_01. If the guard regressed to consuming a
    /// photo for every cell regardless of zone type, sample_travel_01 would be
    /// eaten by row 1's `.art` zone and every photo after it would shift up one
    /// row — row 2 would show sample_couple_01 instead, and row 6 would run out
    /// of photos entirely. Comparing against each candidate's OWN centre pixel
    /// (rather than a hardcoded RGB literal) keeps the assertion honest even if
    /// the bundled asset is ever re-exported.
    func testArtZoneDoesNotConsumeAPhoto() throws {
        let catalog = makeCatalog()
        let service = makeTemplateService()
        let template = try TemplateParser().parse(data: Self.interleavedZonesTemplateJSON)

        let image = try XCTUnwrap(
            service.showcasePreview(for: template, sampleContent: catalog, maxDimension: 420),
            "the interleaved template has 4 `.photo` zones, matching grid-4cell-square's 4 "
                + "manifest photos exactly — this must render, not trip the count guard"
        )

        // `aspectFillRect` centres the scaled source image on the cell's centre
        // point (verified against `CollageRenderer.aspectFillRect` — panX/panY
        // are 0 and zoom is 1 for every showcase cell), so the pixel at a cell's
        // exact centre in the output equals the SOURCE photo's own centre pixel.
        let rowHeight = 1.0 / 7.0
        func rowCenterPixel(_ row: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
            let fractionY = (Double(row) + 0.5) * rowHeight
            let y = Int((fractionY * Double(image.height)).rounded())
            return Self.pixel(image, x: image.width / 2, y: y)
        }
        func sourceCenterPixel(_ name: String) throws -> (r: UInt8, g: UInt8, b: UInt8) {
            let source = try XCTUnwrap(catalog.image(named: name)?.cgImage)
            return Self.pixel(source, x: source.width / 2, y: source.height / 2)
        }

        let travelCenter = try sourceCenterPixel("sample_travel_01")
        let foodCenter = try sourceCenterPixel("sample_food_01")

        // Sanity: if these two references were not visually distinct, no
        // assertion below could actually distinguish "landed correctly" from
        // "landed on the wrong zone" — the test would pass no matter what the
        // guard did.
        XCTAssertGreaterThan(
            Self.colorDistance(travelCenter, foodCenter), 150,
            "sample_travel_01 and sample_food_01 are too visually similar for this test to prove anything"
        )

        let row2 = rowCenterPixel(2)
        let row6 = rowCenterPixel(6)

        XCTAssertLessThan(
            Self.colorDistance(row2, travelCenter), 40,
            "row 2 (2nd .photo zone) should show sample_travel_01 — the guard let a photo shift"
        )
        XCTAssertGreaterThan(
            Self.colorDistance(row2, foodCenter), 150,
            "row 2 shows sample_food_01 instead of sample_travel_01 — an .art zone ate a photo upstream"
        )

        XCTAssertLessThan(
            Self.colorDistance(row6, foodCenter), 40,
            "row 6 (4th .photo zone) should show sample_food_01 — the guard let a photo shift"
        )
        XCTAssertGreaterThan(
            Self.colorDistance(row6, travelCenter), 150,
            "row 6 shows sample_travel_01 instead of sample_food_01 — photos landed one zone early"
        )
    }
}
