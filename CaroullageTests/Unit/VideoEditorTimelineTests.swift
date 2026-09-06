//
//  VideoEditorTimelineTests.swift
//  CaroullageTests
//
//  Task 7 — the timeline stops being a static prop and starts driving the
//  document: lanes built from the real cells, trim and text-retime drags landing
//  as undoable edits, and scrubbing moving the player.
//
//  Two halves, deliberately split:
//
//  • `VideoTimelineModelBuilderTests` is pure — no window, no assets, no player.
//    Building the model is where the arithmetic lives (which cell is a lane, how
//    long it is, where a caption's pill sits when its window is open-ended), so
//    it is worth testing without a screen attached.
//  • `VideoEditorTimelineWiringTests` drives the REAL controller and asserts the
//    view model actually moved. The timeline's own gesture → callback path is
//    already covered by `VideoTimelineViewTests`; what is new here is whether
//    the controller has connected those callbacks to anything, which is exactly
//    the class of defect (a control wired to nothing) this plan keeps hitting.
//
//  Plan deviation, deliberate: the plan said append to `VideoTimelineTests.swift`.
//  That file is the timeline VIEW's own suite; these tests are about the
//  controller/view-model seam and belong beside `VideoEditorRailTests`.
//

import AVFoundation
import CoreGraphics
import UIKit
import XCTest
@testable import Caroullage

// MARK: - The pure model builder

final class VideoTimelineModelBuilderTests: XCTestCase {

    private func filled(trim: VideoTrim, isLooping: Bool = false) -> VideoCellState {
        VideoCellState(videoID: UUID(), trim: trim, isLooping: isLooping)
    }

    func testEveryCellBecomesALaneAndOnlyTheFilledOnesSaySo() {
        let model = VideoTimelineModelBuilder.make(
            cells: [filled(trim: VideoTrim(start: 0, end: 4)), VideoCellState(),
                    filled(trim: VideoTrim(start: 0, end: 6))],
            sourceDurations: [0: 10, 2: 10],
            textOverlays: [])

        XCTAssertEqual(model.clips.count, 3, "an empty slot is still a lane — it is a slot you can fill")
        XCTAssertEqual(model.clips.map(\.isFilled), [true, false, true])
        XCTAssertEqual(model.clips.map(\.index), [0, 1, 2])
    }

    func testALanesLengthIsItsTrimmedLengthNotTheSourcesLength() {
        // The lane's edges ARE the trim handles, so its length has to be what the
        // trim says or dragging an edge would jump.
        let model = VideoTimelineModelBuilder.make(
            cells: [filled(trim: VideoTrim(start: 2, end: 5))],
            sourceDurations: [0: 30],
            textOverlays: [])

        XCTAssertEqual(model.clips[0].duration, 3, accuracy: 0.001)
    }

    func testAnUnsetTrimTakesTheWholeSource() {
        // `VideoTrim(end: 0)` means "to the end", resolved only once the source's
        // real duration is known — the lane must show the resolved length, not 0.
        let model = VideoTimelineModelBuilder.make(
            cells: [filled(trim: VideoTrim())],
            sourceDurations: [0: 7.5],
            textOverlays: [])

        XCTAssertEqual(model.clips[0].duration, 7.5, accuracy: 0.001)
    }

    func testAnUnknownSourceDurationDoesNotInventALength() {
        // The duration load is async; before it lands the lane must not claim a
        // length it cannot know.
        let model = VideoTimelineModelBuilder.make(
            cells: [filled(trim: VideoTrim())],
            sourceDurations: [:],
            textOverlays: [])

        XCTAssertEqual(model.clips[0].duration, 0, accuracy: 0.001)
    }

    func testTheCompositionRunsAsLongAsItsLongestClip() {
        let model = VideoTimelineModelBuilder.make(
            cells: [filled(trim: VideoTrim(start: 0, end: 4)),
                    filled(trim: VideoTrim(start: 0, end: 9)),
                    VideoCellState()],
            sourceDurations: [0: 20, 1: 20],
            textOverlays: [])

        XCTAssertEqual(model.duration, 9, accuracy: 0.001)
    }

