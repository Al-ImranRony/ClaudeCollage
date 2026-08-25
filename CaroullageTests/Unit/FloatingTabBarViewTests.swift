//
//  FloatingTabBarViewTests.swift
//  CaroullageTests
//
//  Step 06 UI pass — the shell's own tab bar.
//
//  The system bar cannot be a floating pill with a selection capsule, so the
//  shell draws its own. That means the selection behaviour UIKit used to give us
//  is now ours to get right, and these are the parts of it that are not visual.
//

import XCTest
@testable import Caroullage

@MainActor
final class FloatingTabBarViewTests: XCTestCase {

    private func makeBar() -> FloatingTabBarView {
        let bar = FloatingTabBarView()
        bar.setItems([
            .init(title: "Home", symbol: "house.fill", identifier: "homeTab"),
            .init(title: "Templates", symbol: "rectangle.3.group.fill", identifier: "templatesButton"),
            .init(title: "Projects", symbol: "square.grid.2x2.fill", identifier: "projectsTab"),
            .init(title: "Carousel", symbol: "rectangle.stack.fill", identifier: "carouselButton"),
        ])
        bar.frame = CGRect(x: 0, y: 0, width: 390, height: 64)
        bar.layoutIfNeeded()
        return bar
    }

    func testTheFirstTabIsSelectedToBeginWith() {
        XCTAssertEqual(makeBar().selectedIndex, 0)
    }

    func testEveryItemGetsAButton() {
        XCTAssertEqual(makeBar().itemButtons.count, 4)
    }

    func testEachButtonKeepsItsIdentifierSoTheShellTestsStillFindIt() {
        let identifiers = makeBar().itemButtons.map(\.accessibilityIdentifier)

        XCTAssertEqual(identifiers, ["homeTab", "templatesButton", "projectsTab", "carouselButton"])
    }

    func testTappingAnItemReportsThatIndex() {
        let bar = makeBar()
        var selected: Int?
        bar.onSelect = { selected = $0 }

        bar.itemButtons[2].sendActions(for: .touchUpInside)

        XCTAssertEqual(selected, 2)
    }

    func testTappingAnItemMovesTheSelection() {
        let bar = makeBar()

        bar.itemButtons[3].sendActions(for: .touchUpInside)

        XCTAssertEqual(bar.selectedIndex, 3)
    }

    func testOnlyTheSelectedItemReadsAsSelectedToVoiceOver() {
        let bar = makeBar()

        bar.select(index: 1)

        XCTAssertTrue(bar.itemButtons[1].accessibilityTraits.contains(.selected))
        for index in [0, 2, 3] {
            XCTAssertFalse(bar.itemButtons[index].accessibilityTraits.contains(.selected),
                           "item \(index) must not claim to be selected")
        }
    }

    func testSelectingProgrammaticallyDoesNotReportBackAsATap() {
        let bar = makeBar()
        var reported = false
        bar.onSelect = { _ in reported = true }

        bar.select(index: 2)

        XCTAssertFalse(reported, "the controller drove this; telling it back would loop")
    }

    func testAnOutOfRangeSelectionIsIgnoredRatherThanCrashing() {
        let bar = makeBar()

        bar.select(index: 9)

        XCTAssertEqual(bar.selectedIndex, 0)
    }

    func testTheBarNamesItselfForTheShellTests() {
        XCTAssertEqual(makeBar().accessibilityIdentifier, "mainTabBar")
    }
}
