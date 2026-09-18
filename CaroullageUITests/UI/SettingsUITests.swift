//
//  SettingsUITests.swift
//  CaroullageUITests
//
//  Home retention, phase 3. The gear on Home opens Settings; Settings can
//  restore, shows the version, and closes back to Home. A deep link opens it
//  too.
//

import XCTest

final class SettingsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(premium: Bool = false, arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication.underTest()
        app.launchArguments += ["-debug.premiumUnlocked", premium ? "YES" : "NO"]
        app.launchArguments += arguments
        app.launch()
        XCTAssertTrue(app.navigationBars["Caroullage"].waitForExistence(timeout: 10),
                      "App launches to Home")
        return app
    }

    @MainActor
    private func openSettings(in app: XCUIApplication) {
        let gear = app.buttons["homeSettingsButton"]
        XCTAssertTrue(gear.waitForExistence(timeout: 5), "Home offers Settings from its header")
        gear.tap()
        XCTAssertTrue(app.otherElements["settingsScreen"].waitForExistence(timeout: 8),
                      "The gear opens the Settings sheet")
    }

    @MainActor
    func testTheGearOpensSettingsWithEverySection() {
        let app = launch()
        openSettings(in: app)

        // SwiftUI exposes a Toggle's identifier on the switch and on its label.
        XCTAssertTrue(app.switches["settingsRemindersToggle"].firstMatch.exists, "Reminders toggle")
        XCTAssertTrue(app.buttons["settingsRestoreButton"].exists, "Restore")
        XCTAssertTrue(app.buttons["settingsManageSubscriptionLink"].exists, "Manage Subscription")
        XCTAssertTrue(app.buttons["settingsTermsLink"].exists)
        XCTAssertTrue(app.buttons["settingsPrivacyLink"].exists)
        // The row is combined for VoiceOver, so the identifier reaches two elements.
        let version = app.staticTexts["settingsVersionLabel"].firstMatch
        XCTAssertTrue(version.exists)
        XCTAssertFalse(version.label.isEmpty, "The version line is never blank")
    }

    // No restore tap here: `AppStore.sync()` on a simulator hangs on a system
    // sign-in alert (see the StoreKit testing note), so the outcome copy is
    // covered by `SettingsViewModelTests` against a stub gateway instead.

    @MainActor
    func testDoneClosesBackToHome() {
        let app = launch()
        openSettings(in: app)

        app.buttons["settingsDoneButton"].tap()
        XCTAssertTrue(app.buttons["homeSettingsButton"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.otherElements["settingsScreen"].exists)
    }

    @MainActor
    func testAPremiumUserSeesTheirStatusAndNoProButton() {
        let app = launch(premium: true)
        openSettings(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["settingsPremiumStatus"].firstMatch
            .waitForExistence(timeout: 5), "Settings tells a premium user they are premium")
        app.buttons["settingsDoneButton"].tap()
        XCTAssertFalse(app.buttons["homeProButton"].waitForExistence(timeout: 2),
                       "A premium user is not sold Pro")
    }

    @MainActor
    func testASettingsDeepLinkOpensTheSheet() {
        let app = launch(arguments: ["-deepLink", "caroullage://settings"])
        XCTAssertTrue(app.otherElements["settingsScreen"].waitForExistence(timeout: 10),
                      "caroullage://settings opens Settings")
    }
}
