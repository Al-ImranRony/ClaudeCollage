//
//  FavoritesStoreTests.swift
//  CaroullageTests
//
//  Home retention, phase 4. Toggle, persist, keep order, announce.
//

import XCTest
@testable import Caroullage

@MainActor
final class FavoritesStoreTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        defaults = UserDefaults(suiteName: "FavoritesStoreTests-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: defaults.description)
        try await super.tearDown()
    }

    private let bloom = FavoritesStore.Item(kind: .photo, id: "seasonal-bloom")
    private let team = FavoritesStore.Item(kind: .carousel, id: "carousel-matched-team")

    func testNothingIsSavedAtFirst() {
        let store = FavoritesStore(defaults: defaults)
        XCTAssertFalse(store.isSaved(bloom))
        XCTAssertEqual(store.count, 0)
        XCTAssertTrue(store.savedIDs(kind: .photo).isEmpty)
    }

    func testToggleSavesThenRemoves() {
        let store = FavoritesStore(defaults: defaults)
        XCTAssertTrue(store.toggle(bloom))
        XCTAssertTrue(store.isSaved(bloom))
        XCTAssertFalse(store.toggle(bloom))
        XCTAssertFalse(store.isSaved(bloom))
    }

    func testSavedIDsKeepInsertionOrderPerKind() {
        let store = FavoritesStore(defaults: defaults)
        store.toggle(team)
        store.toggle(bloom)
        store.toggle(FavoritesStore.Item(kind: .photo, id: "grid-filmstrip"))

        XCTAssertEqual(store.savedIDs(kind: .photo), ["seasonal-bloom", "grid-filmstrip"])
        XCTAssertEqual(store.savedIDs(kind: .carousel), ["carousel-matched-team"])
    }

    func testTheSameIDInTwoKindsIsTwoItems() {
        let store = FavoritesStore(defaults: defaults)
        store.toggle(FavoritesStore.Item(kind: .photo, id: "x"))
        XCTAssertFalse(store.isSaved(FavoritesStore.Item(kind: .carousel, id: "x")))
    }

    func testFavouritesSurviveARelaunch() {
        FavoritesStore(defaults: defaults).toggle(bloom)
        XCTAssertTrue(FavoritesStore(defaults: defaults).isSaved(bloom))
    }

    func testAToggleIsAnnounced() {
        let store = FavoritesStore(defaults: defaults)
        let posted = expectation(forNotification: FavoritesStore.didChangeNotification, object: store)
        store.toggle(bloom)
        wait(for: [posted], timeout: 1)
    }

    func testAMalformedStoredKeyIsIgnored() {
        defaults.set(["photo:seasonal-bloom", "garbage", "video:x", "carousel:"], forKey: "favorites.items")
        let store = FavoritesStore(defaults: defaults)
        XCTAssertEqual(store.savedIDs(kind: .photo), ["seasonal-bloom"])
        XCTAssertTrue(store.savedIDs(kind: .carousel).isEmpty)
    }
}
