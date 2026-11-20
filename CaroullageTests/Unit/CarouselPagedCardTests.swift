//
//  CarouselPagedCardTests.swift
//  CaroullageTests
//
//  The Carousel tab's cards page like the post they make (2026-11-20). Pinned
//  here, in four parts:
//
//  • the schema the SCRL-style templates are written in — frame styling and
//    the blurred-photo / pattern backgrounds — parses, and reaches the editor;
//  • a panoramic preview is ONE photo cut across its pages, so the pages meet;
//  • the card pages: it holds one page per slide, starts on the first, speaks
//    the page it is on, and a recycled card forgets the old template's pages;
//  • a still card (the Collage tab) does not page at all.
//

import XCTest
@testable import Caroullage

@MainActor
final class CarouselPagedCardTests: XCTestCase {

    private var appBundle: Bundle { Bundle(for: CollageRenderer.self) }

    private func makeService() -> TemplateService {
        let service = TemplateService(bundle: appBundle)
        service.loadBundledCarouselTemplates()
        return service
    }

    private func parse(_ json: String) throws -> CarouselTemplate {
        try CarouselTemplateParser().parse(data: Data(json.utf8))
    }

    // MARK: - Schema

    func testFrameStyleAndBlurredBackdropParse() throws {
        let template = try parse("""
        { "canvasAspectRatio": "4:5",
          "background": { "type": "photoBlur", "dim": 0.3 },
          "frameStyle": { "outlineWidth": 22, "outlineHex": "#111111", "shadow": 0.5 },
          "frames": [ { "index": 0, "cells": [ { "type": "photo" } ] } ] }
        """)
        XCTAssertEqual(template.background, .photoBlur(dim: 0.3))
        XCTAssertEqual(template.frameStyle.outlineWidth, 22)
        XCTAssertEqual(template.frameStyle.outlineHex, "#111111")
        XCTAssertEqual(template.frameStyle.shadow, 0.5)
    }

    func testPatternBackgroundParsesAndUnknownMotifFallsBackToPaper() throws {
        let dots = try parse("""
        { "canvasAspectRatio": "1:1",
          "background": { "type": "pattern", "pattern": "dots", "ink": "#222222", "paper": "#FAFAFA" } }
        """)
        XCTAssertEqual(dots.background, .pattern(.dots, ink: "#222222", paper: "#FAFAFA"))

        let unknown = try parse("""
        { "canvasAspectRatio": "1:1",
          "background": { "type": "pattern", "pattern": "plaid", "paper": "#FAFAFA" } }
        """)
        XCTAssertEqual(unknown.background, .solid(hex: "#FAFAFA"),
                       "an unknown motif degrades to its paper, never fails the template")
    }

