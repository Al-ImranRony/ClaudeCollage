//
//  CarouselEditorViewModelTests.swift
//  CaroullageTests
//
//  Step 03b slice 4a — the carousel editor's view model: the frame list, the
//  selected frame, per-frame commit (the embedded grid editor hands its live state
//  back before a switch), the structural frame ops (add / delete / reorder) with
//  carousel-level undo, and sync-edit broadcasting. All value logic — no UIKit — so
//  it's unit-tested here; the VC/navigator wiring is slice 4b.
//

import XCTest
import CoreGraphics
@testable import Caroullage

@MainActor
final class CarouselEditorViewModelTests: XCTestCase {

    private func frames(_ n: Int) -> [CarouselFrame] {
        (0..<n).map { CarouselFrame(index: $0, state: GridEditorState()) }
    }

    private func makeVM(_ n: Int, type: CarouselType = .scrollThrough) -> CarouselEditorViewModel {
        CarouselEditorViewModel(frames: frames(n), canvasSize: CGSize(width: 1080, height: 1350),
                                carouselType: type)
    }

    func testInitSelectsFirstFrame() {
        let vm = makeVM(3)
        XCTAssertEqual(vm.frameCount, 3)
        XCTAssertEqual(vm.currentIndex, 0)
    }

    func testCommitCurrentFramePersistsEditorState() {
        let vm = makeVM(2)
        var edited = GridEditorState()
        edited.background = .black
        vm.commitCurrentFrame(state: edited, images: [:])
        XCTAssertEqual(vm.currentFrame.state.background, .black)
    }

    func testSelectFrameChangesCurrentIndex() {
        let vm = makeVM(3)
        vm.selectFrame(2)
        XCTAssertEqual(vm.currentIndex, 2)
        vm.selectFrame(99)   // out of range → ignored
        XCTAssertEqual(vm.currentIndex, 2)
    }

    func testAddFrameAppendsAndSelectsIt() {
        let vm = makeVM(2)
        XCTAssertTrue(vm.addFrame())
        XCTAssertEqual(vm.frameCount, 3)
        XCTAssertEqual(vm.currentIndex, 2, "the new frame becomes current")
        XCTAssertEqual(vm.frames.map(\.index), [0, 1, 2])
    }

    func testAddFrameCappedAtTen() {
        let vm = makeVM(10)
        XCTAssertFalse(vm.addFrame(), "a carousel can't exceed 10 frames")
        XCTAssertEqual(vm.frameCount, 10)
    }

    func testDeleteFrameRemovesAndClampsIndex() {
        let vm = makeVM(3)
        vm.selectFrame(2)
        vm.deleteFrame(at: 2)
        XCTAssertEqual(vm.frameCount, 2)
        XCTAssertEqual(vm.currentIndex, 1, "current index clamps into the shrunk range")
        XCTAssertEqual(vm.frames.map(\.index), [0, 1])
    }

    func testDeleteKeepsAtLeastOneFrame() {
        let vm = makeVM(1)
        vm.deleteFrame(at: 0)
        XCTAssertEqual(vm.frameCount, 1, "the last frame can't be deleted")
    }

    func testMoveFrameKeepsCurrentOnTheMovedFrame() {
        let vm = makeVM(3)
        let firstID = vm.frames[0].id
        vm.selectFrame(0)
        vm.moveFrame(from: 0, to: 2)
        XCTAssertEqual(vm.frames.map(\.index), [0, 1, 2])
        XCTAssertEqual(vm.frames[2].id, firstID, "the moved frame lands last")
        XCTAssertEqual(vm.currentIndex, 2, "selection follows the frame that moved")
    }

    func testUndoRestoresFrameCountAfterAdd() {
        let vm = makeVM(2)
        vm.addFrame()
        XCTAssertEqual(vm.frameCount, 3)
        XCTAssertTrue(vm.canUndo)
        vm.undo()
        XCTAssertEqual(vm.frameCount, 2, "undo reverts the added frame")
    }

    func testRedoReappliesAfterUndo() {
        let vm = makeVM(2)
        vm.addFrame()
        vm.undo()
        XCTAssertTrue(vm.canRedo)
        vm.redo()
        XCTAssertEqual(vm.frameCount, 3, "redo re-adds the frame")
    }

    // `applySyncEdit` broadcast one `StyleChange` and recorded an undo step per
    // call. `applyStyleToAllFrames` replaced it with a batched, single-step
    // version, leaving the old primitive reachable only from this test — coverage
    // that proved a path nothing took. Both are gone; `CarouselStyleSyncTests`
    // covers the broadcast that ships.

    // Step 06 removed `isSyncEditEnabled`. The toggle's default is no longer a
    // thing to assert — style sync is an explicit action, covered by
    // `CarouselStyleSyncTests`. What replaced it here is the undo behaviour that
    // change depended on.

    func testEditingAFrameIsItsOwnUndoStep() {
        // `commitCurrentFrame` used not to record, so the nav bar's Undo skipped
        // straight past a frame edit to whatever structural change preceded it —
        // silently discarding the edit along the way.
        let vm = makeVM(2)
        var edited = GridEditorState()
        edited.background = .black
        vm.commitCurrentFrame(state: edited, images: [:])

        XCTAssertTrue(vm.canUndo)
        vm.undo()
        XCTAssertNotEqual(vm.frames[0].state.background, .black,
                          "Undo steps back over the frame edit")
    }

    func testCommittingAnUnchangedFrameDoesNotAddAnUndoStep() {
        // `commitCurrentFrame` runs on every return to the navigator, including
        // returns from an editor that changed nothing. Recording those would fill
        // the stack with no-ops and make Undo appear to do nothing.
        let vm = makeVM(2)
        let unchanged = vm.currentFrame.state
        vm.commitCurrentFrame(state: unchanged, images: [:])
        XCTAssertFalse(vm.canUndo)
    }
}
