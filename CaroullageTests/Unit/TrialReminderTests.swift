//
//  TrialReminderTests.swift
//  CaroullageTests
//
//  Step 06 phase 6.3 — the trial-end reminder.
//
//  Apple has tightened review on trial dark patterns, and this is the feature
//  most easily turned into one. The rules here are the honest reading: warn a
//  day before, name the exact amount, say plainly that cancelling avoids it, and
//  take the reminder away the moment it stops being true.
//

import XCTest
@testable import Caroullage

@MainActor
final class TrialReminderTests: XCTestCase {

    private var notifications: SpyNotificationScheduler!
    private var scheduler: TrialReminderScheduler!
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() async throws {
        try await super.setUp()
        notifications = SpyNotificationScheduler()
        scheduler = TrialReminderScheduler(notifications: notifications)
    }

    func testTheReminderLandsADayBeforeTheChargeNotAfterIt() async {
        await scheduler.scheduleReminder(trialDays: 7, price: "$24.99", period: "year", from: start)

        let expected = start.addingTimeInterval(6 * 24 * 3600)
        XCTAssertEqual(notifications.scheduled?.fireDate, expected)
    }

    func testTheReminderNamesTheExactAmountAboutToBeCharged() async {
        await scheduler.scheduleReminder(trialDays: 7, price: "$24.99", period: "year", from: start)

        let body = notifications.scheduled?.body ?? ""
        XCTAssertTrue(body.contains("$24.99"), body)
        XCTAssertTrue(body.contains("year"), body)
    }

    func testTheReminderSaysCancellingAvoidsTheCharge() async {
        await scheduler.scheduleReminder(trialDays: 7, price: "$24.99", period: "year", from: start)

        XCTAssertTrue((notifications.scheduled?.body ?? "").lowercased().contains("cancel"))
    }

    func testAShortTrialStillWarnsBeforeItEnds() async {
        // A 1-day trial cannot be warned about a day early; warn at three
        // quarters through rather than not at all.
        await scheduler.scheduleReminder(trialDays: 1, price: "$4.99", period: "month", from: start)

        let fired = try? XCTUnwrap(notifications.scheduled?.fireDate)
        XCTAssertNotNil(fired)
        XCTAssertGreaterThan(fired!, start)
        XCTAssertLessThan(fired!, start.addingTimeInterval(24 * 3600))
    }

    func testNothingIsScheduledWithoutPermission() async {
        notifications.isAuthorized = false

        await scheduler.scheduleReminder(trialDays: 7, price: "$24.99", period: "year", from: start)

        XCTAssertNil(notifications.scheduled, "a reminder nobody agreed to is spam")
    }

    func testNothingIsScheduledWhenThereIsNoTrial() async {
        await scheduler.scheduleReminder(trialDays: nil, price: "$24.99", period: "year", from: start)

        XCTAssertNil(notifications.scheduled)
    }

    func testTheReminderIsRemovedWhenItStopsBeingTrue() async {
        await scheduler.scheduleReminder(trialDays: 7, price: "$24.99", period: "year", from: start)

        await scheduler.cancelReminder()

        XCTAssertTrue(notifications.didCancel)
    }

    func testSchedulingTwiceLeavesOneReminderNotTwo() async {
        await scheduler.scheduleReminder(trialDays: 7, price: "$24.99", period: "year", from: start)
        await scheduler.scheduleReminder(trialDays: 7, price: "$24.99", period: "year", from: start)

        XCTAssertEqual(notifications.scheduleCount, 2)
        XCTAssertEqual(notifications.identifiers.count, 1, "the same identifier replaces, rather than stacks")
    }
}

private final class SpyNotificationScheduler: TrialNotificationScheduling {
    var isAuthorized = true
    var scheduled: TrialReminderRequest?
    var scheduleCount = 0
    var identifiers: Set<String> = []
    var didCancel = false

    func requestAuthorization() async -> Bool { isAuthorized }

    func schedule(_ request: TrialReminderRequest) async {
        scheduled = request
        scheduleCount += 1
        identifiers.insert(request.identifier)
    }

    func cancel(identifier: String) async {
        didCancel = true
        identifiers.remove(identifier)
    }
}
