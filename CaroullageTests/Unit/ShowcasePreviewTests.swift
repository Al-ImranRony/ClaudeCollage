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
        let showcased = Set(catalog.manifest?.templates.keys ?? [:].keys)

        let undressed = try XCTUnwrap(
            service.templates.first { !showcased.contains($0.id) },
            "expected at least one bundled template outside the manifest"
        )
        try XCTSkipIf(undressed.id.isEmpty, "no un-showcased template to exercise the fallback")

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
}
