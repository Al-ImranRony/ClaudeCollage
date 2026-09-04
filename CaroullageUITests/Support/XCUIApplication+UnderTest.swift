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
        return app
    }
}
