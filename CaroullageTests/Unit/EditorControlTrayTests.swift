//
//  EditorControlTrayTests.swift
//  CaroullageTests
//
//  Step 06 device QA — the collage editor left a dead band along the bottom of
//  the screen.
//
//  The control tray was pinned to `view.safeAreaLayoutGuide.bottomAnchor`, which
//  stops it ~34pt short of the screen edge on a home-indicator phone. Nothing is
//  drawn in that strip and nothing can scroll into it: with the tab bar hidden by
//  `hidesBottomBarWhenPushed`, it is simply empty background under the last row
//  of controls.
//
//  Pinning to the real bottom is only half the fix — a scroll view that reaches
//  the edge will, by default, put the same inset straight back as an adjusted
//  content inset. Both halves are pinned here.
//

import UIKit
import XCTest
@testable import Caroullage

@MainActor
final class EditorControlTrayTests: XCTestCase {

    /// The editor's control tray: the vertical scroll view that is a direct child
    /// of the root view. (The layout picker is also a scroll view, but it lives
    /// further down inside the stack.)
    private func tray(in view: UIView) -> UIScrollView? {
        view.subviews.compactMap { $0 as? UIScrollView }.first
    }

    /// Windows are held for the length of the test: `additionalSafeAreaInsets`
    /// only reaches `view.safeAreaInsets` once the view is in a window, and
    /// without that the assertions below pass against any layout at all.
    private var windows: [UIWindow] = []

    override func tearDown() async throws {
        await MainActor.run { windows.removeAll() }
        try await super.tearDown()
    }

    private func makeEditor(bottomInset: CGFloat) -> GridEditorViewController {
        let editor = GridEditorViewController(viewModel: GridEditorViewModel())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = editor
        window.isHidden = false
        windows.append(window)
        // Stands in for the home indicator, which an off-device window lacks.
        editor.additionalSafeAreaInsets = UIEdgeInsets(
            top: 0, left: 0, bottom: bottomInset, right: 0)
        window.layoutIfNeeded()
        return editor
    }

    func testTheHarnessActuallyAppliesTheInset() {
        // Guards the tests below: if the fake home indicator does not reach the
        // view, every assertion here is vacuous and passes against any layout.
        let editor = makeEditor(bottomInset: 34)
        XCTAssertEqual(editor.view.safeAreaInsets.bottom, 34, accuracy: 0.5)
    }

    func testTheControlTrayReachesTheBottomEdge() throws {
        let editor = makeEditor(bottomInset: 34)
        let tray = try XCTUnwrap(tray(in: editor.view))

        XCTAssertEqual(
            tray.frame.maxY, editor.view.bounds.maxY, accuracy: 0.5,
            "The tray runs to the screen edge rather than stopping above it")
    }

    func testTheTrayDoesNotPutTheBandBackAsAContentInset() throws {
        let editor = makeEditor(bottomInset: 34)
        let tray = try XCTUnwrap(tray(in: editor.view))

        XCTAssertEqual(
            tray.adjustedContentInset.bottom, 0, accuracy: 0.5,
            "Reaching the edge is undone if the safe area returns as a content inset")
    }

    func testTheTrayStillFillsTheScreenWithoutAHomeIndicator() throws {
        // An older phone has no bottom inset; the tray must not depend on one.
        let editor = makeEditor(bottomInset: 0)
        let tray = try XCTUnwrap(tray(in: editor.view))

        XCTAssertEqual(tray.frame.maxY, editor.view.bounds.maxY, accuracy: 0.5)
    }
}
