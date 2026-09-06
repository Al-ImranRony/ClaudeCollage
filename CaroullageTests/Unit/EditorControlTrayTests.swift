//
//  EditorControlTrayTests.swift
//  CaroullageTests
//
//  Originally a Step 06 guard: the editor's control tray was pinned to the safe
//  area, leaving a ~34pt dead band under the last row of controls.
//
//  The 2026-09-05 editor redesign replaced the full-height scrolling tray with an
//  `EditorToolRail`, so the original assertions — which reached for "the first
//  UIScrollView child of the root view" — no longer describe the screen. The INTENT
//  survives unchanged and is what these tests now pin: the rail's background reaches
//  the physical bottom edge, its controls stay inside the safe area, and the canvas
//  takes the document's aspect ratio rather than a hardcoded square.
//

import UIKit
import XCTest
@testable import Caroullage

@MainActor
final class EditorControlTrayTests: XCTestCase {

    /// Windows are held for the length of the test: `additionalSafeAreaInsets` only
    /// reaches `view.safeAreaInsets` once the view is in a window, and without that
    /// the assertions below pass against any layout at all.
    private var windows: [UIWindow] = []

    override func tearDown() async throws {
        await MainActor.run { windows.removeAll() }
        try await super.tearDown()
    }

    private func makeEditor(
        bottomInset: CGFloat,
        canvasSize: CGSize = CGSize(width: 1080, height: 1080)
    ) -> GridEditorViewController {
        let editor = GridEditorViewController(
            viewModel: GridEditorViewModel(canvasSize: canvasSize))
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

    private func rail(in editor: GridEditorViewController) -> EditorToolRail? {
        editor.view.subviews.compactMap { $0 as? EditorToolRail }.first
    }

    func testTheHarnessActuallyAppliesTheInset() {
        // Guards every test below: if the fake home indicator does not reach the
        // view, the assertions are vacuous and pass against any layout.
        let editor = makeEditor(bottomInset: 34)
        XCTAssertEqual(editor.view.safeAreaInsets.bottom, 34, accuracy: 0.5)
    }

    func testTheRailBackgroundReachesTheBottomEdge() throws {
        let editor = makeEditor(bottomInset: 34)
        let rail = try XCTUnwrap(rail(in: editor))

        XCTAssertEqual(
            rail.frame.maxY, editor.view.bounds.maxY, accuracy: 0.5,
            "The rail runs to the screen edge rather than stopping above it")
    }

    func testTheRailStillFillsTheScreenWithoutAHomeIndicator() throws {
        let editor = makeEditor(bottomInset: 0)
        let rail = try XCTUnwrap(rail(in: editor))

        XCTAssertEqual(rail.frame.maxY, editor.view.bounds.maxY, accuracy: 0.5)
    }

    func testTheRailsControlsStayInsideTheSafeArea() throws {
        // The background reaching the edge must not drag the buttons under the
        // home indicator with it.
        let editor = makeEditor(bottomInset: 34)
        let rail = try XCTUnwrap(rail(in: editor))
        let scroll = try XCTUnwrap(rail.subviews.compactMap { $0 as? UIScrollView }.first)

        XCTAssertLessThanOrEqual(
            scroll.convert(scroll.bounds, to: editor.view).maxY,
            editor.view.bounds.maxY - 34 + 0.5,
            "Rail controls must not sit under the home indicator")
    }

    // MARK: - The canvas aspect fix

    func testASquareDocumentGetsASquareCanvas() throws {
        let editor = makeEditor(bottomInset: 34, canvasSize: CGSize(width: 1080, height: 1080))
        let stage = try XCTUnwrap(editor.view.subviews.compactMap { $0 as? EditorStage }.first)
        let canvas = try XCTUnwrap(stage.subviews.first)

        XCTAssertEqual(canvas.bounds.width / canvas.bounds.height, 1, accuracy: 0.02)
    }

    func testAStoryDocumentIsNoLongerSquashedIntoASquare() throws {
        // The regression this redesign exists for. The canvas view was pinned
        // `height == width`, so a 9:16 collage drew at 208x370 inside a 370x370 box.
        let editor = makeEditor(bottomInset: 34, canvasSize: CGSize(width: 1080, height: 1920))
        let stage = try XCTUnwrap(editor.view.subviews.compactMap { $0 as? EditorStage }.first)
        let canvas = try XCTUnwrap(stage.subviews.first)

        XCTAssertEqual(canvas.bounds.width / canvas.bounds.height, 1080.0 / 1920.0,
                       accuracy: 0.02, "The canvas must take the document's aspect")
        XCTAssertGreaterThan(canvas.bounds.height, 420,
                             "A story canvas must be far taller than the old 370pt square")
    }
}