    func testEveryClipStartsAtZeroBecauseCellsPlayTogether() {
        // A video collage plays its cells simultaneously in separate regions —
        // it is not a sequential edit. `startOffset` (Task 9) is what would
        // change this, and it is not here yet.
        let model = VideoTimelineModelBuilder.make(
            cells: [filled(trim: VideoTrim(start: 0, end: 4)),
                    filled(trim: VideoTrim(start: 0, end: 9))],
            sourceDurations: [0: 20, 1: 20],
            textOverlays: [])

        XCTAssertEqual(model.clips.map(\.start), [0, 0])
    }

    func testATextPillSpansItsOwnWindow() {
        var overlay = TextOverlay(text: "Caption")
        overlay.startTime = 2
        overlay.endTime = 5

        let model = VideoTimelineModelBuilder.make(
            cells: [filled(trim: VideoTrim(start: 0, end: 10))],
            sourceDurations: [0: 10],
            textOverlays: [overlay])

        XCTAssertEqual(model.textPills.count, 1)
        XCTAssertEqual(model.textPills[0].start, 2, accuracy: 0.001)
        XCTAssertEqual(model.textPills[0].end, 5, accuracy: 0.001)
        XCTAssertEqual(model.textPills[0].label, "Caption")
    }

    func testAnOpenEndedTextPillSpansTheWholeComposition() {
        // `nil` timing means "always visible" (see `TextOverlay.isVisible`), which
        // on a timeline has to read as a pill covering everything — not a
        // zero-width pill stuck at the origin.
        let model = VideoTimelineModelBuilder.make(
            cells: [filled(trim: VideoTrim(start: 0, end: 10))],
            sourceDurations: [0: 10],
            textOverlays: [TextOverlay(text: "Always")])

        XCTAssertEqual(model.textPills[0].start, 0, accuracy: 0.001)
        XCTAssertEqual(model.textPills[0].end, 10, accuracy: 0.001,
                       "an unbounded caption covers the whole composition")
    }

    func testAHalfOpenTextPillOnlyDefaultsTheMissingEnd() {
        var overlay = TextOverlay(text: "Late")
        overlay.startTime = 6

        let model = VideoTimelineModelBuilder.make(
            cells: [filled(trim: VideoTrim(start: 0, end: 10))],
            sourceDurations: [0: 10],
            textOverlays: [overlay])

        XCTAssertEqual(model.textPills[0].start, 6, accuracy: 0.001)
        XCTAssertEqual(model.textPills[0].end, 10, accuracy: 0.001)
    }

    func testAnEmptyCaptionStillGetsAReadableLabel() {
        let model = VideoTimelineModelBuilder.make(
            cells: [filled(trim: VideoTrim(start: 0, end: 10))],
            sourceDurations: [0: 10],
            textOverlays: [TextOverlay(text: "")])

        XCTAssertFalse(model.textPills[0].label.isEmpty,
                       "a blank pill is unidentifiable on the timeline")
    }

    func testAnEmptyDocumentProducesAZeroDurationModelRatherThanNaN() {
        let model = VideoTimelineModelBuilder.make(
            cells: [VideoCellState(), VideoCellState()], sourceDurations: [:], textOverlays: [])

        XCTAssertEqual(model.duration, 0)
        XCTAssertEqual(model.clips.count, 2)
        XCTAssertTrue(model.textPills.isEmpty)
    }

    func testSelectionAndPlaybackArePassedThrough() {
        let id = UUID()
        var overlay = TextOverlay(text: "hi")
        overlay.startTime = 0
        let model = VideoTimelineModelBuilder.make(
            cells: [filled(trim: VideoTrim(start: 0, end: 4))],
            sourceDurations: [0: 4],
            textOverlays: [overlay],
            hasMusic: true,
            selectedClipIndex: 0,
            selectedTextID: id,
            isPlaying: true)

        XCTAssertEqual(model.selectedClipIndex, 0)
        XCTAssertEqual(model.selectedTextID, id)
        XCTAssertTrue(model.isPlaying)
        XCTAssertNotNil(model.musicTitle, "a music lane needs a title to render")
    }
}

// MARK: - The controller/view-model wiring

@MainActor
final class VideoEditorTimelineWiringTests: XCTestCase {

    private var windows: [UIWindow] = []

    override func tearDown() async throws {
        await MainActor.run { windows.removeAll() }
        try await super.tearDown()
    }

