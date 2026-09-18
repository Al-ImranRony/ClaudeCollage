//
//  EntitlementStoreNotificationTests.swift
//  CaroullageTests
//
//  Home retention, phase 1. The store used to broadcast nothing, so every
//  surface re-read it on appear. Now a change is announced once — and only a
//  change, so a surface observing it never re-renders for a no-op.
//

import XCTest
@testable import Caroullage

@MainActor
final class EntitlementStoreNotificationTests: XCTestCase {

    func testUnlockingPostsOnce() {
        let store = EntitlementStore(isPremiumUnlocked: false)
        let posted = expectation(forNotification: EntitlementStore.didChangeNotification, object: store)
        posted.expectedFulfillmentCount = 1

        store.setPremiumUnlocked(true)

        wait(for: [posted], timeout: 1)
        XCTAssertTrue(store.isPremiumUnlocked)
    }

    func testSettingTheSameValueIsSilent() {
        let store = EntitlementStore(isPremiumUnlocked: true)
        let posted = expectation(forNotification: EntitlementStore.didChangeNotification, object: store)
        posted.isInverted = true

        store.setPremiumUnlocked(true)

        wait(for: [posted], timeout: 0.3)
    }

    func testAnotherStoresChangeDoesNotReachThisObserver() {
        let mine = EntitlementStore(isPremiumUnlocked: false)
        let other = EntitlementStore(isPremiumUnlocked: false)
        let posted = expectation(forNotification: EntitlementStore.didChangeNotification, object: mine)
        posted.isInverted = true

        other.setPremiumUnlocked(true)

        wait(for: [posted], timeout: 0.3)
    }
}
