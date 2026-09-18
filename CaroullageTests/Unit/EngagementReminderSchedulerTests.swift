//
//  EngagementReminderSchedulerTests.swift
//  CaroullageTests
//
//  Home retention, phase 3. The scheduler against a spy: what the policy
//  decides is booked with its deep link, what it no longer wants is cancelled,
//  the toggle asks the system exactly once, and turning it off clears
//  everything.
//

import XCTest
@testable import Caroullage

@MainActor
private final class SpyLocalNotifications: LocalNotificationScheduling {
    var grants = true
    var status: LocalNotificationAuthorization = .notDetermined
    var authorizationRequests = 0
    var scheduled: [TrialReminderRequest] = []
    var cancelled: [String] = []

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        status = grants ? .authorized : .denied
        return grants
    }

    func authorization() async -> LocalNotificationAuthorization { status }
    func schedule(_ request: TrialReminderRequest) async { scheduled.append(request) }
    func cancel(identifier: String) async { cancelled.append(identifier) }
    func pendingIdentifiers() async -> [String] { scheduled.map(\.identifier) }
}

@MainActor
final class EngagementReminderSchedulerTests: XCTestCase {

    private var defaults: UserDefaults!
    private var spy: SpyLocalNotifications!
    private var scheduler: EngagementReminderScheduler!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let installed = Date(timeIntervalSince1970: 1_700_000_000)
    private let day: TimeInterval = 24 * 3600

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "EngagementReminderSchedulerTests-\(UUID().uuidString)")
        spy = SpyLocalNotifications()
        scheduler = EngagementReminderScheduler(
            notifications: spy, policy: EngagementReminderPolicy(defaults: defaults))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaults.description)
        super.tearDown()
    }

    private var unfinished: EngagementReminderPolicy.UnfinishedProject {
        .init(id: UUID(), name: "Beach day", updatedAt: now.addingTimeInterval(-3600))
    }

    func testTurningOnAsksTheSystemAndRemembersTheAnswer() async {
        let granted = await scheduler.setEnabled(true)
        XCTAssertTrue(granted)
        XCTAssertEqual(spy.authorizationRequests, 1)
        XCTAssertTrue(scheduler.isEnabled)
    }

    func testARefusalLeavesRemindersOff() async {
        spy.grants = false
        let granted = await scheduler.setEnabled(true)
        XCTAssertFalse(granted)
        XCTAssertFalse(scheduler.isEnabled)
    }

    func testRefreshBooksTheNudgeWithItsDeepLink() async {
        await scheduler.setEnabled(true)
        await scheduler.refresh(now: now, installedAt: installed, unfinished: unfinished, seasonal: nil)

        XCTAssertEqual(spy.scheduled.count, 1)
        let request = spy.scheduled[0]
        XCTAssertEqual(request.identifier, EngagementReminderPolicy.unfinishedIdentifier)
        XCTAssertNotNil(request.deepLink)
        XCTAssertEqual(DeepLink.parse(request.deepLink!)?.analyticsKind, "project")
    }

    func testNothingIsBookedWhileOff() async {
        await scheduler.refresh(now: now, installedAt: installed, unfinished: unfinished, seasonal: nil)
        XCTAssertTrue(spy.scheduled.isEmpty)
    }

    func testAnExportedProjectCancelsThePendingNudge() async {
        await scheduler.setEnabled(true)
        await scheduler.refresh(now: now, installedAt: installed, unfinished: unfinished, seasonal: nil)
        spy.cancelled.removeAll()

        // Next background: nothing unfinished any more.
        await scheduler.refresh(now: now.addingTimeInterval(3600), installedAt: installed,
                                unfinished: nil, seasonal: nil)
        XCTAssertEqual(spy.cancelled, [EngagementReminderPolicy.unfinishedIdentifier])
    }

    func testComingBackCancelsTheNudgeAndRecordsTheOpen() async {
        await scheduler.setEnabled(true)
        await scheduler.refresh(now: now, installedAt: installed, unfinished: unfinished, seasonal: nil)
        await scheduler.noteOpened(now: now.addingTimeInterval(600))

        XCTAssertTrue(spy.cancelled.contains(EngagementReminderPolicy.unfinishedIdentifier))
        XCTAssertEqual(EngagementReminderPolicy(defaults: defaults).lastOpenedAt, now.addingTimeInterval(600))
    }

    func testTurningOffClearsEverythingBooked() async {
        await scheduler.setEnabled(true)
        let drop = EngagementReminderPolicy.SeasonalDrop(
            collectionID: "spring", title: "Spring", windowStart: now.addingTimeInterval(10 * day))
        await scheduler.refresh(now: now, installedAt: installed, unfinished: unfinished, seasonal: drop)
        XCTAssertEqual(spy.scheduled.count, 2)

        await scheduler.setEnabled(false)
        XCTAssertFalse(scheduler.isEnabled)
        XCTAssertTrue(spy.cancelled.contains(EngagementReminderPolicy.unfinishedIdentifier))
        XCTAssertTrue(spy.cancelled.contains("caroullage.reminder.seasonal.spring"))
        XCTAssertTrue(EngagementReminderPolicy(defaults: defaults).scheduled.isEmpty)
    }
}
