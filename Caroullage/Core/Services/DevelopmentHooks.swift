//
//  DevelopmentHooks.swift
//  Caroullage
//
//  Every switch that exists for the simulator, the UI tests or the screenshot
//  pipeline, in one place and compiled only into Debug builds. A Release build
//  answers each one with its shipping value, so no launch argument and no
//  edited preferences file can unlock Premium, silence the rating prompt or
//  stage sample content on a customer's phone. TestFlight (Staging) builds
//  behave like the App Store build, which is the point of TestFlight.
//
//  `DevelopmentHooksTests` fails if a hook key is read anywhere else, or
//  outside an `#if DEBUG` block here.
//

import Foundation

enum DevelopmentHooks {

    /// `-UITestMode`: set by every UI test. Silences what would block the
    /// runner — the reminders' authorization prompt, the rating sheet — and
    /// lets `-deepLink` route.
    static var isUITest: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-UITestMode")
        #else
        return false
        #endif
    }

    /// `-ScreenshotMode`: the editors open filled with the bundled sample
    /// photography (`ScreenshotStaging`, phase 6.7).
    static var isScreenshotMode: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-ScreenshotMode")
        #else
        return false
        #endif
    }

    /// `debug.premiumUnlocked`: premium flows on a machine that cannot buy.
    static func isPremiumOverridden(in defaults: UserDefaults = .standard) -> Bool {
        #if DEBUG
        return defaults.bool(forKey: "debug.premiumUnlocked")
        #else
        return false
        #endif
    }

    /// `debug.homeDate YYYY-MM-DD`: walk Home's seasonal windows without
    /// waiting for the season.
    static func homeDate(in defaults: UserDefaults = .standard) -> String? {
        #if DEBUG
        return defaults.string(forKey: "debug.homeDate")
        #else
        return nil
        #endif
    }

    /// `-deepLink caroullage://…`, honoured only under `-UITestMode`: XCUITest
    /// cannot open a URL into the app under test, so this is how
    /// `DeepLinkUITests` drives the routes.
    static func launchDeepLink(in defaults: UserDefaults = .standard) -> String? {
        #if DEBUG
        guard isUITest else { return nil }
        return defaults.string(forKey: "deepLink")
        #else
        return nil
        #endif
    }
}
