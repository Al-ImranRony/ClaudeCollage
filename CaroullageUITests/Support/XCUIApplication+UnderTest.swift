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

import XCTest

extension XCUIApplication {

    static func underTest(hasSeenOnboarding: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-hasSeenOnboarding", hasSeenOnboarding ? "YES" : "NO"]
        return app
    }
}
