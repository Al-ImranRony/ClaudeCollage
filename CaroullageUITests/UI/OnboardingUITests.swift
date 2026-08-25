//
//  OnboardingUITests.swift
//  CaroullageUITests
//
//  Step 06 phase 6.3 — the funnel on a first launch.
//
//  The photo-permission beat is deliberately not crossed here: tapping it raises
//  the system prompt, whose buttons are not ours and whose answer sticks for the
//  whole simulator. The decision logic behind it is covered headlessly in
//  `OnboardingViewModelTests`.
//

import XCTest

final class OnboardingUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchFirstRun() -> XCUIApplication {
        let app = XCUIApplication.underTest(hasSeenOnboarding: false)
        app.launch()
        return app
    }

    /// Taps Continue until `element` turns up, so a tap landing mid-transition
    /// costs a retry rather than the test.
    @MainActor
    private func tapContinue(in app: XCUIApplication, until element: XCUIElement, limit: Int = 6) {
        let button = app.buttons["onboardingContinueButton"]
        var taps = 0
        while !element.exists, taps < limit {
            if button.exists { button.tap() }
            taps += 1
            _ = element.waitForExistence(timeout: 1.5)
        }
    }

    @MainActor
    func testAFirstLaunchOpensOnTheWelcomeSlide() throws {
        let app = launchFirstRun()

        XCTAssertTrue(
            app.staticTexts["Welcome to Caroullage"].waitForExistence(timeout: 10),
            "a first launch must start in the funnel, not on the tab bar"
        )
    }

    @MainActor
    func testContinueWalksTheValueSlidesToTheQuestion() throws {
        let app = launchFirstRun()
        XCTAssertTrue(app.buttons["onboardingContinueButton"].waitForExistence(timeout: 10))

        // welcome → grid → carousel → video → personalization
        let question = app.buttons["onboardingChoice.carousels"]
        tapContinue(in: app, until: question)

        XCTAssertTrue(question.exists, "the four value slides should lead to the question")
    }

    @MainActor
    func testAnsweringTheQuestionMovesOnToThePhotoAsk() throws {
        let app = launchFirstRun()
        XCTAssertTrue(app.buttons["onboardingContinueButton"].waitForExistence(timeout: 10))
        let choice = app.buttons["onboardingChoice.reels"]
        tapContinue(in: app, until: choice)
        XCTAssertTrue(choice.exists)

        choice.tap()

        XCTAssertTrue(app.staticTexts["Let's use your photos"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["onboardingContinueButton"].label, "Choose Photos")
    }

    @MainActor
    func testSkipGoesStraightToTheOffer() throws {
        let app = launchFirstRun()
        let skip = app.buttons["onboardingSkipButton"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10))

        skip.tap()

        XCTAssertTrue(
            app.buttons["paywallCloseButton"].waitForExistence(timeout: 10),
            "Skip leaves the slides for the paywall, not the app"
        )
    }

    @MainActor
    func testClosingThePaywallDropsIntoTheAppOnTheFreeTier() throws {
        let app = launchFirstRun()
        let skip = app.buttons["onboardingSkipButton"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10))
        skip.tap()

        let close = app.buttons["paywallCloseButton"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        close.tap()

        // No relaunch, no dead end: the tab bar is there and usable.
        XCTAssertTrue(
            app.buttons["templatesButton"].waitForExistence(timeout: 10),
            "declining the offer must leave a working free app"
        )
    }
}
