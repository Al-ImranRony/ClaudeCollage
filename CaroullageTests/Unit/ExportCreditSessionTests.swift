//
//  ExportCreditSessionTests.swift
//  CaroullageTests
//
//  Step 06 phase 6.2b — spending a credit on an export.
//
//  A credit is taken when the export starts and given back if no file comes out
//  of it. The session exists so that "given back" happens exactly once, however
//  many ways an export can end.
//

import XCTest
@testable import Caroullage

@MainActor
final class ExportCreditSessionTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "ExportCreditSessionTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    private func makeSession(startingCredits: Int) -> (ExportCreditSession, CreditStore) {
        let store = CreditStore(defaults: defaults)
        if startingCredits > 0 {
            store.grant(.pack15)
            while store.balance > startingCredits { _ = store.spend() }
        }
        return (ExportCreditSession(credits: store), store)
    }

    func testBeginningAnExportTakesOneCredit() {
        let (session, store) = makeSession(startingCredits: 3)

        XCTAssertTrue(session.begin())

        XCTAssertEqual(store.balance, 2)
        XCTAssertTrue(session.isActive)
    }

    func testBeginningWithNoCreditsFails() {
        let (session, store) = makeSession(startingCredits: 0)

        XCTAssertFalse(session.begin())

        XCTAssertEqual(store.balance, 0)
        XCTAssertFalse(session.isActive)
    }

    func testAFailedExportGivesTheCreditBack() {
        let (session, store) = makeSession(startingCredits: 1)
        _ = session.begin()

        session.failed()

        XCTAssertEqual(store.balance, 1)
        XCTAssertFalse(session.isActive)
    }

    func testACancelledExportGivesTheCreditBack() {
        let (session, store) = makeSession(startingCredits: 1)
        _ = session.begin()

        session.cancelled()

        XCTAssertEqual(store.balance, 1)
    }

    func testASucceededExportKeepsTheCredit() {
        let (session, store) = makeSession(startingCredits: 2)
        _ = session.begin()

        session.succeeded()

        XCTAssertEqual(store.balance, 1)
        XCTAssertFalse(session.isActive)
    }

    func testTheCreditIsOnlyGivenBackOnce() {
        let (session, store) = makeSession(startingCredits: 1)
        _ = session.begin()

        session.failed()
        session.failed()
        session.cancelled()

        XCTAssertEqual(store.balance, 1, "an export can end in more than one way; the refund must not compound")
    }

    func testFailingWithoutHavingBegunRefundsNothing() {
        let (session, store) = makeSession(startingCredits: 1)

        session.failed()

        XCTAssertEqual(store.balance, 1)
    }

    func testASecondExportNeedsASecondCredit() {
        let (session, store) = makeSession(startingCredits: 2)
        _ = session.begin()
        session.succeeded()

        XCTAssertTrue(session.begin())

        XCTAssertEqual(store.balance, 0)
    }
}
