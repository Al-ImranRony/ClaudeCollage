//
//  PaywallUITests.swift
//  CaroullageUITests
//
//  Step 06 phase 6.2 — the paywall in the running app.
//
//  What this covers: that a locked feature opens the paywall, that the screen
//  stands up, that the close button works on the first tap, and that the App
//  Review essentials — a restore path that always reports back, and the terms
//  line — are on screen.
//
//  What it deliberately does not cover: prices, plan rows, and the purchase
//  itself. Xcode attaches the local `.storekit` configuration to the *run*
//  action, and it does not reach an app launched by the test runner; with no
//  store behind it `Product.products(for:)` returns nothing and the paywall
//  honestly shows its unavailable state. An `SKTestSession` in either test
//  bundle did not change that. Those paths are covered by
//  `PaywallViewModelTests` and `PurchaseServiceTests` against the gateway stub,
//  and by running the app from Xcode with the Dev scheme.
//  See docs/step-06-account-gated.md.
//

import XCTest

final class PaywallUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Opens the paywall the way a user does: by reaching for a locked feature.
    @MainActor
    private func launchAndOpenPaywall() -> XCUIApplication {
        let app = XCUIApplication.underTest()
        app.launchArguments += ["-UITestMode", "1"]
        app.launch()

        let templates = app.buttons["templatesButton"]
        XCTAssertTrue(templates.waitForExistence(timeout: 10), "the Templates tab never appeared")
        templates.tap()

        let grid = app.collectionViews["templateGalleryGrid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 10), "the template grid never appeared")

        // Only visible cells exist in the accessibility tree, and free templates
        // sort first, so scroll until a locked card comes into view.
        let locked = app.cells.matching(identifier: "templateCard.premium").firstMatch
        var scrolls = 0
        while !locked.exists, scrolls < 8 {
            grid.swipeUp()
            scrolls += 1
        }
        guard locked.waitForExistence(timeout: 3) else {
            XCTFail("no locked template card after \(scrolls) scrolls")
            return app
        }
        locked.tap()
        return app
    }

    @MainActor
    func testALockedTemplateOpensThePaywall() throws {
        let app = launchAndOpenPaywall()

        XCTAssertTrue(
            app.staticTexts["Unlock Caroullage Premium"].waitForExistence(timeout: 5),
            "tapping a premium template must open the paywall"
        )
    }

    @MainActor
    func testTheCloseButtonIsThereFromTheFirstFrameAndDismisses() throws {
        let app = launchAndOpenPaywall()

        // App Review rejects paywalls whose close button is delayed or illegible.
        let close = app.buttons["paywallCloseButton"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()

        XCTAssertFalse(close.waitForExistence(timeout: 2), "the paywall must close on the first tap")
    }

    @MainActor
    func testTheRestorePathAndTermsAreOnScreen() throws {
        let app = launchAndOpenPaywall()

        XCTAssertTrue(
            app.buttons["paywallRestoreButton"].waitForExistence(timeout: 5),
            "App Review requires a visible restore path"
        )
        XCTAssertTrue(app.staticTexts["paywallTerms"].exists, "the terms line must be on the committing screen")
    }

    @MainActor
    func testRestoreAlwaysReportsWhatHappened() throws {
        let app = launchAndOpenPaywall()

        let restore = app.buttons["paywallRestoreButton"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.tap()

        // `AppStore.sync()` asks the system to sign in, and a simulator has no
        // Apple Account — so the sign-in alert appears. Declining it is exactly
        // what a signed-out user does, and the app must still report back.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let signIn = springboard.alerts.firstMatch
        if signIn.waitForExistence(timeout: 10) {
            let cancel = signIn.buttons["Cancel"]
            if cancel.exists { cancel.tap() } else { signIn.buttons.element(boundBy: 0).tap() }
        }

        // Either an outcome or an error, but never silence. Only one of the two
        // appears, so poll for whichever arrives rather than waiting on both.
        let message = app.staticTexts["paywallRestoreMessage"]
        let failure = app.staticTexts["paywallError"]
        var waited = 0.0
        while !message.exists, !failure.exists, waited < 25 {
            Thread.sleep(forTimeInterval: 0.5)
            waited += 0.5
        }
        XCTAssertTrue(message.exists || failure.exists, "restore must say what happened")
    }
}
