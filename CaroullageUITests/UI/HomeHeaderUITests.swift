//
//  HomeHeaderUITests.swift
//  CaroullageUITests
//
//  Step 07 — Home's header earns its place in the bar: the brand lockup names
//  the app, and the Pro button is the paywall's front door.
//
//  The premium case is driven by `-debug.premiumUnlocked`, the same override
//  `EntitlementStore` and `PurchaseService` both read, because the simulator
//  cannot buy anything (see the note at the top of `PaywallUITests`).
//

import XCTest

final class HomeHeaderUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(premium: Bool = false) -> XCUIApplication {
        let app = XCUIApplication.underTest()
        app.launchArguments += ["-debug.premiumUnlocked", premium ? "YES" : "NO"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Caroullage"].waitForExistence(timeout: 10),
                      "App launches to Home")
        return app
    }

    /// The lockup replaced the bar's own title, so the bar has to keep saying
    /// which screen this is — every other Home suite waits on that name.
    @MainActor
    func testHeaderNamesTheApp() {
        let app = launch()
        XCTAssertTrue(app.navigationBars["Caroullage"].exists)
        XCTAssertTrue(app.buttons["homeProButton"].waitForExistence(timeout: 5),
                      "A free user is offered Pro from the front door")
    }

    /// The button's whole purpose: reach the paywall from Home, in one tap.
    @MainActor
    func testProButtonOpensThePaywall() {
        let app = launch()

        let pro = app.buttons["homeProButton"]
        XCTAssertTrue(pro.waitForExistence(timeout: 5))
        pro.tap()

        XCTAssertTrue(
            app.staticTexts["Unlock Caroullage Premium"].waitForExistence(timeout: 10),
            "Pro must open the paywall")
    }

    /// And back out again, leaving Home where it was.
    @MainActor
    func testPaywallClosesBackToHome() {
        let app = launch()

        app.buttons["homeProButton"].tap()
        let close = app.buttons["paywallCloseButton"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        close.tap()

        XCTAssertTrue(app.navigationBars["Caroullage"].waitForExistence(timeout: 5),
                      "Closing the paywall returns to Home")
    }

    /// A "Pro" button that leads to a paywall you have already paid is a dead
    /// end, so premium users are not shown one.
    @MainActor
    func testProButtonIsAbsentForPremiumUsers() {
        let app = launch(premium: true)

        // The bar is up (asserted in `launch`), so this is the button being
        // absent rather than the screen not having arrived yet.
        XCTAssertFalse(app.buttons["homeProButton"].exists,
                       "Premium users are not sold premium")
    }
}
