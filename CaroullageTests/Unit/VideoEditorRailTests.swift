//
//  VideoEditorRailTests.swift
//  CaroullageTests
//
//  Task 6 — the video editor's tool rail: the five base tools, which panel each
//  opens, the "Clip selected" / "Text selected" contextual groups, and selection
//  revalidation when the document changes underneath a stale selection. Mirrors
//  GridEditorRailTests.swift's coverage of the same chrome.
//

import AVFoundation
import UIKit
import XCTest
@testable import Caroullage

@MainActor
final class VideoEditorRailTests: XCTestCase {

    private var windows: [UIWindow] = []

    override func tearDown() async throws {
        await MainActor.run { windows.removeAll() }
        try await super.tearDown()
    }

    private func makeAsset() -> AVAsset {
        AVURLAsset(url: URL(fileURLWithPath: "/tmp/video-editor-rail-\(UUID().uuidString).mov"))
    }

    /// A fresh editor. `filledCellIndex` pre-loads that slot with a (fake, never
    /// actually decoded) asset so a real tap-equivalent selection is possible —
    /// mirrors how the real screen only ever calls `selectClip` for a slot that
    /// already holds a video.
    private func makeEditor(
        layout: CollageLayout = .grid(.fourSquare),
        filledCellIndex: Int? = 0
    ) -> VideoEditorViewController {
        let viewModel = VideoEditorViewModel(canvasSize: CGSize(width: 1080, height: 1080), layout: layout)
        if let filledCellIndex {
            viewModel.setVideo(assetID: UUID(), asset: makeAsset(), forCellAt: filledCellIndex)
        }
        let editor = VideoEditorViewController(viewModel: viewModel)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = editor
        window.isHidden = false
        windows.append(window)
        window.layoutIfNeeded()
        return editor
    }

    private func rail(in editor: VideoEditorViewController) throws -> EditorToolRail {
        try XCTUnwrap(editor.view.subviews.compactMap { $0 as? EditorToolRail }.first)
    }

    private func panel(in editor: VideoEditorViewController) throws -> EditorPanel {
        try XCTUnwrap(editor.view.subviews.compactMap { $0 as? EditorPanel }.first)
    }

    // MARK: - Base rail

    func testTheBaseRailOffersTheFiveToolsInOrder() throws {
        let rail = try rail(in: makeEditor())

        XCTAssertEqual(rail.visibleToolIdentifiers,
                       ["videoLayoutButton", "videoFrameTool", "videoAddTextButton",
                        "videoAddStickerButton", "videoMusicButton"])
    }

    func testNoPanelIsOpenOnLaunch() throws {
        XCTAssertFalse(try panel(in: makeEditor()).isPresenting)
    }

    func testTappingFrameOpensTheFramePanelWithASlider() throws {
        let editor = makeEditor()
        try rail(in: editor).simulateTap(toolID: "frame")

        let panel = try panel(in: editor)
        XCTAssertTrue(panel.isPresenting)
        XCTAssertEqual(panel.currentTitle, "Frame")
        let sliders = panel.recursiveSubviews.compactMap { $0 as? UISlider }
        XCTAssertEqual(sliders.count, 1, "Border only — video cells have no corner-radius concept")
    }

    func testTappingTheSameToolTwiceClosesThePanel() throws {
        let editor = makeEditor()
        let rail = try rail(in: editor)
        rail.simulateTap(toolID: "frame")
        rail.simulateTap(toolID: "frame")

        XCTAssertFalse(try panel(in: editor).isPresenting)
    }

    // MARK: - Frame panel — Border slider undo (Fix 2)