    func testAbsentFrameStyleIsUnstyled() throws {
        let template = try parse(#"{ "canvasAspectRatio": "4:5" }"#)
        XCTAssertEqual(template.frameStyle, FrameStyle(),
                       "every template authored before the key must look unchanged")
    }

    func testTextZonesCarryTrackingAndLeading() throws {
        let template = try parse("""
        { "canvasAspectRatio": "4:5",
          "frames": [ { "index": 0, "cells": [
            { "type": "text", "text": "VOL. 01", "letterSpacing": 6, "lineHeight": 1.3 } ] } ] }
        """)
        let overlay = try XCTUnwrap(template.frames.first?.cells.first?.textStyle)
        XCTAssertEqual(overlay.letterSpacing, 6)
        XCTAssertEqual(overlay.lineHeight, 1.3)
    }

    func testTheEditorOpensWithTheTemplatesFrameStyle() throws {
        let template = try parse("""
        { "canvasAspectRatio": "4:5",
          "frameStyle": { "outlineWidth": 26, "outlineHex": "#FFFFFF", "shadow": 0.55 },
          "frames": [ { "index": 0, "cells": [ { "type": "photo" } ] },
                      { "index": 1, "cells": [ { "type": "photo" } ] } ] }
        """)
        let frames = CarouselService().buildCarousel(from: template)
        XCTAssertEqual(frames.count, 2)
        for frame in frames {
            XCTAssertEqual(frame.state.frameStyle, template.frameStyle,
                           "the white mat the card shows must be the one the editor opens with")
        }
    }

    // MARK: - Bundled SCRL-style templates

    func testEveryNewTemplateLoadsDressedAndFullyPaged() throws {
        let service = makeService()
        let catalog = SampleContentCatalog(bundle: appBundle)
        let ids = ["carousel-matched-filmframes", "carousel-matched-framedmoments",
                   "carousel-matched-photodump", "carousel-matched-cleantrio",
                   "carousel-matched-gallerywall", "carousel-matched-softfocus",
                   "carousel-matched-contactsheet", "carousel-story-editorial"]
        for id in ids {
            let template = try XCTUnwrap(
                service.carouselTemplates.first { $0.id == id }, "\(id) is bundled")
            let pages = service.showcaseFrames(
                for: template, sampleContent: catalog, limit: CarouselService.maxFrames)
            XCTAssertEqual(pages.count, template.frameCount,
                           "\(id): every page of the card renders, dressed")
        }
    }

    // MARK: - Seamless panoramic previews

    /// Mean absolute difference between two pixel columns, 0…255.
    private func columnDifference(_ a: CGImage, column ca: Int, _ b: CGImage, column cb: Int) -> Double {
        func column(_ image: CGImage, _ x: Int) -> [UInt8] {
            let height = image.height
            var pixels = [UInt8](repeating: 0, count: height * 4)
            let space = CGColorSpaceCreateDeviceRGB()
            pixels.withUnsafeMutableBytes { buffer in
                guard let context = CGContext(
                    data: buffer.baseAddress, width: 1, height: height, bitsPerComponent: 8,
                    bytesPerRow: 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
                context.draw(image, in: CGRect(x: -x, y: 0, width: image.width, height: height))
            }
            return pixels
        }
        let left = column(a, ca), right = column(b, cb)
        let total = zip(left, right).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        return Double(total) / Double(max(left.count, 1))
    }

    func testPanoramicPagesMeetAtTheirEdges() throws {
        let service = makeService()
        let template = try XCTUnwrap(
            service.carouselTemplates.first { $0.id == "carousel-panoramic-beach" })
        let pages = service.showcaseFrames(
            for: template, sampleContent: SampleContentCatalog(bundle: appBundle),
            limit: CarouselService.maxFrames)
        XCTAssertEqual(pages.count, template.frameCount)

        for index in 0..<(pages.count - 1) {
            let seam = columnDifference(pages[index], column: pages[index].width - 1,
                                        pages[index + 1], column: 0)
            // A control: the same page's two outer edges, which share nothing.
            let unrelated = columnDifference(pages[index], column: 0,
                                             pages[index], column: pages[index].width - 1)
            XCTAssertLessThan(seam, 12,
                              "page \(index) and \(index + 1) must continue one photograph")
            XCTAssertLessThan(seam, unrelated,
                              "the seam must match better than two unrelated columns do")
        }
    }

    // MARK: - The paged card

    private func makeCard(pages: Int?, slides: Int? = nil) -> BrowseTemplateCell {
        let cell = BrowseTemplateCell(frame: CGRect(x: 0, y: 0, width: 170, height: 270))
        let cover = makeImage()
        let count = slides ?? pages ?? 1
        cell.configure(
            BrowseTemplateCell.Content(
                name: "Film Frames", ratio: "Portrait", photos: 13, pages: pages,
                locked: false, identifier: "carouselTemplateCard.free"),
            artwork: .init(cached: cover, load: { cover }),
            pages: pages == nil ? nil : .init(
                cached: nil, load: { Array(repeating: cover, count: count) }))
        cell.layoutIfNeeded()
        return cell
    }

    private func makeImage() -> CGImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 10)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 10))
        }.cgImage!
    }

    func testACarouselCardHoldsOnePagePerSlideAndStartsOnTheFirst() {
        let card = makeCard(pages: 4)
        XCTAssertEqual(card.pageCount, 4)
        XCTAssertEqual(card.currentPage, 0)
        XCTAssertTrue(card.accessibilityValue?.contains("Page 1 of 4") ?? false,
                      "VoiceOver hears which page is showing: \(card.accessibilityValue ?? "nil")")
    }

    func testVoiceOverCanPageTheCard() throws {
        let card = makeCard(pages: 3)
        let actions = card.pagingAccessibilityActions
        XCTAssertEqual(actions.map(\.name), ["Next page", "Previous page"])

        let next = try XCTUnwrap(actions.first?.actionHandler)
        XCTAssertTrue(next(actions[0]))
        XCTAssertEqual(card.currentPage, 1)
        XCTAssertTrue(card.accessibilityValue?.contains("Page 2 of 3") ?? false)

        let previous = try XCTUnwrap(actions.last?.actionHandler)
        XCTAssertTrue(previous(actions[1]))
        XCTAssertEqual(card.currentPage, 0)
        XCTAssertFalse(previous(actions[1]), "there is no page before the first")
    }

    func testARecycledCardForgetsTheOldTemplatesPages() {
        let card = makeCard(pages: 5)
        _ = card.pagingAccessibilityActions.first?.actionHandler?(card.pagingAccessibilityActions[0])
        XCTAssertEqual(card.currentPage, 1)

        card.prepareForReuse()
        XCTAssertEqual(card.pageCount, 1)
        XCTAssertEqual(card.currentPage, 0)
        XCTAssertTrue(card.pagingAccessibilityActions.isEmpty)
    }

    func testAStillCardDoesNotPage() {
        // The Collage tab: no page provider, no page count.
        let still = makeCard(pages: nil)
        XCTAssertEqual(still.pageCount, 1)
        XCTAssertTrue(still.pagingAccessibilityActions.isEmpty)

        // …and a one-page carousel is not a carousel either.
        let single = makeCard(pages: 1)
        XCTAssertEqual(single.pageCount, 1)
    }

    func testPagedCardsReserveRoomForTheirDots() {
        XCTAssertGreaterThan(BrowseTemplateCell.captionHeight(pages: true),
                             BrowseTemplateCell.captionHeight(pages: false))
        XCTAssertEqual(BrowseTemplateCell.captionHeight(pages: false),
                       BrowseTemplateCell.captionHeight,
                       "the Collage tab's still cards keep their old caption height")
    }
}
