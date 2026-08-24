//
//  SuccessOverlayTests.swift
//  CaroullageTests
//
//  Step 05b Part D. The export celebration is transient by design, which makes
//  it awkward to assert from a UI test — it races the SpringBoard round-trip and
//  is gone before the assertion lands. Its contract is testable directly though:
//  it attaches, it says what happened, and it cleans itself up.
//

import UIKit
import XCTest
@testable import Caroullage

@MainActor
final class SuccessOverlayTests: XCTestCase {

    private func makeHost() -> UIView {
        UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    }

    func testPresentingAttachesItToTheHostAtFullBleed() {
        let host = makeHost()
        let overlay = SuccessOverlayView(message: "Saved to Photos")
        overlay.present(in: host)

        XCTAssertTrue(overlay.isDescendant(of: host))
        host.layoutIfNeeded()
        XCTAssertEqual(overlay.bounds.size, host.bounds.size)
    }

    /// One element, not three: VoiceOver should hear the outcome, not a card, a
    /// decorative tick and a label.
    func testItReadsAsASingleAnnouncement() {
        let overlay = SuccessOverlayView(message: "Saved 4 images")
        XCTAssertTrue(overlay.isAccessibilityElement)
        XCTAssertEqual(overlay.accessibilityLabel, "Saved 4 images")
    }

    /// It must never intercept a tap: the user's next move is usually to leave
    /// for another app, and a full-bleed view that swallows touches would sit in
    /// the way for over a second.
    func testItDoesNotSwallowTouches() {
        let host = makeHost()
        let overlay = SuccessOverlayView(message: "Saved to Photos")
        overlay.present(in: host)
        XCTAssertFalse(overlay.isUserInteractionEnabled)
    }

    func testItRemovesItselfWhenTheMomentIsOver() {
        let host = makeHost()
        let overlay = SuccessOverlayView(message: "Saved to Photos")
        // A short hold so the test does not wait on the production timing.
        overlay.present(in: host, holding: 0.05)

        let gone = expectation(description: "overlay removed")
        // Polling rather than a fixed sleep: the spring + fade durations vary
        // with Reduce Motion, which the test host does not control.
        let start = Date()
        func poll() {
            if overlay.superview == nil {
                gone.fulfill()
            } else if Date().timeIntervalSince(start) < 4 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
            }
        }
        poll()
        wait(for: [gone], timeout: 5)
    }
}
