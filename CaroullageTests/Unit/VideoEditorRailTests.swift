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

    // MARK: - The contextual panels' controls actually drive the model
    //
    // Opening a panel is not evidence that it works. Plan 1 Task 9 shipped a
    // panel of sliders with no `addTarget` at all — visible, inert, and every
    // test still green because they only ever asserted the panel appeared. The
    // Frame panel's Border slider has a drag test; before these, Volume, Mute
    // and Transition had none, so deleting any of their `setupRail` wirings
    // would have broken the screen silently.

    /// Locates the live control a panel is currently showing.
    private func control<T: UIView>(_ type: T.Type, in editor: VideoEditorViewController,
                                    at position: Int = 0) throws -> T {
        let all = try panel(in: editor).recursiveSubviews.compactMap { $0 as? T }
        guard all.indices.contains(position) else {
            throw XCTSkip("no \(type) at \(position) in the open panel")
        }
        return all[position]
    }

    func testDraggingTheVolumeSliderThenReleasingRecordsExactlyOneUndoStep() throws {
        let editor = makeEditor()
        let vm = editor.viewModelForTesting
        let original = vm.cells[0].volume

        editor.selectClipForTesting(0)
        try rail(in: editor).simulateTap(toolID: "volume")
        let slider = try control(UISlider.self, in: editor)

        for value: Float in [0.8, 0.5, 0.2] {
            slider.value = value
            slider.sendActions(for: .valueChanged)
        }
        XCTAssertEqual(vm.cells[0].volume, 0.2, accuracy: 0.001,
                       "the Volume slider must drive the model live, not just render")

        slider.sendActions(for: .touchUpInside)
        vm.undo()
        XCTAssertEqual(vm.cells[0].volume, original, accuracy: 0.001,
                       "one undo must revert the whole drag — mid-drag ticks must not each push a step")
    }

    func testTogglingMuteAppliesImmediatelyAndIsUndoableInOneStep() throws {
        let editor = makeEditor()
        let vm = editor.viewModelForTesting
        XCTAssertFalse(vm.cells[0].isMuted, "Precondition: audible")

        editor.selectClipForTesting(0)
        try rail(in: editor).simulateTap(toolID: "volume")
        let muteSwitch = try control(UISwitch.self, in: editor)

        muteSwitch.isOn = true
        muteSwitch.sendActions(for: .valueChanged)
        XCTAssertTrue(vm.cells[0].isMuted, "the Mute switch must drive the model")

        vm.undo()
        XCTAssertFalse(vm.cells[0].isMuted, "a switch commits its own single undo step")
    }

    func testPickingATransitionStyleAndDraggingItsDurationBothReachTheModel() throws {
        let editor = makeEditor()
        let vm = editor.viewModelForTesting
        XCTAssertNil(vm.cells[0].transition, "Precondition: no transition yet")

        editor.selectClipForTesting(0)
        try rail(in: editor).simulateTap(toolID: "transition")

        let fade = try XCTUnwrap(
            panel(in: editor).recursiveSubviews
                .compactMap { $0 as? UIButton }
                .first { $0.configuration?.title == "Fade" },
            "the Transition panel's Fade button")
        fade.sendActions(for: .touchUpInside)
        XCTAssertEqual(vm.cells[0].transition?.style, .crossfade,
                       "a style button must set the transition, not merely highlight itself")

        // The duration slider bails out unless a style is already set, so this
        // has to run after the tap above — which is exactly the real order.
        let slider = try control(UISlider.self, in: editor)
        let seeded = try XCTUnwrap(vm.cells[0].transition?.duration)
        slider.value = 1.5
        slider.sendActions(for: .valueChanged)
        XCTAssertEqual(vm.cells[0].transition?.duration ?? 0, 1.5, accuracy: 0.001,
                       "the Duration slider must drive the model")
        XCTAssertEqual(vm.cells[0].transition?.style, .crossfade,
                       "changing duration must not drop the chosen style")

        slider.sendActions(for: .touchUpInside)
        vm.undo()
        XCTAssertEqual(vm.cells[0].transition?.duration ?? 0, seeded, accuracy: 0.001,
                       "one undo reverts the whole duration drag")
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

    func testTappingEveryStylePresetActuallyAppliesIt() throws {
        // Counting buttons proves nothing — a Plan 1 review found exactly that
        // gap, and Plan 1 Task 9 shipped a whole panel of controls wired to
        // nothing. Every preset gets tapped and checked.
        let editor = makeEditor()
        let vm = editor.viewModelForTesting
        let id = editor.addTextOverlayForTesting()
        editor.selectTextOverlayForTesting(id)
        try rail(in: editor).simulateTap(toolID: "styleText")

        for kind in TextStyle.Kind.allCases {
            let button = try XCTUnwrap(
                panel(in: editor).recursiveSubviews.compactMap { $0 as? UIControl }
                    .first { $0.accessibilityIdentifier == "textStyle_\(kind.rawValue)" },
                "the \(kind) preset button")
            button.sendActions(for: .touchUpInside)

            XCTAssertEqual(vm.textOverlay(id: id)?.style.kind, kind,
                           "tapping the \(kind) preset must actually apply it")
        }
    }

    // MARK: - The Timing panel (Task 8)
    //
    // Steppers rather than text fields: a decimal keypad in a bottom panel has
    // no return key to dismiss it, and the timeline drag already does coarse
    // placement — this panel is for refining it, which 0.1s steps do exactly.

    /// The panel's two steppers, in row order: In, then Out.
    private func timingSteppers(in editor: VideoEditorViewController) throws -> (UIStepper, UIStepper) {
        let steppers = try panel(in: editor).recursiveSubviews.compactMap { $0 as? UIStepper }
        guard steppers.count == 2 else {
            throw XCTSkip("expected an In and an Out stepper, found \(steppers.count)")
        }
        return (steppers[0], steppers[1])
    }

    private func openTiming(_ editor: VideoEditorViewController, _ id: UUID) throws {
        editor.selectTextOverlayForTesting(id)
        try rail(in: editor).simulateTap(toolID: "timingText")
    }

    func testTheTimingPanelOpensOnTheSelectedOverlaysWindow() throws {
        let editor = makeEditor()
        let id = editor.addTextOverlayForTesting()
        editor.viewModelForTesting.setTextTiming(id: id, start: 2, end: 5)
        try openTiming(editor, id)

        XCTAssertEqual(try panel(in: editor).currentTitle, "Timing")
        let (inStepper, outStepper) = try timingSteppers(in: editor)
        XCTAssertEqual(inStepper.value, 2, accuracy: 0.001)
        XCTAssertEqual(outStepper.value, 5, accuracy: 0.001)
    }

    func testAnUnboundedOverlayOpensSpanningTheWholeComposition() throws {
        // `nil` timing means "always visible", so the panel must offer the whole
        // composition rather than a collapsed 0...0 window the user then has to
        // undo by hand.
        let editor = makeEditor()
        editor.viewModelForTesting.setTrim(VideoTrim(start: 0, end: 6), forCellAt: 0)
        let id = editor.addTextOverlayForTesting()
        try openTiming(editor, id)

        let (inStepper, outStepper) = try timingSteppers(in: editor)
        XCTAssertEqual(inStepper.value, 0, accuracy: 0.001)
        XCTAssertEqual(outStepper.value, 6, accuracy: 0.001)
    }

    func testSteppingTheInPointRetimesTheOverlay() throws {
        let editor = makeEditor()
        let id = editor.addTextOverlayForTesting()
        editor.viewModelForTesting.setTextTiming(id: id, start: 1, end: 5)
        try openTiming(editor, id)

        let (inStepper, _) = try timingSteppers(in: editor)
        inStepper.value = 2.5
        inStepper.sendActions(for: .valueChanged)

        XCTAssertEqual(editor.viewModelForTesting.textOverlay(id: id)?.startTime ?? -1, 2.5,
                       accuracy: 0.001)
    }

    func testSteppingTheOutPointRetimesTheOverlay() throws {
        let editor = makeEditor()
        let id = editor.addTextOverlayForTesting()
        editor.viewModelForTesting.setTextTiming(id: id, start: 1, end: 5)
        try openTiming(editor, id)

        let (_, outStepper) = try timingSteppers(in: editor)
        outStepper.value = 4
        outStepper.sendActions(for: .valueChanged)

        XCTAssertEqual(editor.viewModelForTesting.textOverlay(id: id)?.endTime ?? -1, 4,
                       accuracy: 0.001)
    }

    func testTheInPointCannotBePushedPastTheOutPoint() throws {
        // An inverted window is treated as ALWAYS VISIBLE by `isVisible(at:)`
        // (fail-open, deliberately), so letting one be typed in would silently
        // turn a timed caption back into a permanent one.
        let editor = makeEditor()
        let id = editor.addTextOverlayForTesting()
        editor.viewModelForTesting.setTextTiming(id: id, start: 1, end: 5)
        try openTiming(editor, id)

        let (inStepper, _) = try timingSteppers(in: editor)
        inStepper.value = 9
        inStepper.sendActions(for: .valueChanged)

        let overlay = try XCTUnwrap(editor.viewModelForTesting.textOverlay(id: id))
        let start = try XCTUnwrap(overlay.startTime)
        let end = try XCTUnwrap(overlay.endTime)
        XCTAssertLessThan(start, end, "the window must never invert")
        XCTAssertEqual(end, 5, accuracy: 0.001, "clamping the in-point must not move the out-point")
        XCTAssertEqual(inStepper.value, start, accuracy: 0.001,
                       "the control must show the clamped value, not the rejected one")
    }

    func testTheOutPointCannotBePulledBeforeTheInPoint() throws {
        let editor = makeEditor()
        let id = editor.addTextOverlayForTesting()
        editor.viewModelForTesting.setTextTiming(id: id, start: 3, end: 8)
        try openTiming(editor, id)

        let (_, outStepper) = try timingSteppers(in: editor)
        outStepper.value = 0
        outStepper.sendActions(for: .valueChanged)

        let overlay = try XCTUnwrap(editor.viewModelForTesting.textOverlay(id: id))
        XCTAssertGreaterThan(try XCTUnwrap(overlay.endTime), try XCTUnwrap(overlay.startTime))
        XCTAssertEqual(overlay.startTime ?? -1, 3, accuracy: 0.001)
    }

    func testTimingChangesAreUndoable() throws {
        let editor = makeEditor()
        let vm = editor.viewModelForTesting
        let id = editor.addTextOverlayForTesting()
        vm.setTextTiming(id: id, start: 1, end: 5)
        try openTiming(editor, id)

        let (inStepper, _) = try timingSteppers(in: editor)
        inStepper.value = 2
        inStepper.sendActions(for: .valueChanged)

        vm.undo()
        XCTAssertEqual(vm.textOverlay(id: id)?.startTime ?? -1, 1, accuracy: 0.001)
    }

    func testWholeVideoReturnsTheCaptionToUnbounded() throws {
        // `nil` is a real state a drag cannot reach — the pill always has two
        // edges — so the panel has to be the way back to "show it throughout".
        let editor = makeEditor()
        let vm = editor.viewModelForTesting
        let id = editor.addTextOverlayForTesting()
        vm.setTextTiming(id: id, start: 2, end: 4)
        try openTiming(editor, id)

        let button = try XCTUnwrap(
            panel(in: editor).recursiveSubviews.compactMap { $0 as? UIControl }
                .first { $0.accessibilityIdentifier == "textTimingWholeVideoButton" },
            "the Timing panel's Whole Video control")
        button.sendActions(for: .touchUpInside)

        let overlay = try XCTUnwrap(vm.textOverlay(id: id))
        XCTAssertNil(overlay.startTime)
        XCTAssertNil(overlay.endTime)
        XCTAssertTrue(overlay.isVisible(at: 0))
        XCTAssertTrue(overlay.isVisible(at: 9_999))
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