    private func makeEditor(filledCellIndex: Int? = 0) -> VideoEditorViewController {
        let viewModel = VideoEditorViewModel(
            canvasSize: CGSize(width: 1080, height: 1080), layout: .grid(.fourSquare))
        if let filledCellIndex {
            viewModel.setVideo(
                assetID: UUID(),
                asset: AVURLAsset(url: URL(fileURLWithPath: "/tmp/tl-\(UUID().uuidString).mov")),
                forCellAt: filledCellIndex)
            viewModel.setTrim(VideoTrim(start: 0, end: 8), forCellAt: filledCellIndex)
        }
        let editor = VideoEditorViewController(viewModel: viewModel)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = editor
        windows.append(window)
        window.isHidden = false
        window.layoutIfNeeded()
        return editor
    }

    private func timeline(in editor: VideoEditorViewController) throws -> VideoTimeline {
        try XCTUnwrap(editor.view.subviews.compactMap { $0 as? VideoTimeline }.first)
    }

    // MARK: - The model reaches the timeline

    func testTheTimelineIsGivenTheDocumentsClips() throws {
        let editor = makeEditor()
        let model = try timeline(in: editor).modelForTesting

        XCTAssertEqual(model.clips.count, 4, "one lane per cell of the four-up layout")
        XCTAssertEqual(model.clips.map(\.isFilled), [true, false, false, false])
    }

    func testEditingTheDocumentRefreshesTheTimeline() throws {
        let editor = makeEditor()
        editor.viewModelForTesting.setTrim(VideoTrim(start: 0, end: 3), forCellAt: 0)

        XCTAssertEqual(try timeline(in: editor).modelForTesting.clips[0].duration, 3, accuracy: 0.001,
                       "the timeline must not keep showing a length the document no longer has")
    }

    // MARK: - Trim drags

    func testDraggingALaneEndTrimsTheClip() throws {
        let editor = makeEditor()
        let tl = try timeline(in: editor)

        tl.onTrim?(0, 1, 5, .committed)

        XCTAssertEqual(editor.viewModelForTesting.cells[0].trim.start, 1, accuracy: 0.001)
        XCTAssertEqual(editor.viewModelForTesting.cells[0].trim.end, 5, accuracy: 0.001)
    }

    func testATrimDragIsOneUndoStepNotOnePerTick() throws {
        let editor = makeEditor()
        let vm = editor.viewModelForTesting
        let tl = try timeline(in: editor)
        let original = vm.cells[0].trim

        tl.onTrim?(0, 0, 7, .changed)
        tl.onTrim?(0, 0, 6, .changed)
        tl.onTrim?(0, 0, 5, .changed)
        XCTAssertEqual(vm.cells[0].trim.end, 5, accuracy: 0.001, "mid-drag ticks update live")
        tl.onTrim?(0, 0, 5, .committed)

        vm.undo()
        XCTAssertEqual(vm.cells[0].trim, original,
                       "one undo must revert the whole drag, not just its last tick")
    }

    func testATrimForAnOutOfRangeLaneIsIgnoredRatherThanCrashing() throws {
        let editor = makeEditor()
        try timeline(in: editor).onTrim?(99, 0, 2, .committed)
        XCTAssertEqual(editor.viewModelForTesting.cells[0].trim.end, 8, accuracy: 0.001)
    }

    // MARK: - Real gestures, not just the callbacks
    //
    // The tests above call `onTrim` / `onRetimeText` directly, which proves the
    // controller's handlers work but NOT that a real drag can reach them. These
    // drive the actual gesture through the timeline the controller owns. That
    // distinction is the whole ballgame here: `setModel` cancels an in-flight
    // drag (Task 5's defence against acting on stale indices), and the
    // controller's own refresh calls `setModel` — so the drag's first tick used
    // to kill the drag that produced it.

    private func expandedTimeline(in editor: VideoEditorViewController) throws -> VideoTimeline {
        let tl = try timeline(in: editor)
        tl.setState(.expanded, animated: false)
        editor.view.layoutIfNeeded()
        tl.layoutIfNeeded()
        return tl
    }

