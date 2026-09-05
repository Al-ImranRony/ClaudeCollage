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

    // MARK: - Contextual groups

    func testSelectingACellInsertsThePhotoToolsAheadOfTheDocumentTools() throws {
        let editor = makeEditor()
        editor.selectCellForTesting(0)

        XCTAssertEqual(
            try rail(in: editor).visibleToolIdentifiers,
            ["replacePhotoTool", "adjustPhotoTool", "liftSubjectAction", "magicEraserAction",
             "clearCellTool",
             "layoutTool", "frameTool", "backgroundTool", "addTextButton", "addStickerButton"],
            "Document tools must survive a selection — they scroll, they do not vanish")
    }

    func testDeselectingRestoresTheBaseRail() throws {
        let editor = makeEditor()
        editor.selectCellForTesting(0)
        editor.selectCellForTesting(nil)

        XCTAssertEqual(
            try rail(in: editor).visibleToolIdentifiers,
            ["layoutTool", "frameTool", "backgroundTool", "addTextButton", "addStickerButton"])
    }

    func testDismissingTheChipDeselectsTheCell() throws {
        let editor = makeEditor()
        editor.selectCellForTesting(0)
        try rail(in: editor).simulateChipDismiss()

        XCTAssertNil(editor.selectedCellIndexForTesting)
    }

    func testSelectingATextOverlayInsertsTheTextTools() throws {
        let editor = makeEditor()
        let id = editor.addTextOverlayForTesting()
        editor.selectTextOverlayForTesting(id)

        let identifiers = try rail(in: editor).visibleToolIdentifiers
        XCTAssertEqual(Array(identifiers.prefix(4)),
                       ["editTextTool", "styleTextTool", "duplicateTextTool", "deleteTextTool"])
    }

    func testDeletingATextOverlayRemovesItAndClearsTheSelection() throws {
        let editor = makeEditor()
        let id = editor.addTextOverlayForTesting()
        editor.selectTextOverlayForTesting(id)
        try rail(in: editor).simulateTap(toolID: "deleteText")

        XCTAssertNil(editor.viewModelForTesting.textOverlay(id: id))
        XCTAssertEqual(
            try rail(in: editor).visibleToolIdentifiers,
            ["layoutTool", "frameTool", "backgroundTool", "addTextButton", "addStickerButton"])
    }

    func testDeletingATextOverlayIsUndoable() throws {
        // It rides `commit`, so it must land on the undo stack like every other edit.
        let editor = makeEditor()
        let id = editor.addTextOverlayForTesting()
        editor.selectTextOverlayForTesting(id)
        try rail(in: editor).simulateTap(toolID: "deleteText")
        editor.viewModelForTesting.undo()

        XCTAssertNotNil(editor.viewModelForTesting.textOverlay(id: id))
    }

    func testTheTextStylePanelOffersEveryPreset() throws {
        let editor = makeEditor()
        let id = editor.addTextOverlayForTesting()
        editor.selectTextOverlayForTesting(id)
        try rail(in: editor).simulateTap(toolID: "styleText")

        let buttons = try panel(in: editor).recursiveSubviews
            .compactMap { $0 as? UIControl }
            .filter { ($0.accessibilityIdentifier ?? "").hasPrefix("textStyle_") }
        XCTAssertEqual(buttons.count, TextStyle.Kind.allCases.count)
    }

    // MARK: - State coherence (rail highlight / panel / openToolID must agree)

    func testClosingThePanelClearsTheRailsActiveTool() throws {
        // Nothing asserted `toolRail`'s own active-tool bookkeeping before — a
        // regression that forgot `setActiveTool(nil)` in `closePanel()` would
        // pass every existing test (they only checked `isPresenting`).
        let editor = makeEditor()
        let rail = try rail(in: editor)
        rail.simulateTap(toolID: "layout")
        rail.simulateTap(toolID: "layout")   // same tool again → closePanel()

        XCTAssertNil(rail.activeToolID)
    }

    func testTheCloseButtonClosesThePanelAndClearsTheRailHighlight() throws {
        // `EditorPanel.simulateClose()` exists as a test seam but nothing fired
        // it — this drives the close (✕) button's real callback path rather
        // than the rail's own toggle-the-same-tool path.
        let editor = makeEditor()
        let rail = try rail(in: editor)
        rail.simulateTap(toolID: "frame")
        let panel = try panel(in: editor)
        panel.simulateClose()

        XCTAssertFalse(panel.isPresenting)
        XCTAssertNil(rail.activeToolID)
    }

    // MARK: - Stale selection revalidation

    func testShrinkingTheLayoutClearsAStaleCellSelection() throws {
        // fourSquare (4 cells) → select the last cell → shrink to 2 cells via the
        // view model (undo/redo/a layout swap all funnel through the same
        // `viewModel.onChange` choke point) — the rail must not keep offering
        // Photo tools for a cell that no longer exists.
        let editor = makeEditor()
        editor.selectCellForTesting(3)
        XCTAssertEqual(try rail(in: editor).visibleToolIdentifiers.first, "replacePhotoTool",
                       "Precondition: cell 3 is selected")

        editor.viewModelForTesting.setLayout(.grid(.twoUpHorizontal))

        XCTAssertNil(editor.selectedCellIndexForTesting)
        XCTAssertEqual(
            try rail(in: editor).visibleToolIdentifiers,
            ["layoutTool", "frameTool", "backgroundTool", "addTextButton", "addStickerButton"])
    }

    func testRemovingTheSelectedTextOverlayReturnsTheRailToTheBaseTools() throws {
        let editor = makeEditor()
        let id = editor.addTextOverlayForTesting()
        editor.selectTextOverlayForTesting(id)
        XCTAssertEqual(try rail(in: editor).visibleToolIdentifiers.first, "editTextTool",
                       "Precondition: the text overlay is selected")

        editor.viewModelForTesting.removeTextOverlay(id: id)

        XCTAssertNil(editor.selectedTextIDForTesting)
        XCTAssertEqual(
            try rail(in: editor).visibleToolIdentifiers,
            ["layoutTool", "frameTool", "backgroundTool", "addTextButton", "addStickerButton"])
    }

    func testRevalidationLeavesAnOpenBasePanelAloneWhenTheCellSelectionGoesStale() throws {
        // A selected cell can legitimately coexist with an open BASE panel (the
        // rail's own doc comment: document tools must survive a selection).
        // Revalidation must retire only the stale Photo context, never a Frame
        // panel that happens to be open alongside it.
        let editor = makeEditor()
        editor.selectCellForTesting(3)
        try rail(in: editor).simulateTap(toolID: "frame")
        let panel = try panel(in: editor)
        XCTAssertTrue(panel.isPresenting, "Precondition: Frame panel open alongside the selection")

        editor.viewModelForTesting.setLayout(.grid(.twoUpHorizontal))

        XCTAssertNil(editor.selectedCellIndexForTesting)
        XCTAssertTrue(panel.isPresenting, "the Frame panel is unrelated to the stale selection")
        XCTAssertEqual(panel.currentTitle, "Frame")
    }

    // MARK: - Duplicate text stays on canvas

    func testDuplicatingATextZoneNearTheBottomRightStaysFullyOnCanvas() throws {
        // With no clamp, offsetting by (0.03, 0.03) from a zone already this
        // close to the edge walks the copy off the normalized [0, 1] canvas,
        // where it is invisible (the canvas clips) and untappable.
        let editor = makeEditor()
        let original = TextOverlay(text: "Corner",
                                   frame: CGRect(x: 0.9, y: 0.9, width: 0.08, height: 0.08))
        let id = editor.viewModelForTesting.addTextOverlay(original)
        editor.selectTextOverlayForTesting(id)

        try rail(in: editor).simulateTap(toolID: "duplicateText")

        let duplicate = try XCTUnwrap(
            editor.viewModelForTesting.textOverlays.first { $0.id != id })
        XCTAssertGreaterThanOrEqual(duplicate.frame.minX, 0)
        XCTAssertGreaterThanOrEqual(duplicate.frame.minY, 0)
        XCTAssertLessThanOrEqual(duplicate.frame.maxX, 1)
        XCTAssertLessThanOrEqual(duplicate.frame.maxY, 1)
        // The clamp moves the origin only — size is untouched.
        XCTAssertEqual(duplicate.frame.width, original.frame.width, accuracy: 0.0001)
        XCTAssertEqual(duplicate.frame.height, original.frame.height, accuracy: 0.0001)
    }

    // MARK: - On-canvas text selection indicator

    func testSelectingATextOverlayMarksItsCanvasViewSelected() throws {
        // The rail chip is not the only feedback that something is selected —
        // `TextOverlayView` must show the same persistent selection chrome
        // `StickerOverlayView` already does.
        let editor = makeEditor()
        let id = editor.addTextOverlayForTesting()
        editor.selectTextOverlayForTesting(id)

        let overlayView = try XCTUnwrap(
            editor.view.recursiveSubviews.compactMap { $0 as? TextOverlayView }
                .first { $0.overlayID == id })
        XCTAssertTrue(overlayView.isSelected)
    }

    func testTheBackgroundPanelHasNoGenerativeButtonWhenUnavailable() throws {
        // Image Playground never reports available in the simulator (see
        // AIService.ImagePlaygroundAvailability) and there is no injection seam
        // to force it `true` — so only the `false` path is reachable from a
        // unit test. That is still worth guarding: it exercises the same guard
        // `makeGenerativeBackgroundButton()` uses, and would catch a regression
        // that stopped checking the flag at all.
        let editor = makeEditor()
        XCTAssertFalse(editor.aiService.generativeBackgroundsAvailable,
                       "Precondition: the simulator never reports Image Playground available")
        try rail(in: editor).simulateTap(toolID: "background")

        let button = try panel(in: editor).recursiveSubviews
            .first { $0.accessibilityIdentifier == "generateBackgroundButton" }
        XCTAssertNil(button)
    }
}

extension UIView {
    /// Every descendant, depth first. Test-only convenience.
    var recursiveSubviews: [UIView] {
        subviews + subviews.flatMap(\.recursiveSubviews)
    }
}
