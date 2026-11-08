//
//  ProBadgeButtonTests.swift
//  CaroullageTests
//
//  When a sheet comes up over Home, UIKit dims the tint of everything behind
//  it. The Pro button's sparkle and gradient are baked colours that ignore
//  that, while its title followed the dimming, so "Pro" faded to grey on its
//  own as Settings opened and read as a flicker. This pins the button
//  out of tint dimming, so the pill stays one piece under the sheet.
//

import UIKit
import XCTest
@testable import Caroullage

@MainActor
final class ProBadgeButtonTests: XCTestCase {

    func testThePillIgnoresTintDimmingBehindASheet() {
        let host = UIView()
        let button = ProBadgeButton(title: "Pro") {}
        host.addSubview(button)

        host.tintAdjustmentMode = .dimmed

        XCTAssertEqual(button.tintAdjustmentMode, .normal,
                       "A sheet's dimming must not reach the title alone")
    }
}
