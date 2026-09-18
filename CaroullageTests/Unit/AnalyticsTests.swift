//
//  AnalyticsTests.swift
//  CaroullageTests
//
//  Home retention, phase 1. The seam is only worth having if the names on the
//  wire are stable and every event reaches whatever is installed.
//

import XCTest
@testable import Caroullage

@MainActor
final class SpyAnalytics: AnalyticsTracking {
    private(set) var events: [AnalyticsEvent] = []
    func track(_ event: AnalyticsEvent) { events.append(event) }
}

@MainActor
final class AnalyticsTests: XCTestCase {

    private var previous: (any AnalyticsTracking)!

    override func setUp() {
        super.setUp()
        previous = Analytics.tracker
    }

    override func tearDown() {
        Analytics.tracker = previous
        super.tearDown()
    }

    func testTheInstalledTrackerReceivesEveryEvent() {
        let spy = SpyAnalytics()
        Analytics.tracker = spy

        Analytics.track(.settingsOpened)
        Analytics.track(.templateOpened(id: "grid-4cell-square", source: "home"))

        XCTAssertEqual(spy.events, [
            .settingsOpened,
            .templateOpened(id: "grid-4cell-square", source: "home"),
        ])
    }

    func testWireNamesAreSnakeCaseAndUnique() {
        let all: [AnalyticsEvent] = [
            .homeSectionShown(id: "a"), .collectionSeeAll(id: "a"),
            .templateOpened(id: "a", source: "b"), .heroTapped(id: "a"), .recentResumed,
            .suggestionOpened(template: "a"), .favouriteToggled(id: "a", saved: true),
            .settingsOpened, .restore(result: "ok"), .reminderScheduled(kind: "a"),
            .reminderOpened(kind: "a"), .deepLinkOpened(kind: "a"),
        ]
        let names = all.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "two events must never share a series")
        for name in names {
            XCTAssertEqual(name, name.lowercased())
            XCTAssertFalse(name.contains(" "))
            XCTAssertFalse(name.contains("-"))
        }
    }

    func testParametersCarryEveryAssociatedValueAsStrings() {
        XCTAssertEqual(
            AnalyticsEvent.templateOpened(id: "x", source: "hero").parameters,
            ["id": "x", "source": "hero"])
        XCTAssertEqual(
            AnalyticsEvent.favouriteToggled(id: "x", saved: false).parameters,
            ["id": "x", "saved": "false"])
        XCTAssertEqual(AnalyticsEvent.recentResumed.parameters, [:])
    }

    func testTheConsoleTrackerDoesNotCrashOnAnyEvent() {
        // The default implementation is what ships; it must accept everything.
        let console = ConsoleAnalytics()
        console.track(.deepLinkOpened(kind: "project"))
        console.track(.recentResumed)
    }
}
