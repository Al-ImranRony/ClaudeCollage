//
//  XCUIApplication+UnderTest.swift
//  CaroullageUITests
//
//  Step 06 phase 6.3 — one place that decides what state the app launches in.
//
//  Onboarding runs on first launch, which for a UI test means every launch on a
//  clean simulator. Passing `-hasSeenOnboarding YES` puts that flag in
//  UserDefaults' argument domain, which outranks what the app itself writes, so
//  tests land on the tab bar. `OnboardingUITests` asks for the funnel explicitly.
//
//  The suite also pins English. Assertions across it match nav titles the app
//  resolves through `String(localized:)` — "Collage Templates", "Caroullage",
//  "Grid Collage" — so they are only stable while the run's language is the one
//  those literals are written in. That holds today because the string catalog is
//  largely unpopulated, which makes it luck rather than intent; `-AppleLanguages
//  (en)` states the assumption instead of relying on the host's language.
//

import XCTest

extension XCUIApplication {

    static func underTest(hasSeenOnboarding: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-hasSeenOnboarding", hasSeenOnboarding ? "YES" : "NO"]
        app.launchArguments += ["-AppleLanguages", "(en)"]
        // Phase 6.9: the rating prompt stays silent under this flag. On a
        // development build the system's review sheet appears on every request,
        // which would land on top of ExportSaveUITests' success moment.
        app.launchArguments += ["-UITestMode", "1"]
        return app
    }
}

extension XCUIApplication {

    /// A locked card on the Collage tab, ready to tap.
    ///
    /// The tab browses as shelves, whose cards are `templateShelfCard.*` (a card
    /// half off-screen in a sideways shelf is not tappable), and its vertical
    /// grid of `templateCard.*` closes the page far below. The Instant chip
    /// collapses the tab to a results grid with a premium print near the top.
    @MainActor
    func lockedCollageTemplateCard(maxScrolls: Int = 8) -> XCUIElement {
        let chip = staticTexts["categoryChip-Instant"]
        if chip.waitForExistence(timeout: 5) { chip.tap() }
        let grid = collectionViews["templateGalleryGrid"]
        let locked = cells.matching(identifier: "templateCard.premium").firstMatch
        var scrolls = 0
        while !locked.exists, scrolls < maxScrolls {
            grid.swipeUp()
            scrolls += 1
        }
        return locked
    }
}
