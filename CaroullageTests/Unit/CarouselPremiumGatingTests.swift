//
//  CarouselPremiumGatingTests.swift
//  CaroullageTests
//
//  Four bundled carousels are marked `"isPremium": true`, and until Step 07's
//  gallery there was no `canOpen` overload that could read the flag — so Home
//  opened all four for free. These tests are the pin on that not returning.
//

import XCTest
@testable import Caroullage

@MainActor
final class CarouselPremiumGatingTests: XCTestCase {

    private var appBundle: Bundle { Bundle(for: CollageRenderer.self) }

    private func makeService(premiumUnlocked: Bool) -> TemplateService {
        let service = TemplateService(
            bundle: appBundle,
            entitlements: EntitlementStore(isPremiumUnlocked: premiumUnlocked))
        service.loadBundledCarouselTemplates()
        return service
    }

    private func template(_ id: String, in service: TemplateService) throws -> CarouselTemplate {
        try XCTUnwrap(service.carouselTemplates.first { $0.id == id },
                      "\(id) is missing from the bundled carousel catalog")
    }

    func testTheCatalogStillCarriesPremiumCarousels() throws {
        // If this ever fails the rest of the file is testing nothing, so it
        // fails loudly rather than letting the suite go green on an empty set.
        let service = makeService(premiumUnlocked: false)
        let premium = service.carouselTemplates.filter(\.isPremium)
        XCTAssertFalse(premium.isEmpty, "no premium carousel left to gate")
    }

    func testFreeCarouselOpensOnTheFreeTier() throws {
        let service = makeService(premiumUnlocked: false)
        let free = try template("carousel-matched-team", in: service)
        XCTAssertFalse(service.isPremium(free))
        XCTAssertTrue(service.canOpen(free))
    }

    func testPremiumCarouselIsBlockedOnTheFreeTier() throws {
        let service = makeService(premiumUnlocked: false)
        let locked = try template("carousel-story-travel", in: service)
        XCTAssertTrue(service.isPremium(locked))
        XCTAssertFalse(service.canOpen(locked),
                       "a premium carousel must not open for a free user")
    }

    func testPremiumCarouselOpensOnceUnlocked() throws {
        let service = makeService(premiumUnlocked: true)
        let locked = try template("carousel-story-travel", in: service)
        XCTAssertTrue(service.canOpen(locked))
    }
}
