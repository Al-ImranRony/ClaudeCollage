//
//  HomeCollectionCatalogTests.swift
//  CaroullageTests
//
//  Home retention, phase 2. The bundled collections file against the bundled
//  catalogs: every id it names must exist and be dressed with sample
//  photography, every title must be in the String Catalog, every "See All"
//  target must be a chip the gallery actually has — so an authoring slip can
//  never ship as an empty or half-empty strip.
//

import XCTest
@testable import Caroullage

@MainActor
final class HomeCollectionCatalogTests: XCTestCase {

    private var appBundle: Bundle { Bundle(for: CollageRenderer.self) }

    private func makeTemplateService() -> TemplateService {
        let service = TemplateService(bundle: appBundle)
        service.loadBundledTemplates()
        service.loadBundledCarouselTemplates()
        return service
    }

    func testTheFileIsBundledAndNonEmpty() {
        let catalog = HomeCollectionCatalog(bundle: appBundle)
        XCTAssertGreaterThanOrEqual(catalog.authored.count, 6,
                                    "home_collections.json must be bundled and decodable")
    }

    func testIDsAreUnique() {
        let ids = HomeCollectionCatalog(bundle: appBundle).authored.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testEveryItemResolvesToADressedCatalogEntry() throws {
        let catalog = HomeCollectionCatalog(bundle: appBundle)
        let service = makeTemplateService()
        let sample = SampleContentCatalog(bundle: appBundle)
        let manifest = try XCTUnwrap(sample.manifest)

        for collection in catalog.authored {
            XCTAssertFalse(collection.itemIDs.isEmpty, "\(collection.id) has no items")
            for id in collection.itemIDs {
                switch collection.kind {
                case .photo:
                    XCTAssertNotNil(service.templates.first { $0.id == id },
                                    "\(collection.id): \(id) is not a bundled template")
                    XCTAssertNotNil(manifest.templates[id],
                                    "\(collection.id): \(id) has no sample photography")
                case .carousel:
                    XCTAssertNotNil(service.carouselTemplates.first { $0.id == id },
                                    "\(collection.id): \(id) is not a bundled carousel")
                    XCTAssertNotNil(manifest.carousels[id],
                                    "\(collection.id): \(id) has no sample photography")
                case .video:
                    XCTAssertTrue(sample.videoShowcases.contains { $0.id == id },
                                  "\(collection.id): \(id) is not a video showcase")
                }
            }
        }
    }

    func testEveryTitleIsInTheStringCatalog() {
        // Resolved through the app bundle, which is the main bundle of the
        // hosted test: a key with no entry comes back as itself.
        for collection in HomeCollectionCatalog(bundle: appBundle).authored {
            let title = appBundle.localizedString(forKey: collection.titleKey, value: "∅", table: nil)
            XCTAssertNotEqual(title, "∅", "\(collection.id): \"\(collection.titleKey)\" is not in the catalog")
            if let subtitle = collection.subtitleKey {
                XCTAssertNotEqual(appBundle.localizedString(forKey: subtitle, value: "∅", table: nil), "∅")
            }
        }
    }

    func testEverySeeAllTargetIsARealChip() {
        for collection in HomeCollectionCatalog(bundle: appBundle).authored {
            if let category = collection.galleryCategory {
                XCTAssertEqual(collection.kind, .photo, "\(collection.id): only photo collections land on the Collage tab")
                XCTAssertTrue(
                    TemplateGalleryViewController.categories.contains {
                        $0.caseInsensitiveCompare(category) == .orderedSame
                    }, "\(collection.id): \"\(category)\" is not a Collage tab chip")
            }
            if let type = collection.carouselType {
                XCTAssertEqual(collection.kind, .carousel)
                XCTAssertNotNil(CarouselType(rawValue: type), "\(collection.id): \"\(type)\" is not a CarouselType")
            }
        }
    }

    func testThePillarsAreAllPresentAndLast() {
        let authored = HomeCollectionCatalog(bundle: appBundle).authored
        let pillars = authored.filter(\.isPillar)
        XCTAssertEqual(pillars.map(\.kind), [.photo, .video, .carousel],
                       "One pillar per format, photo then video then carousel")
        XCTAssertEqual(Array(authored.suffix(pillars.count)), pillars, "Pillars are authored last")
    }

    func testEveryWindowIsWellFormed() {
        for collection in HomeCollectionCatalog(bundle: appBundle).authored {
            guard let window = collection.window else { continue }
            // A window that is never live would silently hide the collection.
            let anyDay = (1 ... 12).contains { month in
                var components = DateComponents()
                components.year = 2026
                components.month = month
                components.day = 15
                let date = HomeCollectionPlanner.calendar.date(from: components)!
                return HomeCollectionPlanner.isInWindow(window, now: date)
            }
            XCTAssertTrue(anyDay, "\(collection.id): its window is never live")
        }
    }

    func testAMissingFileFallsBackToTheThreePillars() {
        let sample = SampleContentCatalog(bundle: appBundle)
        let empty = HomeCollectionCatalog(bundle: Bundle(for: HomeCollectionCatalogTests.self))
        XCTAssertTrue(empty.authored.isEmpty, "The test bundle carries no collections file")

        let fallback = empty.collections(fallingBackTo: sample)
        XCTAssertEqual(fallback.map(\.id), ["photo-collages", "video-collages", "carousels"])
        XCTAssertTrue(fallback.allSatisfy(\.isPillar))
        XCTAssertEqual(Set(fallback[0].itemIDs), sample.featuredTemplateIDs)
        XCTAssertEqual(fallback[2].itemIDs, sample.featuredCarouselIDs)
    }
}
