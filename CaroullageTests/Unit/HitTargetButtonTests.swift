//
//  HitTargetButtonTests.swift
//  CaroullageTests
//
//  Step 06 phase 6.5. A glyph can be 28pt; the thing a finger hits must be 44.
//  These pin the two halves of that promise: touches land in the grown region,
//  and the accessibility frame — what Xcode's hit-region audit measures —
//  reports the grown size, not the drawn one.
//

import UIKit
import XCTest
@testable import Caroullage

@MainActor
final class HitTargetButtonTests: XCTestCase {

    func testTheMinimumHitTargetIsApplesFortyFour() {
        XCTAssertEqual(Theme.Layout.minimumHitTarget, 44)
    }

    func testASmallButtonAcceptsTouchesOutToFortyFourPoints() {
        let button = HitTargetButton(frame: CGRect(x: 0, y: 0, width: 28, height: 28))
        // 8pt outside each edge is inside the 44pt region centred on the button.
        XCTAssertTrue(button.point(inside: CGPoint(x: -7, y: -7), with: nil))
        XCTAssertTrue(button.point(inside: CGPoint(x: 35, y: 35), with: nil))
        XCTAssertFalse(button.point(inside: CGPoint(x: -9, y: 14), with: nil),
                       "the region is 44pt, not unbounded")
    }

    func testALargeButtonIsNotGrown() {
        let button = HitTargetButton(frame: CGRect(x: 0, y: 0, width: 60, height: 50))
        XCTAssertEqual(button.minimumHitTargetBounds, button.bounds)
        XCTAssertFalse(button.point(inside: CGPoint(x: -1, y: 25), with: nil))
    }

    func testTheAccessibilityFrameReportsTheGrownSize() {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let button = HitTargetButton(frame: CGRect(x: 100, y: 100, width: 28, height: 28))
        host.addSubview(button)
        XCTAssertEqual(button.accessibilityFrame.size, CGSize(width: 44, height: 44))
    }

    func testABareControlGetsTheSameTreatment() {
        let control = HitTargetControl(frame: CGRect(x: 0, y: 0, width: 32, height: 24))
        XCTAssertTrue(control.point(inside: CGPoint(x: -5, y: -9), with: nil))
        XCTAssertEqual(control.accessibilityFrame.size, CGSize(width: 44, height: 44))
    }
}
