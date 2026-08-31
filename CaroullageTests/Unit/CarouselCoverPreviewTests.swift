//
//  CarouselCoverPreviewTests.swift
//  CaroullageTests
//
//  The Carousel gallery is a masonry grid, and a masonry grid is only a masonry
//  grid if the cards have different shapes. That property lives entirely in
//  `showcaseCover` returning an image at the template's TRUE canvas ratio — a
//  regression to the three-frame strip renderer would make every card the same
//  wide shape and the screen would silently become a plain uniform grid.
//
//  `schematicCover` is the other half: it must work with no manifest at all, so
//  a card can never render blank.
//

import XCTest
@testable import Caroullage

@MainActor
final class CarouselCoverPreviewTests: XCTestCase {

    private var appBundle: Bundle { Bundle(for: CollageRenderer.self) }

    private func makeCatalog() -> SampleContentCatalog {
        SampleContentCatalog(bundle: appBundle)
    }

    private func makeService() -> TemplateService {
        let service = TemplateService(bundle: appBundle)
        service.loadBundledCarouselTemplates()
        return service
    }

    /// width ÷ height, the same convention `MasonryLayout` consumes.
    private func aspect(_ image: CGImage) -> CGFloat {
        CGFloat(image.width) / CGFloat(image.height)
    }

    func testCoverMatchesTheTemplateCanvasRatio() throws {
        let service = makeService()
        let catalog = makeCatalog()
        let entries = try XCTUnwrap(catalog.manifest?.carousels)

        for id in entries.keys {
            let template = try XCTUnwrap(service.carouselTemplates.first { $0.id == id })
            let cover = try XCTUnwrap(
                service.showcaseCover(for: template, sampleContent: catalog),
                "\(id): a dressed carousel must produce a cover")

            let native = CanvasSize.size(forAspectRatio: template.canvasAspectRatio)
            let expected = native.width / native.height
            XCTAssertEqual(
                aspect(cover), expected, accuracy: 0.02,
                "\(id): the cover must carry the template's own shape — a cover "
                    + "rendered at a fixed or composited ratio flattens the masonry")
        }
    }

    func testCoverIsASingleFrameNotAStrip() throws {
        // The strip renderer composites 3 frames, so for a 4:5 template it comes
        // back WIDER than tall. The cover must not.
        let service = makeService()
        let catalog = makeCatalog()
        let template = try XCTUnwrap(
            service.carouselTemplates.first { $0.id == "carousel-story-beforeafter" })

        let cover = try XCTUnwrap(service.showcaseCover(for: template, sampleContent: catalog))
        XCTAssertLessThan(aspect(cover), 1.0, "a 4:5 cover must be taller than it is wide")

        let strip = try XCTUnwrap(service.showcasePreview(for: template, sampleContent: catalog))
        XCTAssertGreaterThan(aspect(strip), 1.0, "the strip renderer is unchanged")
    }

    func testSchematicCoverExistsForEveryBundledTemplateWithoutAManifest() throws {
        let service = makeService()
        XCTAssertFalse(service.carouselTemplates.isEmpty)

        for template in service.carouselTemplates {
            XCTAssertNotNil(
                service.schematicCover(for: template),
                "\(template.id): the fallback must never be nil — it is what stops "
                    + "a card rendering blank when sample photos fail to resolve")
        }
    }

    func testSchematicCoverAlsoCarriesTheTemplateShape() throws {
        let service = makeService()
        let template = try XCTUnwrap(
            service.carouselTemplates.first { $0.id == "carousel-panoramic-skyline" })
        let cover = try XCTUnwrap(service.schematicCover(for: template))
        // 16:9
        XCTAssertEqual(aspect(cover), 16.0 / 9.0, accuracy: 0.02)
    }

    func testPhotoZoneCountSumsEveryFrame() throws {
        let service = makeService()
        // gridpreview-4cell is [4,1,1,1,1] = 8.
        let template = try XCTUnwrap(
            service.carouselTemplates.first { $0.id == "carousel-gridpreview-4cell" })
        XCTAssertEqual(template.photoZoneCount, 8)
        XCTAssertEqual(template.frameCount, 5)
    }
}
