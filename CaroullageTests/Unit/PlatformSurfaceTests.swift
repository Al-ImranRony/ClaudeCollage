//
//  PlatformSurfaceTests.swift
//  CaroullageTests
//
//  Step 05 batch C — the widget snapshot, Spotlight identifiers, and the intent
//  router.
//
//  These are the parts that can be proven headlessly. Spotlight's index, the
//  widget's actual rendering and Siri invocation are all device concerns.
//

import XCTest
import Foundation
@testable import Caroullage

final class PlatformSurfaceTests: XCTestCase {

    // MARK: - Widget snapshot

    private func makeEntry(daysAgo: Int, hasThumbnail: Bool = true) -> WidgetProjectEntry {
        WidgetProjectEntry(
            id: UUID(),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000 - Double(daysAgo) * 86_400),
            thumbnailData: hasThumbnail ? Data([0xFF, 0xD8, 0xFF]) : nil)
    }

    func testSnapshotRoundTrips() throws {
        let snapshot = WidgetSnapshot(
            projects: [makeEntry(daysAgo: 0), makeEntry(daysAgo: 1)],
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000))

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    func testAProjectWithNoThumbnailStillEncodes() throws {
        // A project saved before its first thumbnail render must not break the
        // whole snapshot — the widget shows a placeholder tile for it.
        let snapshot = WidgetSnapshot(
            projects: [makeEntry(daysAgo: 0, hasThumbnail: false)], generatedAt: Date())
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        XCTAssertNil(decoded.projects.first?.thumbnailData)
    }

    func testWritingTrimsToTheNewestEntries() throws {
        // Widgets show at most six; writing more would bloat a file the widget
        // process has to parse on every refresh.
        let store = WidgetSnapshotStore()
        let many = (0 ..< 20).map { makeEntry(daysAgo: $0) }
        XCTAssertTrue(store.write(WidgetSnapshot(projects: many, generatedAt: Date())))

        let read = store.read()
        XCTAssertEqual(read.projects.count, WidgetSnapshotStore.maxEntries)
        XCTAssertEqual(read.projects.first?.id, many.first?.id, "Newest survives")
    }

    func testWrittenSnapshotIsSortedNewestFirst() throws {
        let store = WidgetSnapshotStore()
        let oldest = makeEntry(daysAgo: 9)
        let newest = makeEntry(daysAgo: 0)
        // Deliberately written in the wrong order.
        _ = store.write(WidgetSnapshot(projects: [oldest, newest], generatedAt: Date()))

        XCTAssertEqual(store.read().projects.first?.id, newest.id)
    }

    func testReadingWithNoSnapshotYieldsEmptyNotAFailure() {
        // What the widget hits before the app has ever saved — and, until the App
        // Group entitlement lands, on every widget refresh. It must render an
        // empty state rather than fail.
        let store = WidgetSnapshotStore()
        if let url = store.snapshotURL { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(store.read(), .empty)
    }

    func testCorruptSnapshotDegradesToEmpty() throws {
        let store = WidgetSnapshotStore()
        let url = try XCTUnwrap(store.snapshotURL)
        try Data("not json".utf8).write(to: url)
        XCTAssertEqual(store.read(), .empty, "Unreadable data must not crash a widget")
    }

    func testContainerResolvesEvenWithoutTheAppGroup() {
        // The entitlement is deferred to Step 06, so this documents today's
        // behaviour: writing still works, into the app's own container.
        let store = WidgetSnapshotStore()
        XCTAssertNotNil(store.containerURL)
        XCTAssertFalse(store.isSharedContainerAvailable,
                       "No App Group yet — so the widget cannot see this file")
    }

    // MARK: - Spotlight identifiers

    func testProjectIDSurvivesTheIdentifierRoundTrip() {
        let id = UUID()
        let identifier = SpotlightIndexer.identifier(for: id)
        XCTAssertEqual(SpotlightIndexer.projectID(fromIdentifier: identifier), id)
    }

    func testForeignIdentifiersAreRejected() {
        // A Spotlight result from another app must never be parsed as ours.
        XCTAssertNil(SpotlightIndexer.projectID(fromIdentifier: "com.example.other.\(UUID())"))
        XCTAssertNil(SpotlightIndexer.projectID(fromIdentifier: ""))
        XCTAssertNil(SpotlightIndexer.projectID(
            fromIdentifier: "\(SpotlightIndexer.domain).not-a-uuid"))
    }

    func testEveryModeHasReadableSearchText() {
        // Spotlight titles are user-facing; none may fall through to a raw value.
        for mode in CollageMode.allCases {
            let title = SpotlightIndexer.title(for: mode)
            XCTAssertFalse(title.isEmpty)
            XCTAssertEqual(title.first, title.first?.uppercased().first)
            XCTAssertTrue(SpotlightIndexer.keywords(for: mode).contains("collage"),
                          "\(mode) should be findable by searching 'collage'")
        }
    }

    // MARK: - Intent routing

    @MainActor
    func testRequestsBeforeTheAppIsReadyAreReplayed() {
        // An intent fired from a cold launch arrives before the coordinator has
        // wired itself up; dropping it would silently do nothing.
        let router = IntentRouter.shared
        router.onRequest = nil

        router.send(.newGridCollage(photoCount: 4))
        router.send(.exportLastProject)

        var received: [IntentRouter.Request] = []
        router.onRequest = { received.append($0) }

        XCTAssertEqual(received, [.newGridCollage(photoCount: 4), .exportLastProject],
                       "Queued requests replay in order once a handler exists")
        router.onRequest = nil
    }

    @MainActor
    func testRequestsAfterWiringDeliverImmediately() {
        let router = IntentRouter.shared
        var received: [IntentRouter.Request] = []
        router.onRequest = { received.append($0) }

        router.send(.newStoryCarousel(frameCount: 5))
        XCTAssertEqual(received, [.newStoryCarousel(frameCount: 5)])
        router.onRequest = nil
    }
}