    func testDraggingTheBorderSliderThenReleasingRecordsExactlyOneUndoStep() throws {
        // No pre-filled cell: `makeEditor()`'s default `setVideo` call would
        // itself push an undo step, muddying the "exactly one step" assertions.
        let editor = makeEditor(filledCellIndex: nil)
        let vm = editor.viewModelForTesting
        XCTAssertFalse(vm.canUndo, "Precondition: nothing to undo yet")

        try rail(in: editor).simulateTap(toolID: "frame")
        let slider = try XCTUnwrap(
            panel(in: editor).recursiveSubviews.compactMap { $0 as? UISlider }.first,
            "the Frame panel's Border slider")

        // Simulate a drag: several mid-gesture ticks, then release.
        for value: Float in [0.2, 0.5, 0.8, 1.0] {
            slider.value = value
            slider.sendActions(for: .valueChanged)
        }
        XCTAssertFalse(vm.canUndo, "mid-drag ticks must not each push an undo snapshot")
        let widthDuringDrag = vm.borderWidth
        XCTAssertGreaterThan(widthDuringDrag, 0, "the live value tracks the drag immediately")

        slider.sendActions(for: .touchUpInside)

        XCTAssertTrue(vm.canUndo, "releasing the slider must commit one undo step")
        XCTAssertEqual(vm.borderWidth, widthDuringDrag, accuracy: 0.001)

        vm.undo()
        XCTAssertEqual(vm.borderWidth, 0, accuracy: 0.001, "undo reverts the whole drag in one step")
        XCTAssertFalse(vm.canUndo, "exactly one step was recorded for the whole drag")
    }

    // MARK: - Clip contextual group

    func testSelectingAClipInsertsTheClipToolsAheadOfTheDocumentTools() throws {
        let editor = makeEditor()
        editor.selectClipForTesting(0)

        XCTAssertEqual(
            try rail(in: editor).visibleToolIdentifiers,
            ["swapClipTool", "trimClipTool", "volumeClipTool", "transitionClipTool", "clearClipTool",
             "videoLayoutButton", "videoFrameTool", "videoAddTextButton",
             "videoAddStickerButton", "videoMusicButton"],
            "Document tools must survive a selection — they scroll, they do not vanish")
    }

    func testDismissingTheChipClearsTheSelection() throws {
        let editor = makeEditor()
        editor.selectClipForTesting(0)
        try rail(in: editor).simulateChipDismiss()

        XCTAssertEqual(
            try rail(in: editor).visibleToolIdentifiers,
            ["videoLayoutButton", "videoFrameTool", "videoAddTextButton",
             "videoAddStickerButton", "videoMusicButton"])
    }

    func testTappingVolumeOpensTheVolumePanel() throws {
        let editor = makeEditor()
        editor.selectClipForTesting(0)
        try rail(in: editor).simulateTap(toolID: "volume")

        let panel = try panel(in: editor)
        XCTAssertTrue(panel.isPresenting)
        XCTAssertEqual(panel.currentTitle, "Volume")
    }

    func testTappingClearRemovesTheClipAndReturnsToTheBaseRail() throws {
        let editor = makeEditor()
        editor.selectClipForTesting(0)
        try rail(in: editor).simulateTap(toolID: "clear")

        XCTAssertNil(editor.viewModelForTesting.asset(forCellAt: 0))
        XCTAssertEqual(
            try rail(in: editor).visibleToolIdentifiers,
            ["videoLayoutButton", "videoFrameTool", "videoAddTextButton",
             "videoAddStickerButton", "videoMusicButton"])
    }

    // MARK: - Stale selection revalidation (the scenario this task calls out explicitly)

    func testClearingTheSelectedClipViaTheViewModelRevalidatesTheRail() throws {
        // Selecting a clip through the VC and then emptying it from UNDERNEATH —
        // straight on the view model, as an undo/redo or a different code path
        // would — must not leave the rail offering Clip tools for a slot that no
        // longer holds a video.
        let editor = makeEditor()
        editor.selectClipForTesting(0)
        XCTAssertEqual(try rail(in: editor).visibleToolIdentifiers.first, "swapClipTool",
                       "Precondition: clip 0 is selected")

        editor.viewModelForTesting.clearVideo(atCellIndex: 0)

        XCTAssertEqual(
            try rail(in: editor).visibleToolIdentifiers,
            ["videoLayoutButton", "videoFrameTool", "videoAddTextButton",
             "videoAddStickerButton", "videoMusicButton"])
    }

    func testClearingTheSelectedClipViaTheViewModelClearsTheModelsSelectionToo() throws {
        // The bug: `revalidateSelection` retired the rail's contextual group and
        // the panel, but never told the MODEL its selection had gone stale —
        // `viewModel.selectedIndex` was left dangling at the cleared index.
        let editor = makeEditor()
        editor.selectClipForTesting(0)
        XCTAssertEqual(editor.viewModelForTesting.selectedIndex, 0, "Precondition: clip 0 is selected")

        editor.viewModelForTesting.clearVideo(atCellIndex: 0)

        XCTAssertNil(editor.viewModelForTesting.selectedIndex,
                     "revalidateSelection must clear viewModel.selectedIndex, not just the rail chrome")
        XCTAssertEqual(
            try rail(in: editor).visibleToolIdentifiers,
            ["videoLayoutButton", "videoFrameTool", "videoAddTextButton",
             "videoAddStickerButton", "videoMusicButton"],
            "the rail returns to the base tools")
    }

