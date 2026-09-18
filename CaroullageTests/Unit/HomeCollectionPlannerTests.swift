//
//  HomeCollectionPlannerTests.swift
//  CaroullageTests
//
//  Home retention, phase 2. The planner is the whole reason Home stops being
//  the same screen every day, so every rule is pinned against a fixed clock:
//  windows (and the new-year wrap), pinning, affinity, weekly rotation, the
//  cap, and the pillars that survive it.
//

import XCTest
@testable import Caroullage

final class HomeCollectionPlannerTests: XCTestCase {

    private var calendar: Calendar { HomeCollectionPlanner.calendar }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return calendar.date(from: components)!
    }

    private func collection(
        _ id: String, kind: HomeCollection.Kind = .photo, items: [String] = ["a", "b", "c"],
        window: HomeCollection.Window? = nil, isNew: Bool = false, creatorKinds: [String] = [],
        weeklyPick: Int? = nil, isPillar: Bool = false, priority: Int = 0
    ) -> HomeCollection {
        HomeCollection(
            id: id, titleKey: id, kind: kind, itemIDs: items, window: window, isNew: isNew,
            creatorKinds: creatorKinds, weeklyPick: weeklyPick, isPillar: isPillar,
            priority: priority)
    }

    // MARK: - Windows

    func testAWindowIsInclusiveAtBothEnds() {
        let autumn = HomeCollection.Window(start: "09-01", end: "11-15")
        XCTAssertTrue(HomeCollectionPlanner.isInWindow(autumn, now: date(2026, 9, 1)))
        XCTAssertTrue(HomeCollectionPlanner.isInWindow(autumn, now: date(2026, 10, 20)))
        XCTAssertTrue(HomeCollectionPlanner.isInWindow(autumn, now: date(2026, 11, 15)))
        XCTAssertFalse(HomeCollectionPlanner.isInWindow(autumn, now: date(2026, 8, 31)))
        XCTAssertFalse(HomeCollectionPlanner.isInWindow(autumn, now: date(2026, 11, 16)))
    }

    func testAWindowWrapsTheNewYear() {
        let holiday = HomeCollection.Window(start: "11-16", end: "01-05")
        XCTAssertTrue(HomeCollectionPlanner.isInWindow(holiday, now: date(2026, 12, 25)))
        XCTAssertTrue(HomeCollectionPlanner.isInWindow(holiday, now: date(2027, 1, 5)))
        XCTAssertTrue(HomeCollectionPlanner.isInWindow(holiday, now: date(2026, 11, 16)))
        XCTAssertFalse(HomeCollectionPlanner.isInWindow(holiday, now: date(2027, 1, 6)))
        XCTAssertFalse(HomeCollectionPlanner.isInWindow(holiday, now: date(2026, 6, 1)))
    }

    func testAMalformedWindowIsNeverLive() {
        let broken = HomeCollection.Window(start: "13-40", end: "x")
        XCTAssertFalse(HomeCollectionPlanner.isInWindow(broken, now: date(2026, 9, 17)))
    }

    // MARK: - Ordering

    func testOutOfSeasonCollectionsAreDroppedAndInSeasonOnesLead() {
        let plan = HomeCollectionPlanner.plan([
            collection("everyday"),
            collection("holiday", window: .init(start: "11-16", end: "01-05")),
            collection("autumn", window: .init(start: "09-01", end: "11-15")),
        ], now: date(2026, 9, 17), creatorKind: nil)

        XCTAssertEqual(plan.map(\.id), ["autumn", "everyday"])
    }

    func testNewCollectionsArePinnedAndPriorityBreaksTies() {
        let plan = HomeCollectionPlanner.plan([
            collection("everyday"),
            collection("just-landed", isNew: true, priority: 1),
            collection("autumn", window: .init(start: "09-01", end: "11-15"), priority: 10),
        ], now: date(2026, 9, 17), creatorKind: nil)

        XCTAssertEqual(plan.map(\.id), ["autumn", "just-landed", "everyday"])
    }

    func testAffinityLiftsWhatTheUserSaidTheyMakeAboveTheRest() {
        let collections = [
            collection("grids", creatorKinds: ["pinterest"]),
            collection("everyday"),
            collection("carousels", kind: .carousel, creatorKinds: ["carousels"]),
        ]
        let forCarousels = HomeCollectionPlanner.plan(
            collections, now: date(2026, 9, 17), creatorKind: .carousels)
        XCTAssertEqual(forCarousels.first?.id, "carousels")

        let forPinterest = HomeCollectionPlanner.plan(
            collections, now: date(2026, 9, 17), creatorKind: .pinterest)
        XCTAssertEqual(forPinterest.first?.id, "grids")

        let noAnswer = HomeCollectionPlanner.plan(
            collections, now: date(2026, 9, 17), creatorKind: nil)
        XCTAssertEqual(Set(noAnswer.map(\.id)), Set(collections.map(\.id)),
                       "Without an answer nothing is lifted, but nothing is lost either")
    }

    func testTheRestRotatesWeeklyAndIsStableWithinAWeek() {
        let collections = (1 ... 4).map { collection("c\($0)") }

        let monday = HomeCollectionPlanner.plan(collections, now: date(2026, 9, 14), creatorKind: nil)
        let friday = HomeCollectionPlanner.plan(collections, now: date(2026, 9, 18), creatorKind: nil)
        XCTAssertEqual(monday.map(\.id), friday.map(\.id), "The same week reads the same all week")

        let nextWeek = HomeCollectionPlanner.plan(collections, now: date(2026, 9, 21), creatorKind: nil)
        XCTAssertNotEqual(monday.map(\.id), nextWeek.map(\.id), "A new week reads differently")
        XCTAssertEqual(Set(nextWeek.map(\.id)), Set(monday.map(\.id)), "…but nothing is lost")
    }

    func testTheCapAppliesToChosenStripsButNeverToPillars() {
        let collections = (1 ... 8).map { collection("c\($0)") }
            + [collection("photo", isPillar: true), collection("video", kind: .video, isPillar: true)]

        let plan = HomeCollectionPlanner.plan(
            collections, now: date(2026, 9, 17), creatorKind: nil, maxStrips: 3)

        XCTAssertEqual(plan.count, 5)
        XCTAssertEqual(plan.suffix(2).map(\.id), ["photo", "video"], "Pillars close the screen, in file order")
        XCTAssertFalse(plan.prefix(3).contains { $0.isPillar })
    }

    func testPinnedCollectionsCountAgainstTheCap() {
        let collections = [
            collection("autumn", window: .init(start: "09-01", end: "11-15")),
            collection("new", isNew: true),
            collection("c1"), collection("c2"),
        ]
        let plan = HomeCollectionPlanner.plan(
            collections, now: date(2026, 9, 17), creatorKind: nil, maxStrips: 2)
        XCTAssertEqual(plan.map(\.id), ["autumn", "new"])
    }

    // MARK: - Weekly picks

    func testAWeeklyPickSlicesADifferentSetEachWeek() {
        let picks = collection("picks", items: (1 ... 12).map { "t\($0)" }, weeklyPick: 4)

        let thisWeek = HomeCollectionPlanner.plan([picks], now: date(2026, 9, 17), creatorKind: nil)
        let nextWeek = HomeCollectionPlanner.plan([picks], now: date(2026, 9, 24), creatorKind: nil)

        XCTAssertEqual(thisWeek.first?.itemIDs.count, 4)
        XCTAssertEqual(nextWeek.first?.itemIDs.count, 4)
        XCTAssertNotEqual(thisWeek.first?.itemIDs, nextWeek.first?.itemIDs)
        XCTAssertTrue(Set(thisWeek.first!.itemIDs).isSubset(of: Set(picks.itemIDs)))
    }

    func testAWeeklyPickLargerThanTheListShowsTheWholeList() {
        let picks = collection("picks", items: ["a", "b"], weeklyPick: 6)
        let plan = HomeCollectionPlanner.plan([picks], now: date(2026, 9, 17), creatorKind: nil)
        XCTAssertEqual(plan.first?.itemIDs, ["a", "b"])
    }

    // MARK: - Debug clock

    func testTheDebugDateOverrideParsesAndRejectsGarbage() {
        let defaults = UserDefaults(suiteName: "HomeCollectionPlannerTests-\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.description) }

        XCTAssertNil(HomeCollectionPlanner.overrideDate(from: defaults))

        defaults.set("2026-12-25", forKey: "debug.homeDate")
        let overridden = try! XCTUnwrap(HomeCollectionPlanner.overrideDate(from: defaults))
        XCTAssertEqual(calendar.component(.month, from: overridden), 12)
        XCTAssertEqual(calendar.component(.day, from: overridden), 25)

        defaults.set("christmas", forKey: "debug.homeDate")
        XCTAssertNil(HomeCollectionPlanner.overrideDate(from: defaults))
    }

    // MARK: - Next seasonal drop

    func testTheNextSeasonalDropIsTheEarliestWindowStillAhead() throws {
        let collections = [
            collection("autumn", window: .init(start: "09-01", end: "11-15")),
            collection("holiday", window: .init(start: "11-16", end: "01-05")),
            collection("spring", window: .init(start: "03-01", end: "05-31")),
            collection("everyday"),
        ]
        let next = try XCTUnwrap(HomeCollectionPlanner.nextSeasonalDrop(collections, after: date(2026, 9, 17)))
        XCTAssertEqual(next.collection.id, "holiday", "Autumn is already open; the holiday window is next")
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: next.windowStart),
                       DateComponents(year: 2026, month: 11, day: 16))

        let wrapped = try XCTUnwrap(HomeCollectionPlanner.nextSeasonalDrop(collections, after: date(2026, 12, 1)))
        XCTAssertEqual(wrapped.collection.id, "spring", "Past the last window of the year, next year's first")
        XCTAssertEqual(calendar.component(.year, from: wrapped.windowStart), 2027)
    }

    func testNoWindowsMeansNoDrop() {
        XCTAssertNil(HomeCollectionPlanner.nextSeasonalDrop([collection("everyday")], after: date(2026, 9, 17)))
    }
}
