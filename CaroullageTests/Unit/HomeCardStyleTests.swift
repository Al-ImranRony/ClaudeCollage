//
//  HomeCardStyleTests.swift
//  CaroullageTests
//
//  The 2026-11-20 Home strips redesign: which card shape each collection
//  gets, that the bundled file only names shapes that suit its kind, and the
//  one-line facts under each card. The cards themselves are checked by eye.
//

import XCTest
@testable import Caroullage

@MainActor
final class HomeCardStyleTests: XCTestCase {

    private var appBundle: Bundle { Bundle(for: CollageRenderer.self) }

    // MARK: - Style per collection

    func testEachKindFallsBackToItsNativeShape() {
        XCTAssertEqual(HomeCollection(id: "p", titleKey: "P", kind: .photo, itemIDs: []).cardStyleName, "poster")
        XCTAssertEqual(HomeCollection(id: "v", titleKey: "V", kind: .video, itemIDs: []).cardStyleName, "reel")
        XCTAssertEqual(HomeCollection(id: "c", titleKey: "C", kind: .carousel, itemIDs: []).cardStyleName, "deck")
    }

    /// A video collection cannot become a poster, nor a carousel a story: the
    /// card would show the wrong artwork. Unknown or mismatched values fall
    /// back to the native shape rather than failing.
    func testAMismatchedOrUnknownStyleFallsBack() {
        XCTAssertEqual(
            HomeCollection(id: "v", titleKey: "V", kind: .video, itemIDs: [], style: "poster").cardStyleName,
            "reel")
        XCTAssertEqual(
            HomeCollection(id: "c", titleKey: "C", kind: .carousel, itemIDs: [], style: "story").cardStyleName,
            "deck")
        XCTAssertEqual(
            HomeCollection(id: "p", titleKey: "P", kind: .photo, itemIDs: [], style: "sparkly").cardStyleName,
            "poster")
        XCTAssertEqual(
            HomeCollection(id: "p", titleKey: "P", kind: .photo, itemIDs: [], style: "feature").cardStyleName,
            "feature")
    }

    func testEveryResolvedStyleIsARealCardStyle() {
        let catalog = HomeCollectionCatalog(bundle: appBundle)
        XCTAssertFalse(catalog.authored.isEmpty)
        for collection in catalog.authored {
            XCTAssertNotNil(HomeCardStyle(rawValue: collection.cardStyleName), collection.id)
            if let style = collection.style {
                XCTAssertEqual(collection.cardStyleName, style,
                               "\(collection.id) names a style its kind cannot use")
            }
        }
    }

    /// Every bundled collection carries a hook line under its title.
    func testEveryCollectionHasASubtitle() {
        for collection in HomeCollectionCatalog(bundle: appBundle).authored {
            XCTAssertFalse((collection.subtitleKey ?? "").isEmpty, collection.id)
        }
    }

    /// A story strip shows its templates full-bleed at 9:16, so everything in
    /// it must actually be 9:16 — anything else would be cropped.
    func testAStoryStripHoldsOnlyTallTemplates() {
        let templates = TemplateService(bundle: appBundle)
        templates.loadBundledTemplates()
        for collection in HomeCollectionCatalog(bundle: appBundle).authored
        where collection.cardStyleName == "story" {
            for id in collection.itemIDs {
                guard let template = templates.templates.first(where: { $0.id == id }) else { continue }
                XCTAssertEqual(template.canvasAspectRatio, "9:16", "\(id) in \(collection.id)")
            }
        }
    }

    // MARK: - Geometry

    /// Each shape is distinct — the point of the redesign is that strips stop
    /// looking alike — and the tall shapes really are tall.
    func testShapesAreDistinctAndTallOnesAreTall() {
        let sizes = Set(HomeCardStyle.allCases.filter { $0 != .reel }.map { "\($0.artworkSize)" })
        XCTAssertEqual(sizes.count, HomeCardStyle.allCases.count - 1)
        for style in [HomeCardStyle.story, .reel] {
            let size = style.artworkSize
            XCTAssertEqual(size.height / size.width, 16.0 / 9, accuracy: 0.05, "\(style)")
        }
        XCTAssertGreaterThan(HomeCardStyle.feature.artworkSize.width, HomeCardStyle.poster.artworkSize.width)
        XCTAssertGreaterThan(HomeCardStyle.poster.cellSize.height, HomeCardStyle.poster.artworkSize.height)
    }

    // MARK: - Meta lines

    func testMetaLines() {
        XCTAssertEqual(HomeCardMeta.photos(4, ratio: "1:1"), "4 photos · 1:1")
        XCTAssertEqual(HomeCardMeta.photos(1, ratio: "4:5"), "1 photo · 4:5")
        XCTAssertEqual(HomeCardMeta.pages(5, ratio: "4:5"), "5 pages · 4:5")
        XCTAssertEqual(HomeCardMeta.video(size: CGSize(width: 540, height: 960)), "Video · 9:16")
        XCTAssertEqual(HomeCardMeta.video(size: CGSize(width: 720, height: 900)), "Video · 4:5")
        XCTAssertEqual(HomeCardMeta.video(size: nil), "Video")
    }
}