    func testARealTrimDragMovesTheTrimAndCommitsExactlyOneUndoStep() throws {
        let editor = makeEditor()
        let vm = editor.viewModelForTesting
        let tl = try expandedTimeline(in: editor)
        let originalEnd = vm.cells[0].trim.end

        let frame = try XCTUnwrap(tl.frameForClip(at: 0), "clip 0 must render a lane")
        let edge = CGPoint(x: frame.maxX - 1, y: frame.midY)
        tl.simulatePanBegan(at: edge)
        tl.simulatePanChanged(at: CGPoint(x: edge.x - 40, y: frame.midY))
        tl.simulatePanEnded(at: CGPoint(x: edge.x - 40, y: frame.midY))

        XCTAssertLessThan(vm.cells[0].trim.end, originalEnd,
                          "dragging the trailing edge left must actually shorten the clip — " +
                          "the drag must survive the model refresh it causes")
        let shortened = vm.cells[0].trim.end
        vm.undo()
        XCTAssertEqual(vm.cells[0].trim.end, originalEnd, accuracy: 0.001,
                       "the whole drag must be exactly one undo step")
        vm.redo()
        XCTAssertEqual(vm.cells[0].trim.end, shortened, accuracy: 0.001)
    }

    func testARealTextPillDragRetimesTheOverlay() throws {
        let editor = makeEditor()
        let vm = editor.viewModelForTesting
        let id = editor.addTextOverlayForTesting()
        vm.setTextTiming(id: id, start: 2, end: 6)
        let tl = try expandedTimeline(in: editor)

        let frame = try XCTUnwrap(tl.frameForTextPill(id: id), "the caption must render a pill")
        let edge = CGPoint(x: frame.minX + 1, y: frame.midY)
        tl.simulatePanBegan(at: edge)
        tl.simulatePanChanged(at: CGPoint(x: edge.x - 30, y: frame.midY))
        tl.simulatePanEnded(at: CGPoint(x: edge.x - 30, y: frame.midY))

        XCTAssertLessThan(vm.textOverlay(id: id)?.startTime ?? .infinity, 2,
                          "dragging the pill's leading edge earlier must reach the document")
    }

    func testAForeignDocumentChangeStillCancelsAnInFlightDrag() throws {
        // The other half of the contract: the drag must survive its OWN feedback
        // but must still be abandoned when the thing it points at disappears.
        let editor = makeEditor()
        let vm = editor.viewModelForTesting
        let tl = try expandedTimeline(in: editor)

        let frame = try XCTUnwrap(tl.frameForClip(at: 0))
        let edge = CGPoint(x: frame.maxX - 1, y: frame.midY)
        tl.simulatePanBegan(at: edge)

        // The clip the drag is holding is cleared out from under it.
        vm.clearVideo(atCellIndex: 0)
        let afterClear = vm.cells[0].trim

        tl.simulatePanChanged(at: CGPoint(x: edge.x - 40, y: frame.midY))
        tl.simulatePanEnded(at: CGPoint(x: edge.x - 40, y: frame.midY))

        XCTAssertEqual(vm.cells[0].trim, afterClear,
                       "a drag must not keep editing a clip the document no longer has")
    }

    // MARK: - Text retiming

    func testDraggingATextPillRetimesTheOverlay() throws {
        let editor = makeEditor()
        let vm = editor.viewModelForTesting
        let id = editor.addTextOverlayForTesting()

        try timeline(in: editor).onRetimeText?(id, 2, 6, .committed)

        XCTAssertEqual(vm.textOverlay(id: id)?.startTime ?? -1, 2, accuracy: 0.001)
        XCTAssertEqual(vm.textOverlay(id: id)?.endTime ?? -1, 6, accuracy: 0.001)
    }

    func testATextRetimeDragIsOneUndoStep() throws {
        let editor = makeEditor()
        let vm = editor.viewModelForTesting
        let id = editor.addTextOverlayForTesting()
        let tl = try timeline(in: editor)

        tl.onRetimeText?(id, 1, 9, .changed)
        tl.onRetimeText?(id, 2, 8, .changed)
        tl.onRetimeText?(id, 3, 7, .changed)
        XCTAssertEqual(vm.textOverlay(id: id)?.startTime ?? -1, 3, accuracy: 0.001)
        tl.onRetimeText?(id, 3, 7, .committed)

        vm.undo()
        XCTAssertNil(vm.textOverlay(id: id)?.startTime,
                     "one undo returns the caption to its original open-ended window")
    }

    func testRetimingAnOverlayThatIsGoneIsIgnored() throws {
        let editor = makeEditor()
        try timeline(in: editor).onRetimeText?(UUID(), 1, 2, .committed)
        XCTAssertTrue(editor.viewModelForTesting.textOverlays.isEmpty)
    }

    // MARK: - Scrubbing

