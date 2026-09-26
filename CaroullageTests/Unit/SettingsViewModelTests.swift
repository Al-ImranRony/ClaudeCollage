//
//  SettingsViewModelTests.swift
//  CaroullageTests
//
//  Home retention, phase 3. The toggle honours the system's answer, restore
//  reports the paywall's exact words, and the version line is never blank.
//

import XCTest
@testable import Caroullage

@MainActor
private final class SpyNotifications: LocalNotificationScheduling {
    var grants = true
    var status: LocalNotificationAuthorization = .notDetermined
    func requestAuthorization() async -> Bool {
        status = grants ? .authorized : .denied
        return grants
    }
    func authorization() async -> LocalNotificationAuthorization { status }
    func schedule(_ request: TrialReminderRequest) async {}
    func cancel(identifier: String) async {}
    func pendingIdentifiers() async -> [String] { [] }
}

@MainActor
final class SettingsViewModelTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var spy: SpyNotifications!
    private var opened: [URL] = []

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "SettingsViewModelTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        spy = SpyNotifications()
        opened = []
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    private func makeModel(gateway: StubPurchaseGateway = StubPurchaseGateway()) -> SettingsViewModel {
        let entitlements = EntitlementStore(isPremiumUnlocked: false)
        let service = PurchaseService(gateway: gateway, defaults: defaults, entitlements: entitlements)
        let reminders = EngagementReminderScheduler(
            notifications: spy, policy: EngagementReminderPolicy(defaults: defaults))
        return SettingsViewModel(service: service, entitlements: entitlements, reminders: reminders) {
            [weak self] in self?.opened.append($0)
        }
    }

    func testRemindersStartOffAndTurnOnWhenTheSystemAgrees() async {
        let model = makeModel()
        XCTAssertFalse(model.remindersEnabled)
        await model.setReminders(true)
        XCTAssertTrue(model.remindersEnabled)
        XCTAssertFalse(model.remindersBlockedBySystem)
    }

    func testARefusedPermissionLeavesTheToggleOffAndPointsAtSettings() async {
        spy.grants = false
        let model = makeModel()
        await model.setReminders(true)
        XCTAssertFalse(model.remindersEnabled)
        XCTAssertTrue(model.remindersBlockedBySystem)

        model.openSystemSettings()
        XCTAssertEqual(opened.last?.absoluteString, UIApplication.openSettingsURLString)
    }

    func testLoadNoticesTheSystemSwitchTurnedOffLater() async {
        let model = makeModel()
        await model.setReminders(true)
        spy.status = .denied
        await model.load()
        XCTAssertTrue(model.remindersBlockedBySystem)
    }

    func testRestoreWithNothingToRestoreSaysSo() async {
        let model = makeModel()
        await model.restore()
        XCTAssertEqual(model.restoreMessage, "No previous purchase found on this Apple Account.")
        XCTAssertNil(model.restoreFailure)
        XCTAssertFalse(model.isRestoring)
    }

    func testTheVersionLineIsNeverBlank() {
        let model = makeModel()
        XCTAssertFalse(model.version.isEmpty)
        XCTAssertTrue(model.version.contains("("), "short version (build)")
    }

    func testLinksOpenThroughTheInjectedOpener() {
        let model = makeModel()
        model.open(LegalLinks.terms)
        model.open(LegalLinks.manageSubscriptions)
        XCTAssertEqual(opened, [LegalLinks.terms, LegalLinks.manageSubscriptions])
    }
}
