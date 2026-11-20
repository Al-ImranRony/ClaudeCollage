//
//  PreviewPipelineTests.swift
//  CaroullageTests
//
//  The async preview pipeline behind every Home and browse card (2026-11-20).
//  What it promises, pinned:
//
//  • concurrent requests for one picture share ONE render;
//  • once loaded, a picture is answered synchronously from memory — which is
//    what lets a card scrolled back into view show it in the same frame;
//  • a card with its picture in memory shows it immediately, unanimated; one
//    without shows its well and fills in when the load lands.
//

import XCTest
@testable import Caroullage

@MainActor
final class PreviewPipelineTests: XCTestCase {

    private var appBundle: Bundle { Bundle(for: CollageRenderer.self) }

    private func makeService() -> TemplateService {
        let service = TemplateService(bundle: appBundle)
        service.loadBundledTemplates()
        service.loadBundledCarouselTemplates()
        return service
    }

    private func solidRequest() -> RenderRequest {
        RenderRequest(canvasSize: CGSize(width: 40, height: 50), background: .solid(hex: "#FF8800"), cells: [])
    }

    func testConcurrentRequestsForOnePictureShareOneRender() async {
        let service = makeService()
        let key = "pipeline-test-\(UUID().uuidString)"
        var builds = 0
        let make: @MainActor () -> RenderRequest? = {
            builds += 1
            return self.solidRequest()
        }
        async let first = service.loadImage(forKey: key, makeRequest: make)
        async let second = service.loadImage(forKey: key, makeRequest: make)
        let (a, b) = await (first, second)
        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
        XCTAssertEqual(builds, 1, "the second caller must join the first render, not start its own")
    }

    func testALoadedPictureIsThenAnsweredFromMemory() async {
        let service = makeService()
        let key = "pipeline-test-\(UUID().uuidString)"
        XCTAssertNil(service.cachedImage(forKey: key))
        _ = await service.loadImage(forKey: key) { self.solidRequest() }
        XCTAssertNotNil(service.cachedImage(forKey: key),
                        "a card configured after the load must find it synchronously")
    }

    func testAnUndrawableRequestYieldsNilAndCachesNothing() async {
        let service = makeService()
        let key = "pipeline-test-\(UUID().uuidString)"
        let image = await service.loadImage(forKey: key) { nil }
        XCTAssertNil(image)
        XCTAssertNil(service.cachedImage(forKey: key))
    }

    func testCarouselCoverAndFramesAreCachedAfterLoading() async throws {
        let service = makeService()
        let catalog = SampleContentCatalog(bundle: appBundle)
        let template = try XCTUnwrap(service.carouselTemplates.first { $0.id == "carousel-matched-filmframes" })

        let cover = await service.loadShowcaseCover(for: template, sampleContent: catalog)
        XCTAssertNotNil(cover)
        XCTAssertNotNil(service.cachedShowcaseCover(for: template, sampleContent: catalog))

        let frames = await service.loadShowcaseFrames(for: template, sampleContent: catalog)
        XCTAssertEqual(frames.count, template.frameCount)
        XCTAssertEqual(service.cachedShowcaseFrames(for: template, sampleContent: catalog)?.count,
                       template.frameCount, "a paged card scrolled back in fills every page at once")
    }

    func testCollagePreviewIsCachedAfterLoading() async throws {
        let service = makeService()
        let catalog = SampleContentCatalog(bundle: appBundle)
        let template = try XCTUnwrap(service.templates.first {
            catalog.manifest?.templates[$0.id] != nil
        })
        let image = await service.loadShowcasePreview(for: template, sampleContent: catalog)
        XCTAssertNotNil(image)
        XCTAssertNotNil(service.cachedShowcasePreview(for: template, sampleContent: catalog))
    }

    // MARK: - The card

    private func makeImage() -> CGImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 10)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 10))
        }.cgImage!
    }

    private func content() -> BrowseTemplateCell.Content {
        .init(name: "Clean Trio", ratio: "Portrait", photos: 12, pages: nil,
              locked: false, identifier: "templateCard.free")
    }

    func testACachedPictureIsShownInTheSameFrame() {
        let cell = BrowseTemplateCell(frame: CGRect(x: 0, y: 0, width: 170, height: 260))
        let image = makeImage()
        cell.configure(content(), artwork: .init(cached: image, load: { XCTFail("must not load"); return nil }))
        XCTAssertNotNil(cell.pageImage(at: 0), "no placeholder, no fade: it is there before the next frame")
    }

    func testAnUncachedPictureFillsInWhenItsLoadLands() async {
        let cell = BrowseTemplateCell(frame: CGRect(x: 0, y: 0, width: 170, height: 260))
        let image = makeImage()
        let landed = expectation(description: "load ran")
        cell.configure(content(), artwork: .init(cached: nil, load: {
            landed.fulfill()
            return image
        }))
        XCTAssertNil(cell.pageImage(at: 0), "the well shows until the picture arrives")
        await fulfillment(of: [landed], timeout: 2)
        await Task.yield()
        XCTAssertNotNil(cell.pageImage(at: 0))
    }

    // MARK: - Review fixes

    func testAWireframeInMemoryNeverStandsInForADressedPreview() throws {
        let service = makeService()
        let catalog = SampleContentCatalog(bundle: appBundle)
        let template = try XCTUnwrap(service.templates.first { catalog.manifest?.templates[$0.id] != nil })
        _ = service.thumbnail(for: template)   // the wireframe, now in memory
        XCTAssertNil(service.cachedShowcasePreview(for: template, sampleContent: catalog),
                     "a dressed template must load its real preview, not settle for the wireframe")
    }

    func testACardOnlyPassedThroughNeverLoadsItsOtherSlides() async throws {
        let cell = BrowseTemplateCell(frame: CGRect(x: 0, y: 0, width: 170, height: 270))
        let image = makeImage()
        var slideLoads = 0
        cell.configure(
            .init(name: "Film Frames", ratio: "Portrait", photos: 13, pages: 4,
                  locked: false, identifier: "carouselTemplateCard.free"),
            artwork: .init(cached: image, load: { image }),
            pages: .init(cached: nil, load: {
                slideLoads += 1
                return Array(repeating: image, count: 4)
            }))
        cell.prepareForReuse()   // recycled within the settle window
        try await Task.sleep(for: BrowseTemplateCell.slideSettleDelay * 2)
        XCTAssertEqual(slideLoads, 0, "a fling's passing cards render no slides")
    }

    func testACardThatSettlesLoadsItsOtherSlides() async throws {
        let cell = BrowseTemplateCell(frame: CGRect(x: 0, y: 0, width: 170, height: 270))
        let image = makeImage()
        let loaded = expectation(description: "slides loaded")
        cell.configure(
            .init(name: "Film Frames", ratio: "Portrait", photos: 13, pages: 4,
                  locked: false, identifier: "carouselTemplateCard.free"),
            artwork: .init(cached: image, load: { image }),
            pages: .init(cached: nil, load: {
                loaded.fulfill()
                return Array(repeating: image, count: 4)
            }))
        await fulfillment(of: [loaded], timeout: 3)
        await Task.yield()
        XCTAssertNotNil(cell.pageImage(at: 3))
    }
}
