//
//  VideoEditorViewModelTests.swift
//  ClaudeCollageTests
//
//  Step 04 slice 5b — the video editor's view model: one `VideoCellState` per
//  layout slot, the per-cell controls (trim / loop / mute / volume / transition),
//  the background-music track, undo/redo over both, and the bridge that turns all
//  of it into the `VideoCompositionCell`s the slice-3/4/5a engine composes.
//
//  All logic is value-based (no UIKit / no real media decode), so the whole model
//  is unit-tested headlessly; the AVAssets here are placeholder URL assets that are
//  never decoded — only carried through to the composition inputs.
//

import XCTest
import AVFoundation
import CoreGraphics
@testable import ClaudeCollage

@MainActor
final class VideoEditorViewModelTests: XCTestCase {

    private func makeAsset(_ name: String = "clip") -> AVAsset {
        AVURLAsset(url: URL(fileURLWithPath: "/tmp/\(name)-\(UUID().uuidString).mov"))
    }

    private func makeViewModel(
        layout: CollageLayout = .grid(.twoUpVertical)
    ) -> VideoEditorViewModel {
        VideoEditorViewModel(canvasSize: CGSize(width: 1080, height: 1080), layout: layout)
    }

    // MARK: - Layout → cells

    func testInitCreatesOneCellPerLayoutSlot() {
        XCTAssertEqual(makeViewModel(layout: .grid(.fourSquare)).cellCount, 4)
    }

    func testChangeLayoutPadsAndPreservesExistingCells() {
        let vm = makeViewModel(layout: .grid(.twoUpVertical))
        let id = UUID()
        vm.setVideo(assetID: id, asset: makeAsset(), forCellAt: 0)
        vm.changeLayout(.grid(.sixGrid))
        XCTAssertEqual(vm.cellCount, 6)
        XCTAssertEqual(vm.cells[0].videoID, id, "existing cell content survives a layout change")
        XCTAssertNil(vm.cells[5].videoID, "new slots start empty")
    }

    func testChangeLayoutTruncatesWhenSmaller() {
        let vm = makeViewModel(layout: .grid(.fourSquare))
        vm.changeLayout(.grid(.twoUpVertical))
        XCTAssertEqual(vm.cellCount, 2)
    }

    func testCellFramesMatchLayoutGeometry() {
        let vm = makeViewModel(layout: .grid(.twoUpVertical))
        let frames = vm.cellFrames()
        XCTAssertEqual(frames.count, 2)
        // Vertical split of a 1080×1080 canvas → top half then bottom half.
        XCTAssertEqual(frames[0].frame.height, 540, accuracy: 1)
        XCTAssertEqual(frames[1].frame.minY, 540, accuracy: 1)
    }

    // MARK: - Per-cell content + controls

    func testSetVideoAssignsIDToCell() {
        let vm = makeViewModel()
        let id = UUID()
        vm.setVideo(assetID: id, asset: makeAsset(), forCellAt: 1)
        XCTAssertEqual(vm.cells[1].videoID, id)
        XCTAssertNil(vm.cells[0].videoID)
    }

    func testSetVideoDefaultsToLoopingSoShortClipsFillTheTimeline() {
        let vm = makeViewModel()
        vm.setVideo(assetID: UUID(), asset: makeAsset(), forCellAt: 0)
        XCTAssertTrue(vm.cells[0].isLooping,
                      "a freshly placed clip loops by default so it never leaves a hole")
    }

    func testFilledCellCountCountsOnlyCellsWithVideo() {
        let vm = makeViewModel(layout: .grid(.fourSquare))
        vm.setVideo(assetID: UUID(), asset: makeAsset(), forCellAt: 0)
        vm.setVideo(assetID: UUID(), asset: makeAsset(), forCellAt: 2)
        XCTAssertEqual(vm.filledCellCount, 2)
    }

    func testClearVideoEmptiesCell() {
        let vm = makeViewModel()
        vm.setVideo(assetID: UUID(), asset: makeAsset(), forCellAt: 0)
        vm.clearVideo(atCellIndex: 0)
        XCTAssertNil(vm.cells[0].videoID)
        XCTAssertEqual(vm.filledCellCount, 0)
    }