    func testRefillingAClearedSlotDoesNotResurrectTheStaleSelectionOnTheCanvas() throws {
        // The stronger regression: with the dangling `selectedIndex`, refilling
        // the SAME slot makes `refreshCanvas`'s "in range and filled" check pass
        // again, drawing an accent selection border around a cell the rail has
        // no contextual group for at all — canvas and rail visibly disagree.
        let editor = makeEditor()
        editor.selectClipForTesting(0)

        editor.viewModelForTesting.clearVideo(atCellIndex: 0)
        editor.viewModelForTesting.setVideo(assetID: UUID(), asset: makeAsset(), forCellAt: 0)

        XCTAssertNil(editor.viewModelForTesting.selectedIndex,
                     "a refill must not resurrect a selection that was already invalidated")
        let cellView = try XCTUnwrap(
            editor.view.recursiveSubviews.first { $0.accessibilityIdentifier == "videoCell-0" },
            "the canvas's chrome view for slot 0")
        XCTAssertEqual(cellView.layer.borderWidth, 1,
                       "must render as unselected (3pt accent border means selected)")
        XCTAssertEqual(
            try rail(in: editor).visibleToolIdentifiers,
            ["videoLayoutButton", "videoFrameTool", "videoAddTextButton",
             "videoAddStickerButton", "videoMusicButton"],
            "the rail must show no contextual group, matching the canvas")
    }

    func testUndoingThePlacementOfASelectedClipRevalidatesTheRail() throws {
        let editor = makeEditor(filledCellIndex: nil)
        editor.viewModelForTesting.setVideo(assetID: UUID(), asset: makeAsset(), forCellAt: 0)
        editor.selectClipForTesting(0)
        XCTAssertEqual(try rail(in: editor).visibleToolIdentifiers.first, "swapClipTool",
                       "Precondition: clip 0 is selected")

        editor.viewModelForTesting.undo()

        // `apply(_:)` only nils `selectedIndex` when it's OUT of range, not when
        // undo merely empties the cell it points at — this is the ordinary Undo
        // button reaching the same dangling-selection bug as a direct
        // `clearVideo` call.
        XCTAssertNil(editor.viewModelForTesting.selectedIndex,
                     "undo emptied the selected cell; the model's selection must not survive it")
        XCTAssertEqual(
            try rail(in: editor).visibleToolIdentifiers,
            ["videoLayoutButton", "videoFrameTool", "videoAddTextButton",
             "videoAddStickerButton", "videoMusicButton"])
    }

    func testRevalidationLeavesAnOpenBasePanelAloneWhenTheClipSelectionGoesStale() throws {
        // A selected clip can legitimately coexist with an open BASE panel (the
        // rail's own contract: document tools must survive a selection).
        // Revalidation must retire only the stale Clip context, never a Frame
        // panel that happens to be open alongside it.
        let editor = makeEditor()
        editor.selectClipForTesting(0)
        try rail(in: editor).simulateTap(toolID: "frame")
        let panel = try panel(in: editor)
        XCTAssertTrue(panel.isPresenting, "Precondition: Frame panel open alongside the selection")

        editor.viewModelForTesting.clearVideo(atCellIndex: 0)

        XCTAssertTrue(panel.isPresenting, "the Frame panel is unrelated to the stale selection")
        XCTAssertEqual(panel.currentTitle, "Frame")
    }

    func testRevalidationClosesASelectionPanelWhenTheClipItBelongsToGoesStale() throws {
        let editor = makeEditor()
        editor.selectClipForTesting(0)
        try rail(in: editor).simulateTap(toolID: "volume")
        XCTAssertTrue(try panel(in: editor).isPresenting, "Precondition: Volume panel open")

        editor.viewModelForTesting.clearVideo(atCellIndex: 0)

        XCTAssertFalse(try panel(in: editor).isPresenting,
                       "The Volume panel belongs to the selection that just went stale")
    }

    // MARK: - Text contextual group

