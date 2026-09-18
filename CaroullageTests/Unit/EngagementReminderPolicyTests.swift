//
//  EngagementReminderPolicyTests.swift
//  CaroullageTests
//
//  Home retention, phase 3. Every rule about when the app may notify, against
//  a fixed clock and suite-named defaults.
//

import XCTest
@testable import Caroullage

final class EngagementReminderPolicyTests: XCTestCase {

    private var defaults: UserDefaults!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)   // 2027-01-15 ~08:00 UTC
    private let day: TimeInterval = 24 * 3600
    private let projectID = UUID()

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "EngagementReminderPolicyTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaults.description)
        super.tearDown()
    }

    private func policy(enabled: Bool = true) -> EngagementReminderPolicy {
        let policy = EngagementReminderPolicy(defaults: defaults)
        policy.isEnabled = enabled
        return policy
    }

    private func unfinished(editedAgo: TimeInterval) -> EngagementReminderPolicy.UnfinishedProject {
        .init(id: projectID, name: "Beach day", updatedAt: now.addingTimeInterval(-editedAgo))
    }

    private func seasonal(startsIn: TimeInterval) -> EngagementReminderPolicy.SeasonalDrop {
        .init(collectionID: "spring", title: "Spring", windowStart: now.addingTimeInterval(startsIn))
    }

    private let installedLongAgo = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Gates

    func testOffByDefaultAndNothingWhileOff() {
        let policy = EngagementReminderPolicy(defaults: defaults)
        XCTAssertFalse(policy.isEnabled, "Reminders are opt-in")
        XCTAssertTrue(policy.decisions(
            now: now, installedAt: installedLongAgo,
            unfinished: unfinished(editedAgo: 2 * day), seasonal: seasonal(startsIn: 5 * day)).isEmpty)
    }

    func testNothingInTheFirstDayAfterInstall() {
        let decisions = policy().decisions(
            now: now, installedAt: now.addingTimeInterval(-6 * 3600),
            unfinished: unfinished(editedAgo: 3600), seasonal: seasonal(startsIn: 5 * day))
        XCTAssertTrue(decisions.isEmpty)
    }

    // MARK: - Unfinished project

    func testAnUnfinishedProjectIsNudgedADayAfterTheLastEdit() throws {
        let decision = try XCTUnwrap(policy().decisions(
            now: now, installedAt: installedLongAgo,
            unfinished: unfinished(editedAgo: 3600), seasonal: nil).first)

        XCTAssertEqual(decision.kind, .unfinishedProject)
        XCTAssertEqual(decision.identifier, EngagementReminderPolicy.unfinishedIdentifier)
        XCTAssertEqual(decision.fireDate, now.addingTimeInterval(day - 3600))
        XCTAssertTrue(decision.body.contains("Beach day"), decision.body)
        XCTAssertEqual(decision.deepLink, DeepLink.project(projectID).url)
    }

    func testAnEditOlderThanADayStillFiresAnHourFromNowNotInThePast() throws {
        let decision = try XCTUnwrap(policy().decisions(
            now: now, installedAt: installedLongAgo,
            unfinished: unfinished(editedAgo: 3 * day), seasonal: nil).first)
        XCTAssertEqual(decision.fireDate, now.addingTimeInterval(3600))
    }

    func testWorkOlderThanAWeekIsLeftAlone() {
        XCTAssertTrue(policy().decisions(
            now: now, installedAt: installedLongAgo,
            unfinished: unfinished(editedAgo: 8 * day), seasonal: nil).isEmpty)
    }

    func testTheNudgeKeepsClearOfTheLastOpen() throws {
        let policy = policy()
        policy.recordOpened(now: now.addingTimeInterval(day - 1800))   // opened 30 min before it would fire
        let decision = try XCTUnwrap(policy.decisions(
            now: now, installedAt: installedLongAgo,
            unfinished: unfinished(editedAgo: 0), seasonal: nil).first)
        XCTAssertEqual(decision.fireDate, now.addingTimeInterval(day - 1800 + 2 * 3600))
    }

    // MARK: - Seasonal drop

    func testASeasonalDropFiresAtTenOnTheMorningItsWindowOpens() throws {
        let calendar = Calendar(identifier: .gregorian)
        let start = now.addingTimeInterval(10 * day)
        let decision = try XCTUnwrap(policy().decisions(
            now: now, installedAt: installedLongAgo, unfinished: nil,
            seasonal: .init(collectionID: "spring", title: "Spring", windowStart: start),
            calendar: calendar).first)

        XCTAssertEqual(decision.kind, .seasonalDrop)
        XCTAssertEqual(decision.identifier, "caroullage.reminder.seasonal.spring")
        XCTAssertEqual(calendar.component(.hour, from: decision.fireDate), 10)
        XCTAssertTrue(calendar.isDate(decision.fireDate, inSameDayAs: start))
        XCTAssertTrue(decision.title.contains("Spring"))
        XCTAssertEqual(decision.deepLink, DeepLink.collection("spring").url)
    }

    func testAWindowAlreadyOpenOrTooFarAwayIsNotBooked() {
        let policy = policy()
        XCTAssertTrue(policy.decisions(
            now: now, installedAt: installedLongAgo, unfinished: nil,
            seasonal: seasonal(startsIn: -day)).isEmpty, "already open")
        XCTAssertTrue(policy.decisions(
            now: now, installedAt: installedLongAgo, unfinished: nil,
            seasonal: seasonal(startsIn: 90 * day)).isEmpty, "too far ahead")
    }

    func testASeasonIsAnnouncedOnceEvenAcrossRelaunches() throws {
        let first = policy()
        let decision = try XCTUnwrap(first.decisions(
            now: now, installedAt: installedLongAgo, unfinished: nil,
            seasonal: seasonal(startsIn: 5 * day)).first)
        first.recordScheduled(decision)

        let relaunched = EngagementReminderPolicy(defaults: defaults)
        XCTAssertTrue(relaunched.decisions(
            now: now, installedAt: installedLongAgo, unfinished: nil,
            seasonal: seasonal(startsIn: 5 * day)).isEmpty)
    }

    // MARK: - Caps

    func testOnlyOneReminderAWeek() throws {
        let policy = policy()
        let decisions = policy.decisions(
            now: now, installedAt: installedLongAgo,
            unfinished: unfinished(editedAgo: 0), seasonal: seasonal(startsIn: 3 * day))
        XCTAssertEqual(decisions.map(\.kind), [.unfinishedProject],
                       "The seasonal drop three days later would be a second reminder that week")
    }

    func testASeasonalDropAWeekAwayFitsBesideTheNudge() {
        let decisions = policy().decisions(
            now: now, installedAt: installedLongAgo,
            unfinished: unfinished(editedAgo: 0), seasonal: seasonal(startsIn: 9 * day))
        XCTAssertEqual(decisions.map(\.kind), [.unfinishedProject, .seasonalDrop])
    }

    func testTwoAMonthAtMost() throws {
        let policy = policy()
        // Two already booked inside the month, a week apart from each other
        // and from the candidate.
        policy.recordScheduled(.init(
            kind: .seasonalDrop, identifier: "caroullage.reminder.seasonal.a", title: "", body: "",
            fireDate: now.addingTimeInterval(-9 * day), deepLink: DeepLink.settings.url))
        policy.recordScheduled(.init(
            kind: .seasonalDrop, identifier: "caroullage.reminder.seasonal.b", title: "", body: "",
            fireDate: now.addingTimeInterval(-18 * day), deepLink: DeepLink.settings.url))

        XCTAssertTrue(policy.decisions(
            now: now, installedAt: installedLongAgo,
            unfinished: unfinished(editedAgo: 0), seasonal: nil).isEmpty)
    }

    func testReBookingTheNudgeDoesNotCountAgainstItself() throws {
        let policy = policy()
        let first = try XCTUnwrap(policy.decisions(
            now: now, installedAt: installedLongAgo,
            unfinished: unfinished(editedAgo: 0), seasonal: nil).first)
        policy.recordScheduled(first)

        // Edited again an hour later: the nudge moves, it is not blocked.
        let later = now.addingTimeInterval(3600)
        let moved = try XCTUnwrap(policy.decisions(
            now: later, installedAt: installedLongAgo,
            unfinished: .init(id: projectID, name: "Beach day", updatedAt: later), seasonal: nil).first)
        XCTAssertEqual(moved.identifier, first.identifier)
        XCTAssertGreaterThan(moved.fireDate, first.fireDate)
    }

    func testCancellingForgetsTheBooking() throws {
        let policy = policy()
        let decision = try XCTUnwrap(policy.decisions(
            now: now, installedAt: installedLongAgo,
            unfinished: unfinished(editedAgo: 0), seasonal: nil).first)
        policy.recordScheduled(decision)
        XCTAssertEqual(policy.scheduled.count, 1)
        policy.recordCancelled(identifier: decision.identifier)
        XCTAssertTrue(policy.scheduled.isEmpty)
    }
}