    func testSetTrimLoopMuteOnCell() {
        let vm = makeViewModel()
        vm.setTrim(VideoTrim(start: 1, end: 3), forCellAt: 0)
        vm.setLooping(true, forCellAt: 0)
        vm.setMuted(true, forCellAt: 0)
        XCTAssertEqual(vm.cells[0].trim, VideoTrim(start: 1, end: 3))
        XCTAssertTrue(vm.cells[0].isLooping)
        XCTAssertTrue(vm.cells[0].isMuted)
    }

    func testSetVolumeIsClamped() {
        let vm = makeViewModel()
        vm.setVolume(3.0, forCellAt: 0)
        XCTAssertEqual(vm.cells[0].volume, 1, accuracy: 1e-9)
        vm.setVolume(-1.0, forCellAt: 0)
        XCTAssertEqual(vm.cells[0].volume, 0, accuracy: 1e-9)
    }

    func testSetTransitionOnCell() {
        let vm = makeViewModel()
        vm.setTransition(CellTransition(style: .zoomIn, duration: 0.4), forCellAt: 0)
        XCTAssertEqual(vm.cells[0].transition?.style, .zoomIn)
    }

    func testOutOfRangeCellIndexIsIgnored() {
        let vm = makeViewModel()
        vm.setVolume(0.5, forCellAt: 99)   // must not trap
        XCTAssertEqual(vm.cellCount, 2)
    }

    // MARK: - Interactive changes (coalesced undo, hardening #3)

    // Simulate a slider drag: many mid-gesture updates ending at 0.25.
    private let dragVolumes = [0.9, 0.7, 0.5, 0.35, 0.25]

    func testInteractiveVolumeDoesNotRecordUndoUntilCommitted() {
        let vm = makeViewModel()
        for v in dragVolumes { vm.setVolumeInteractive(v, forCellAt: 0) }
        XCTAssertFalse(vm.canUndo, "mid-drag updates must not each push an undo snapshot")
        XCTAssertEqual(vm.cells[0].volume, 0.25, accuracy: 1e-9, "but the live value still tracks the drag")
    }

    func testCommitInteractiveRecordsExactlyOneUndoStep() {
        let vm = makeViewModel()
        for v in dragVolumes { vm.setVolumeInteractive(v, forCellAt: 0) }
        vm.commitInteractive()
        XCTAssertTrue(vm.canUndo)
        vm.undo()
        XCTAssertEqual(vm.cells[0].volume, 1.0, accuracy: 1e-9,
                       "one undo returns the whole drag to where it began")
    }

    func testInteractiveTrimThenCommitIsOneStep() {
        let vm = makeViewModel()
        vm.setTrimInteractive(VideoTrim(start: 0.1, end: 0.5), forCellAt: 0)
        vm.setTrimInteractive(VideoTrim(start: 0.2, end: 0.9), forCellAt: 0)
        XCTAssertFalse(vm.canUndo)
        vm.commitInteractive()
        XCTAssertEqual(vm.cells[0].trim, VideoTrim(start: 0.2, end: 0.9))
        XCTAssertTrue(vm.canUndo)
    }

    // MARK: - Selection

    func testSelectCellIgnoresOutOfRange() {
        let vm = makeViewModel()
        vm.selectCell(at: 1)
        XCTAssertEqual(vm.selectedIndex, 1)
        vm.selectCell(at: 7)
        XCTAssertEqual(vm.selectedIndex, 1, "an out-of-range selection is ignored")
        vm.selectCell(at: nil)
        XCTAssertNil(vm.selectedIndex)
    }

    // MARK: - Background music

    func testSetMusicStoresStateAndVolume() {
        let vm = makeViewModel()
        let id = UUID()
        vm.setMusic(assetID: id, asset: makeAsset("song"), volume: 0.5)
        XCTAssertEqual(vm.music?.musicID, id)
        XCTAssertEqual(vm.music?.volume ?? -1, 0.5, accuracy: 1e-9)
    }

