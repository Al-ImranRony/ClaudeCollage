//
//  CarouselStyleSyncTests.swift
//  CaroullageTests
//
//  Step 06 — "Sync Edit" became "Apply Style to All Frames".
//
//  The capability was always right for a carousel; the toggle around it was not.
//  It was hidden modal state — flip it on, edit a frame later, and other frames
//  changed with no announcement — and it only ever broadcast two of the four
//  things `StyleChange` defines. As an explicit, undoable action it says what it
//  does, does it once, and does all four.
//
//  Also pins the layout axis, which is now persisted for every carousel type and
//  must stay purely presentational: it decides how the navigator is laid out and
//  must never reach the frames, because the frames are what gets exported.
//

import XCTest
import CoreGraphics
@testable import Caroullage

@MainActor
final class CarouselStyleSyncTests: XCTestCase {

    private func makeVM(
        _ n: Int, type: CarouselType = .matched, axis: SplitAxis = .horizontal
    ) -> CarouselEditorViewModel {
        let frames = (0..<n).map { CarouselFrame(index: $0, state: GridEditorState()) }
        return CarouselEditorViewModel(
            frames: frames, canvasSize: CGSize(width: 1080, height: 1350),
            carouselType: type, axis: axis)
    }

    /// A frame with a deliberately distinct look, to prove it is the SOURCE.
    private func styledState() -> GridEditorState {
        var state = GridEditorState()
        state.background = .solid(hex: "#123456")
        state.borderWidth = 42
        state.textOverlays = [
            TextOverlay(text: "Hello", fontName: "Georgia-Bold", colorHex: "#ABCDEF")
        ]
        return state
    }

    // MARK: - Apply to all

    func testApplyingStyleCopiesBackgroundAndBorderToEveryFrame() {
        let vm = makeVM(4)
        vm.commitCurrentFrame(state: styledState(), images: [:])
        vm.applyStyleToAllFrames()

        for frame in vm.frames {
            XCTAssertEqual(frame.state.background, .solid(hex: "#123456"))
            XCTAssertEqual(frame.state.borderWidth, 42, accuracy: 0.001)
        }
    }

    func testApplyingStyleCopiesFontAndTextColourToEveryFrameThatHasText() {
        // `.font` and `.textColor` were defined in StyleChange and never sent.
        let vm = makeVM(3)
        var second = GridEditorState()
        second.textOverlays = [TextOverlay(text: "Second", fontName: "Helvetica")]
        vm.selectFrame(1)
        vm.commitCurrentFrame(state: second, images: [:])
        vm.selectFrame(0)
        vm.commitCurrentFrame(state: styledState(), images: [:])

        vm.applyStyleToAllFrames()

        let overlay = vm.frames[1].state.textOverlays.first
        XCTAssertEqual(overlay?.fontName, "Georgia-Bold")
        XCTAssertEqual(overlay?.colorHex, "#ABCDEF")
        XCTAssertEqual(overlay?.text, "Second", "Styling is copied; the words are not")
    }

    func testApplyingStyleFromAFrameWithNoTextLeavesOtherFramesTypeAlone() {
        // Otherwise styling from a photo-only frame would silently reset every
        // caption in the carousel to the default font.
        let vm = makeVM(2)
        var withText = GridEditorState()
        withText.textOverlays = [TextOverlay(text: "Keep me", fontName: "Georgia-Bold")]
        vm.selectFrame(1)
        vm.commitCurrentFrame(state: withText, images: [:])

        vm.selectFrame(0)
        var plain = GridEditorState()
        plain.background = .black
        vm.commitCurrentFrame(state: plain, images: [:])
        vm.applyStyleToAllFrames()

        XCTAssertEqual(vm.frames[1].state.textOverlays.first?.fontName, "Georgia-Bold")
        XCTAssertEqual(vm.frames[1].state.background, .black, "…but the background still applies")
    }

    func testApplyingStyleIsUndoable() {
        // The action replaces a confirmation-free toggle, so undo is what makes it
        // safe to try.
        let vm = makeVM(3)
        vm.commitCurrentFrame(state: styledState(), images: [:])
        let before = vm.frames.map(\.state.background)

        vm.applyStyleToAllFrames()
        XCTAssertTrue(vm.canUndo)
        vm.undo()

        XCTAssertEqual(vm.frames.map(\.state.background), before)
    }

    func testApplyingStyleLeavesEachFramesPhotosAlone() {
        let vm = makeVM(2)
        var withPhoto = GridEditorState()
        withPhoto.borderWidth = 5
        vm.selectFrame(1)
        vm.commitCurrentFrame(state: withPhoto, images: [:])
        let cellsBefore = vm.frames[1].state.cells

        vm.selectFrame(0)
        vm.commitCurrentFrame(state: styledState(), images: [:])
        vm.applyStyleToAllFrames()

        XCTAssertEqual(vm.frames[1].state.cells, cellsBefore,
                       "Style sync must never touch a frame's photo content")
    }

    // MARK: - Layout axis

    func testTheAxisDefaultsToHorizontal() {
        XCTAssertEqual(makeVM(3).axis, .horizontal)
    }

    func testTheAxisIsCarriedByTheViewModel() {
        XCTAssertEqual(makeVM(3, axis: .vertical).axis, .vertical)
    }

    func testChangingTheAxisDoesNotTouchTheFrames() {
        // The axis is presentation only. If it ever reaches the frames it reaches
        // the export, and a carousel would render differently depending on how its
        // navigator happened to be arranged.
        let vm = makeVM(4, axis: .horizontal)
        vm.commitCurrentFrame(state: styledState(), images: [:])
        let before = vm.frames

        vm.axis = .vertical

        XCTAssertEqual(vm.frames, before)
    }
}
