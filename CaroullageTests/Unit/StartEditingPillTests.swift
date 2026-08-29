//
//  StartEditingPillTests.swift
//  CaroullageTests
//
//  Step 06 device QA — the "+ Start Editing" pill came back from a tap as a
//  rounded rectangle instead of a capsule, and stayed that way.
//
//  The press animation leaves a 0.92 scale on the button. `viewDidLayoutSubviews`
//  then assigns `plusButton.frame`, and UIKit answers a frame assignment on a
//  transformed view by solving for the bounds that would produce it — inflating
//  bounds to ~50pt tall while the corner radius stays 23. Half of 50 is not 23,
//  so the ends stop being semicircles.
//
//  The invariant is simply: radius is always half the height, whatever else has
//  happened to the button.
//

import UIKit
import XCTest
@testable import Caroullage

@MainActor
final class StartEditingPillTests: XCTestCase {

    private func makeShell() -> AppTabBarController {
        let tabs = AppTabBarController()
        tabs.setTabs([
            (UIViewController(), TabDescriptor(title: "One", symbol: "house", identifier: "one")),
            (UIViewController(), TabDescriptor(title: "Two", symbol: "star", identifier: "two")),
        ])
        tabs.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        tabs.view.layoutIfNeeded()
        return tabs
    }

    private func pill(in view: UIView) -> UIView? {
        if view.accessibilityIdentifier == "startEditingButton" { return view }
        for subview in view.subviews {
            if let found = pill(in: subview) { return found }
        }
        return nil
    }

    private func assertIsCapsule(
        _ button: UIView, _ message: String, line: UInt = #line
    ) {
        XCTAssertEqual(
            button.layer.cornerRadius * 2, button.bounds.height, accuracy: 0.5,
            message, line: line)
    }

    func testThePillIsACapsuleWhenFirstLaidOut() throws {
        let tabs = makeShell()
        let button = try XCTUnwrap(pill(in: tabs.view))
        assertIsCapsule(button, "The resting pill is a capsule")
    }

    func testThePillIsStillACapsuleAfterALayoutPassDuringAPress() throws {
        let tabs = makeShell()
        let button = try XCTUnwrap(pill(in: tabs.view))

        // Exactly what `plusPressed` leaves on the button while a finger is down.
        button.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        tabs.view.setNeedsLayout()
        tabs.view.layoutIfNeeded()

        assertIsCapsule(button, "A layout pass mid-press must not inflate the bounds")
    }

    func testThePillSurvivesRepeatedPresses() throws {
        // The inflation compounds: each frame assignment divides by the scale
        // again, so a few taps turn the capsule into a plain rounded rectangle.
        let tabs = makeShell()
        let button = try XCTUnwrap(pill(in: tabs.view))

        for _ in 0..<5 {
            button.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
            tabs.view.setNeedsLayout()
            tabs.view.layoutIfNeeded()
            button.transform = .identity
            tabs.view.setNeedsLayout()
            tabs.view.layoutIfNeeded()
        }

        assertIsCapsule(button, "Five presses later it is still a capsule")
        XCTAssertEqual(button.bounds.height, 46, accuracy: 0.5,
                       "…and still the height it was laid out at")
    }
}