    func testSelectingATextOverlayInsertsTheTextTools() throws {
        let editor = makeEditor()
        let id = editor.addTextOverlayForTesting()
        editor.selectTextOverlayForTesting(id)

        XCTAssertEqual(
            Array(try rail(in: editor).visibleToolIdentifiers.prefix(4)),
            ["editTextTool", "styleTextTool", "timingTextTool", "deleteTextTool"])
    }

    func testDeletingATextOverlayRemovesItAndClearsTheSelection() throws {
        let editor = makeEditor()
        let id = editor.addTextOverlayForTesting()
        editor.selectTextOverlayForTesting(id)
        try rail(in: editor).simulateTap(toolID: "deleteText")

        XCTAssertNil(editor.viewModelForTesting.textOverlay(id: id))
        XCTAssertEqual(
            try rail(in: editor).visibleToolIdentifiers,
            ["videoLayoutButton", "videoFrameTool", "videoAddTextButton",
             "videoAddStickerButton", "videoMusicButton"])
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
            ["videoLayoutButton", "videoFrameTool", "videoAddTextButton",
             "videoAddStickerButton", "videoMusicButton"])
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

    func testTheTimingToolOpensAPanelWithoutTouchingTheOverlay() throws {
        // Task 8 implements real numeric timing; here the tool must merely be
        // wired (a real panel opens with a real hit target) rather than inert —
        // and it must not silently mutate startTime/endTime.
        let editor = makeEditor()
        let id = editor.addTextOverlayForTesting()
        editor.selectTextOverlayForTesting(id)
        try rail(in: editor).simulateTap(toolID: "timingText")

        let panel = try panel(in: editor)
        XCTAssertTrue(panel.isPresenting)
        XCTAssertEqual(panel.currentTitle, "Timing")
        let overlay = try XCTUnwrap(editor.viewModelForTesting.textOverlay(id: id))
        XCTAssertNil(overlay.startTime)
        XCTAssertNil(overlay.endTime)

        let stubLabel = panel.recursiveSubviews.first { $0.accessibilityIdentifier == "textTimingStubLabel" }
        XCTAssertNotNil(stubLabel, "The tool must produce real, hit-testable content, not a dead button")
    }

    func testSelectingATextOverlayMarksItsCanvasViewSelected() throws {
        // The rail chip is not the only feedback that something is selected —
        // `TextOverlayView` shows the same persistent selection chrome
        // `StickerOverlayView` already does (mirrors the grid editor).
        let editor = makeEditor()
        let id = editor.addTextOverlayForTesting()
        editor.selectTextOverlayForTesting(id)

        let overlayView = try XCTUnwrap(
            editor.view.recursiveSubviews.compactMap { $0 as? TextOverlayView }
                .first { $0.overlayID == id })
        XCTAssertTrue(overlayView.isSelected)
    }

    // MARK: - State coherence (rail highlight / panel / openToolID must agree)

    func testClosingThePanelClearsTheRailsActiveTool() throws {
        let editor = makeEditor()
        let rail = try rail(in: editor)
        rail.simulateTap(toolID: "frame")
        rail.simulateTap(toolID: "frame")   // same tool again → closePanel()

        XCTAssertNil(rail.activeToolID)
    }

    func testTheCloseButtonClosesThePanelAndClearsTheRailHighlight() throws {
        let editor = makeEditor()
        let rail = try rail(in: editor)
        rail.simulateTap(toolID: "frame")
        let panel = try panel(in: editor)
        panel.simulateClose()

        XCTAssertFalse(panel.isPresenting)
        XCTAssertNil(rail.activeToolID)
    }

    func testSwitchingFromAClipToATextSelectionSwapsTheContextCleanly() throws {
        // Selecting a different kind of thing while a Clip panel is open must
        // not leave a mismatched panel/tool-id behind.
        let editor = makeEditor()
        editor.selectClipForTesting(0)
        try rail(in: editor).simulateTap(toolID: "volume")

        let id = editor.addTextOverlayForTesting()
        editor.selectTextOverlayForTesting(id)

        let rail = try rail(in: editor)
        XCTAssertFalse(try panel(in: editor).isPresenting, "The stale Clip panel must not survive")
        XCTAssertNil(rail.activeToolID)
        XCTAssertEqual(Array(rail.visibleToolIdentifiers.prefix(4)),
                       ["editTextTool", "styleTextTool", "timingTextTool", "deleteTextTool"])
    }
}