    func testScrubbingMovesThePlayerAndTheCanvasTogether() throws {
        let editor = makeEditor()

        try timeline(in: editor).onScrub?(4)

        XCTAssertEqual(editor.canvasPreviewTimeForTesting, 4, accuracy: 0.001,
                       "the canvas must be told directly and synchronously — a seek while PAUSED " +
                       "is not guaranteed to reach the periodic time observer, so waiting for it " +
                       "would drop or lag the drag")
        XCTAssertEqual(editor.lastSeekedTimeForTesting ?? -1, 4, accuracy: 0.001)
    }

    func testScrubbingKeepsTheTimelinesOwnPlayheadInStep() throws {
        let editor = makeEditor()
        let tl = try timeline(in: editor)

        tl.onScrub?(3)

        XCTAssertEqual(tl.playheadTimeForTesting, 3, accuracy: 0.001)
    }

    func testThePlayheadAdvancesWithPlaybackNotJustWithScrubbing() throws {
        // The playhead is the timeline's primary feedback. Driving only the canvas
        // from the periodic observer left it — and the "0:00 / 0:08" readout —
        // frozen at the origin for the entire length of the video.
        let editor = makeEditor()
        let tl = try timeline(in: editor)

        editor.simulatePlaybackTickForTesting(2.5)

        XCTAssertEqual(tl.playheadTimeForTesting, 2.5, accuracy: 0.001,
                       "the timeline must follow playback, not only a drag")
        XCTAssertEqual(editor.canvasPreviewTimeForTesting, 2.5, accuracy: 0.001,
                       "and the canvas must still be driven too")
    }

    func testAPlaybackTickSurvivesAModelRefresh() throws {
        // `refreshTimeline` re-pushes the playhead it believes in; if playback
        // ticks did not update that belief, any document change would yank the
        // playhead back to where the last scrub left it.
        let editor = makeEditor()
        let tl = try timeline(in: editor)

        editor.simulatePlaybackTickForTesting(3)
        editor.viewModelForTesting.setLooping(true, forCellAt: 0)

        XCTAssertEqual(tl.playheadTimeForTesting, 3, accuracy: 0.001)
    }

    // MARK: - Selection from the timeline

    func testTappingALaneSelectsThatClipInTheEditor() throws {
        let editor = makeEditor()

        try timeline(in: editor).onSelectClip?(0)

        XCTAssertEqual(editor.viewModelForTesting.selectedIndex, 0)
        let rail = try XCTUnwrap(editor.view.subviews.compactMap { $0 as? EditorToolRail }.first)
        XCTAssertEqual(rail.visibleToolIdentifiers.first, "swapClipTool",
                       "selecting from the timeline must raise the same contextual group as the canvas")
    }

    func testTappingAnEmptyLaneRaisesNoClipToolsBecauseThereIsNothingToEdit() throws {
        // The canvas does not select an empty slot either — it offers to fill it
        // (`canvasTapped`). Selecting one here would raise Swap/Trim/Volume/
        // Transition against a slot that has none of them: every one of those
        // tools no-ops, which is the "visible, tappable, inert" trap this plan
        // keeps finding.
        let editor = makeEditor()   // cell 0 filled; 1...3 empty

        try timeline(in: editor).onSelectClip?(1)

        XCTAssertNil(editor.viewModelForTesting.selectedIndex)
        let rail = try XCTUnwrap(editor.view.subviews.compactMap { $0 as? EditorToolRail }.first)
        XCTAssertEqual(rail.visibleToolIdentifiers.first, "videoLayoutButton",
                       "the rail must still be showing only its base tools")
    }

    func testTappingAFilledLaneStillSelectsIt() throws {
        let editor = makeEditor()
        try timeline(in: editor).onSelectClip?(0)
        XCTAssertEqual(editor.viewModelForTesting.selectedIndex, 0)
    }

    func testTappingATextPillSelectsThatOverlay() throws {
        let editor = makeEditor()
        let id = editor.addTextOverlayForTesting()

        try timeline(in: editor).onSelectText?(id)

        XCTAssertEqual(editor.selectedTextIDForTesting, id)
    }

    func testSelectionIsReflectedBackIntoTheTimelinesModel() throws {
        let editor = makeEditor()
        editor.selectClipForTesting(0)

        XCTAssertEqual(try timeline(in: editor).modelForTesting.selectedClipIndex, 0)
    }
}
