//
//  GridEditorRailTests.swift
//  CaroullageTests
//
//  The collage editor's tool rail: which tools it offers, which panel each opens,
//  and the one document type that must not be offered a layout choice at all.
//

import UIKit
import XCTest
@testable import Caroullage

@MainActor
final class GridEditorRailTests: XCTestCase {

    private var windows: [UIWindow] = []

    override func tearDown() async throws {
        await MainActor.run { windows.removeAll() }
        try await super.tearDown()
    }

    private func makeEditor(
        layout: CollageLayout = .grid(.fourSquare)
    ) -> GridEditorViewController {
        let viewModel = GridEditorViewModel(
            canvasSize: CGSize(width: 1080, height: 1080),
            state: GridEditorState(layout: layout))
        let editor = GridEditorViewController(viewModel: viewModel)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = editor
        window.isHidden = false
        windows.append(window)
        window.layoutIfNeeded()
        return editor
    }

    private func rail(in editor: GridEditorViewController) throws -> EditorToolRail {
        try XCTUnwrap(editor.view.subviews.compactMap { $0 as? EditorToolRail }.first)
    }

    private func panel(in editor: GridEditorViewController) throws -> EditorPanel {
        try XCTUnwrap(editor.view.subviews.compactMap { $0 as? EditorPanel }.first)
    }

    func testTheBaseRailOffersTheFiveDocumentTools() throws {
        let rail = try rail(in: makeEditor())

        XCTAssertEqual(rail.visibleToolIdentifiers,
                       ["layoutTool", "frameTool", "backgroundTool", "addTextButton", "addStickerButton"])
    }

    func testATemplateDocumentIsNotOfferedALayoutChoice() throws {
        // A template defines its own geometry; offering a layout picker would claim
        // a selection the document does not have.
        let template = TemplateLayout(
            templateID: "test.single",
            name: "Test",
            aspectRatio: "1:1",
            cells: [TemplateLayoutCell(frame: CGRect(x: 0, y: 0, width: 1, height: 1))])
        let rail = try rail(in: makeEditor(layout: .template(template)))

        XCTAssertFalse(rail.visibleToolIdentifiers.contains("layoutTool"))
    }

    func testNoPanelIsOpenOnLaunch() throws {
        // The canvas gets the whole stage until the user asks for a tool.
        XCTAssertFalse(try panel(in: makeEditor()).isPresenting)
    }

    func testTappingLayoutOpensTheLayoutPanel() throws {
        let editor = makeEditor()
        try rail(in: editor).simulateTap(toolID: "layout")

        let panel = try panel(in: editor)
        XCTAssertTrue(panel.isPresenting)
        XCTAssertEqual(panel.currentTitle, "Layout")
    }

    func testTappingFrameOpensTheFramePanelWithBothSliders() throws {
        let editor = makeEditor()
        try rail(in: editor).simulateTap(toolID: "frame")

        let panel = try panel(in: editor)
        XCTAssertEqual(panel.currentTitle, "Frame")
        let sliders = panel.recursiveSubviews.compactMap { $0 as? UISlider }
        XCTAssertEqual(sliders.count, 2, "Border and Corners")
    }

    func testTappingTheSameToolTwiceClosesThePanel() throws {
        // Toggling gives the canvas its full height back without hunting for the ✕.
        let editor = makeEditor()
        let rail = try rail(in: editor)
        rail.simulateTap(toolID: "layout")
        rail.simulateTap(toolID: "layout")

        XCTAssertFalse(try panel(in: editor).isPresenting)
    }

    func testSwitchingToolsSwapsThePanelWithoutClosingIt() throws {
        let editor = makeEditor()
        let rail = try rail(in: editor)
        rail.simulateTap(toolID: "layout")
        rail.simulateTap(toolID: "background")

        let panel = try panel(in: editor)
        XCTAssertTrue(panel.isPresenting)
        XCTAssertEqual(panel.currentTitle, "Background")
    }

    func testTheLayoutPickerLivesInsideTheLayoutPanel() throws {
        // PolygonQAUITests reaches for this collection view by identifier; it must
        // still exist, just scoped to the panel now.
        let editor = makeEditor()
        try rail(in: editor).simulateTap(toolID: "layout")

        let picker = try panel(in: editor).recursiveSubviews
            .first { $0.accessibilityIdentifier == "layoutPicker" }
        XCTAssertNotNil(picker)
    }
}

extension UIView {
    /// Every descendant, depth first. Test-only convenience.
    var recursiveSubviews: [UIView] {
        subviews + subviews.flatMap(\.recursiveSubviews)
    }
}