    func testMusicVolumeIsClamped() {
        let vm = makeViewModel()
        vm.setMusic(assetID: UUID(), asset: makeAsset("song"))
        vm.setMusicVolume(4.0)
        XCTAssertEqual(vm.music?.volume ?? -1, 1, accuracy: 1e-9)
    }

    func testRemoveMusicClearsIt() {
        let vm = makeViewModel()
        vm.setMusic(assetID: UUID(), asset: makeAsset("song"))
        vm.removeMusic()
        XCTAssertNil(vm.music)
        XCTAssertNil(vm.backgroundMusic())
    }

    func testBackgroundMusicCarriesVolumeToTheEngineInput() {
        let vm = makeViewModel()
        vm.setMusic(assetID: UUID(), asset: makeAsset("song"), volume: 0.25)
        let music = vm.backgroundMusic()
        XCTAssertNotNil(music)
        XCTAssertEqual(music?.volume ?? -1, 0.25, accuracy: 1e-9)
    }

    // MARK: - Composition bridge

    func testCompositionCellsOnlyIncludeCellsWithAssets() {
        let vm = makeViewModel(layout: .grid(.fourSquare))
        vm.setVideo(assetID: UUID(), asset: makeAsset(), forCellAt: 1)
        XCTAssertEqual(vm.compositionCells().count, 1, "empty cells contribute no track")
    }

    func testCompositionCellsCarryPerCellControls() {
        let vm = makeViewModel()
        vm.setVideo(assetID: UUID(), asset: makeAsset(), forCellAt: 0)
        vm.setTrim(VideoTrim(start: 0.5, end: 2), forCellAt: 0)
        vm.setLooping(true, forCellAt: 0)
        vm.setMuted(true, forCellAt: 0)
        vm.setVolume(0.3, forCellAt: 0)
        vm.setTransition(CellTransition(style: .crossfade, duration: 0.5), forCellAt: 0)

        let cell = try? XCTUnwrap(vm.compositionCells().first)
        XCTAssertEqual(cell?.trim, VideoTrim(start: 0.5, end: 2))
        XCTAssertEqual(cell?.isLooping, true)
        XCTAssertEqual(cell?.isMuted, true)
        XCTAssertEqual(cell?.volume ?? -1, 0.3, accuracy: 1e-9)
        XCTAssertEqual(cell?.transition?.style, .crossfade)
    }

    func testCompositionCellFrameMatchesItsLayoutSlot() {
        let vm = makeViewModel(layout: .grid(.twoUpVertical))
        vm.setVideo(assetID: UUID(), asset: makeAsset(), forCellAt: 1)
        let cell = vm.compositionCells().first
        // Bottom half of the 1080-square canvas.
        XCTAssertEqual(cell?.frame.minY ?? -1, 540, accuracy: 1)
    }

    // MARK: - Undo / redo

    func testUndoRestoresPreviousCellState() {
        let vm = makeViewModel()
        vm.setVolume(0.4, forCellAt: 0)
        vm.setVolume(0.9, forCellAt: 0)
        vm.undo()
        XCTAssertEqual(vm.cells[0].volume, 0.4, accuracy: 1e-9)
    }

    func testRedoReappliesTheChange() {
        let vm = makeViewModel()
        vm.setVolume(0.4, forCellAt: 0)
        vm.setVolume(0.9, forCellAt: 0)
        vm.undo()
        vm.redo()
        XCTAssertEqual(vm.cells[0].volume, 0.9, accuracy: 1e-9)
    }

    func testUndoRestoresMusic() {
        let vm = makeViewModel()
        vm.setMusic(assetID: UUID(), asset: makeAsset("song"), volume: 0.8)
        vm.removeMusic()
        XCTAssertNil(vm.music)
        vm.undo()
        XCTAssertNotNil(vm.music, "undo brings the music track back")
    }

    func testCanUndoIsFalseOnAFreshEditor() {
        XCTAssertFalse(makeViewModel().canUndo)
    }
}
