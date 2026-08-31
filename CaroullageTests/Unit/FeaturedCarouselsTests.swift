//
//  FeaturedCarouselsTests.swift
//  CaroullageTests
//
//  Home's Carousels strip used to be `filter { the manifest dresses it }`, so
//  its curation was an accident of which templates happened to have sample
//  photos — and dressing the rest of the catalog for the Carousel gallery would
//  have silently taken the strip from 6 cards to 20. `featuredCarousels` makes
//  the choice explicit. These tests hold the list and its fallback.
//

import XCTest
@testable import Caroullage

@MainActor
final class FeaturedCarouselsTests: XCTestCase {

    private var appBundle: Bundle { Bundle(for: CollageRenderer.self) }

    private func makeCatalog() -> SampleContentCatalog {
        SampleContentCatalog(bundle: appBundle)
    }

    func testFeaturedListIsPresentAndNonEmpty() {
        let catalog = makeCatalog()
        XCTAssertFalse(catalog.featuredCarouselIDs.isEmpty,
                       "Home leads with this list; empty means an empty strip")
    }

    func testEveryFeaturedIDIsBothDressedAndInTheCatalog() throws {
        let catalog = makeCatalog()
        let service = TemplateService(bundle: appBundle)
        service.loadBundledCarouselTemplates()
        let dressed = try XCTUnwrap(catalog.manifest?.carousels)

        for id in catalog.featuredCarouselIDs {
            XCTAssertNotNil(dressed[id],
                            "featured '\(id)' has no framePhotos — Home would show empty wells")
            XCTAssertTrue(service.carouselTemplates.contains { $0.id == id },
                          "featured '\(id)' is not in the bundled carousel catalog")
        }
    }

    func testFeaturedOrderIsTheManifestOrder() throws {
        // Home renders in this order, so it is data, not a set.
        let catalog = makeCatalog()
        let ids = catalog.featuredCarouselIDs
        XCTAssertEqual(ids.first, "carousel-matched-team",
                       "the strip's first card is authored, not incidental")
        XCTAssertEqual(Set(ids).count, ids.count, "a duplicate would render the same card twice")
    }

    func testAbsentKeyFallsBackToEveryDressedCarousel() {
        // A manifest written before this key existed must still produce a strip.
        let json = """
        {
          "version": 1,
          "templates": {},
          "carousels": {
            "a": { "framePhotos": [["sample_portrait_01"]] },
            "b": { "framePhotos": [["sample_portrait_02"]] }
          },
          "videoShowcases": [],
          "hero": []
        }
        """
        let manifest = try? JSONDecoder().decode(
            SampleContentManifest.self, from: Data(json.utf8))
        XCTAssertNotNil(manifest, "the key must be optional, or old manifests stop decoding")
        XCTAssertNil(manifest?.featuredCarousels)
    }
}
