//
//  DeepLinkUITests.swift
//  CaroullageUITests
//
//  Home retention, phase 1. XCUITest cannot open a URL into the app under
//  test, so the scene delegate honours `-deepLink <url>` under `-UITestMode`
//  and routes it exactly as a real URL — through `DeepLink` and the
//  `IntentRouter` queue — which is what these tests exercise.
//

import XCTest

final class DeepLinkUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(link: String) -> XCUIApplication {
        let app = XCUIApplication.underTest()
        app.launchArguments += ["-deepLink", link]
        app.launch()
        return app
    }

    @MainActor
    func testATemplateLinkOpensThatTemplateInTheEditor() {
        // A free template, so no paywall stands between the link and the editor.
        let app = launch(link: "caroullage://template/grid-4cell-square")
        XCTAssertTrue(app.navigationBars["Grid Collage"].waitForExistence(timeout: 20),
                      "A template deep link lands in the grid editor")
    }

    @MainActor
    func testACarouselTemplateLinkOpensTheCarouselEditor() {
        let app = launch(link: "caroullage://carousel/carousel-matched-team")
        XCTAssertTrue(app.navigationBars["Carousel"].waitForExistence(timeout: 20),
                      "A carousel deep link lands in the carousel editor")
    }

    @MainActor
    func testAnUnknownProjectLinkLeavesTheAppOnHome() {
        let app = launch(link: "caroullage://project/00000000-0000-0000-0000-000000000000")
        XCTAssertTrue(app.navigationBars["Caroullage"].waitForExistence(timeout: 20),
                      "A stale project link is a no-op, never a crash")
    }

    @MainActor
    func testAForeignLinkIsIgnored() {
        let app = launch(link: "https://example.com/project/1")
        XCTAssertTrue(app.navigationBars["Caroullage"].waitForExistence(timeout: 20))
    }
}
