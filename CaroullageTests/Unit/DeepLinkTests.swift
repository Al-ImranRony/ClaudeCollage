//
//  DeepLinkTests.swift
//  CaroullageTests
//
//  Home retention, phase 1. Every URL the widget, the Live Activity, Spotlight
//  and a notification can hand the app, parsed once and round-tripped.
//

import CoreSpotlight
import XCTest
@testable import Caroullage

final class DeepLinkTests: XCTestCase {

    private let id = UUID(uuidString: "6E0E9B3A-9E2C-4C3E-9C0F-2C4E5D1B7A10")!

    // MARK: - URLs

    func testTheWidgetsProjectURLOpensThatProject() {
        // The exact string `RecentProjectsWidget` has emitted since Step 05.
        let url = URL(string: "caroullage://project/\(id.uuidString)")!
        XCTAssertEqual(DeepLink.parse(url), .project(id))
    }

    func testTheLiveActivitysExportURLOpensTheLastProject() {
        XCTAssertEqual(DeepLink.parse(URL(string: "caroullage://export")!), .exportLast)
    }

    func testEveryVerbParses() {
        XCTAssertEqual(DeepLink.parse(URL(string: "caroullage://collection/autumn")!), .collection("autumn"))
        XCTAssertEqual(DeepLink.parse(URL(string: "caroullage://template/grid-4cell-square")!),
                       .template("grid-4cell-square"))
        XCTAssertEqual(DeepLink.parse(URL(string: "caroullage://carousel/carousel-matched-team")!),
                       .carouselTemplate("carousel-matched-team"))
        XCTAssertEqual(DeepLink.parse(URL(string: "caroullage://settings")!), .settings)
    }

    func testTheSchemeAndVerbAreCaseInsensitiveButTheArgumentIsNot() {
        XCTAssertEqual(DeepLink.parse(URL(string: "CAROULLAGE://Template/Bloom")!), .template("Bloom"))
    }

    func testTheSchemeOnlyFormIsAccepted() {
        XCTAssertEqual(DeepLink.parse(URL(string: "caroullage:///project/\(id.uuidString)")!), .project(id))
    }

    func testForeignSchemesAndMalformedLinksAreRejected() {
        XCTAssertNil(DeepLink.parse(URL(string: "https://caroullage.app/project/\(id.uuidString)")!))
        XCTAssertNil(DeepLink.parse(URL(string: "caroullage://project/not-a-uuid")!))
        XCTAssertNil(DeepLink.parse(URL(string: "caroullage://project")!))
        XCTAssertNil(DeepLink.parse(URL(string: "caroullage://template")!))
        XCTAssertNil(DeepLink.parse(URL(string: "caroullage://dance")!))
        XCTAssertNil(DeepLink.parse(URL(string: "caroullage://")!))
    }

    func testEveryLinkRoundTripsThroughItsOwnURL() {
        let links: [DeepLink] = [
            .project(id), .exportLast, .collection("new-this-week"),
            .template("grid-4cell-square"), .carouselTemplate("carousel-matched-team"), .settings,
        ]
        for link in links {
            XCTAssertEqual(DeepLink.parse(link.url), link, "\(link) must survive its own URL")
        }
    }

    // MARK: - User activities

    func testASpotlightResultOpensItsProject() {
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: SpotlightIndexer.identifier(for: id)]
        XCTAssertEqual(DeepLink.parse(activity), .project(id))
    }

    func testASpotlightResultWithAForeignIdentifierIsIgnored() {
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: "com.example.other.123"]
        XCTAssertNil(DeepLink.parse(activity))
    }

    func testAnUnrelatedActivityIsIgnored() {
        XCTAssertNil(DeepLink.parse(NSUserActivity(activityType: "com.devron.caroullage.nothing")))
    }

    // MARK: - Routing

    @MainActor
    func testEachLinkBecomesTheMatchingRouterRequest() {
        XCTAssertEqual(DeepLink.project(id).request, .openProject(id))
        XCTAssertEqual(DeepLink.exportLast.request, .exportLastProject)
        XCTAssertEqual(DeepLink.collection("x").request, .openCollection("x"))
        XCTAssertEqual(DeepLink.template("x").request, .openTemplate("x"))
        XCTAssertEqual(DeepLink.carouselTemplate("x").request, .openCarouselTemplate("x"))
        XCTAssertEqual(DeepLink.settings.request, .openSettings)
    }
}
