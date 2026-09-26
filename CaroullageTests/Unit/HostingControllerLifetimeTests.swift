//
//  HostingControllerLifetimeTests.swift
//  CaroullageTests
//
//  Pre-submission. The four SwiftUI sheets are built by factories whose root
//  view's callbacks dismiss the controller that hosts them. Capturing that
//  controller strongly (an implicitly unwrapped `var` the closures close over)
//  made controller → root view → closure → controller a cycle: every paywall,
//  special offer, Settings sheet and onboarding run stayed in memory, view
//  model, timers and all, for the life of the process.
//

import SwiftUI
import XCTest
@testable import Caroullage

@MainActor
final class HostingControllerLifetimeTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "HostingControllerLifetimeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        try await super.tearDown()
    }

    private func makeService() -> PurchaseService {
        PurchaseService(gateway: StubPurchaseGateway(), defaults: defaults,
                        entitlements: EntitlementStore(isPremiumUnlocked: false))
    }

    /// Builds a controller, loads its view, lets go of it, and reports whether
    /// anything still holds it.
    private func assertReleased<C: UIViewController>(_ make: () -> C, _ name: String,
                                                    file: StaticString = #filePath, line: UInt = #line) {
        weak var released: C?
        autoreleasepool {
            let controller = make()
            controller.loadViewIfNeeded()
            released = controller
        }
        XCTAssertNil(released, "\(name) outlives its last owner", file: file, line: line)
    }

    func testThePaywallIsReleased() {
        let service = makeService()
        assertReleased({ PaywallHostingController.sheet(service: service) }, "the paywall")
    }

    func testTheSpecialOfferIsReleased() {
        let service = makeService()
        assertReleased({ SpecialOfferHostingController.sheet(service: service) }, "the special offer")
    }

    func testSettingsIsReleased() {
        let entitlements = EntitlementStore(isPremiumUnlocked: false)
        let model = SettingsViewModel(
            service: makeService(), entitlements: entitlements,
            reminders: EngagementReminderScheduler(policy: EngagementReminderPolicy(defaults: defaults)),
            openURL: { _ in })
        assertReleased({ SettingsHostingController.sheet(model: model) }, "Settings")
    }

    func testOnboardingIsReleased() {
        let model = OnboardingViewModel(defaults: defaults)
        assertReleased({ OnboardingHostingController.make(model: model, requestPhotoAccess: { .denied }) },
                       "onboarding")
    }
}
