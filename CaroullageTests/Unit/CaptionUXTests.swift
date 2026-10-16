//
//  CaptionUXTests.swift
//  CaroullageTests
//
//  The four caption findings of the 2026-10-16 QA pass
//  (docs/qa/2026-10-16-qa-report.md §4): where a new caption lands, the
//  default text acting as a placeholder, overlays that can no longer be
//  dragged out of reach, and VoiceOver following a panning collage's camera.
//

import XCTest
import UIKit
@testable import Caroullage

@MainActor
final class CaptionUXTests: XCTestCase {

    private var windows: [UIWindow] = []

    override func tearDown() {
        windows.forEach { $0.isHidden = true }
        windows = []
        super.tearDown()
    }

    // MARK: - 1. A new caption avoids the ones already there

    private let band = CGRect(x: 0.12, y: 0.44, width: 0.76, height: 0.14)

    func testCandidatesStartAtThePreferredBandAndAlternateOutward() {
        let candidates = CaptionPlacement.candidates(around: band)
        XCTAssertEqual(candidates.first, band)
        XCTAssertGreaterThan(candidates[1].minY, band.minY, "then just below")
        XCTAssertLessThan(candidates[2].minY, band.minY, "then just above")
        for candidate in candidates {
            XCTAssertGreaterThanOrEqual(candidate.minY, 0)
            XCTAssertLessThanOrEqual(candidate.maxY, 1 + 1e-9, "every band stays on the canvas")
            XCTAssertEqual(candidate.width, band.width)
        }
    }

    func testTheFirstFreeBandIsTaken() {
        let candidates = CaptionPlacement.candidates(around: band)
        let free = CaptionPlacement.firstFree(candidates, avoiding: [band])
        XCTAssertEqual(free, candidates[1], "the band below, when the middle is taken")
        XCTAssertEqual(CaptionPlacement.firstFree(candidates, avoiding: []), band, "an empty canvas keeps the middle")
    }

    func testACrowdedCanvasFallsBackToThePreferredBand() {
        let candidates = CaptionPlacement.candidates(around: band)
        let everywhere = CGRect(x: 0, y: 0, width: 1, height: 1)
        XCTAssertEqual(CaptionPlacement.firstFree(candidates, avoiding: [everywhere]), band)
    }

    func testTheVideoEditorPlacesANewCaptionClearOfTheCaptionOnScreen() {
        // Caption Stack's own caption sits across the middle.
        let viewModel = VideoEditorViewModel(template: VideoTemplateCatalog.captionStack)
        let onScreen = viewModel.textOverlays.filter { $0.isVisible(at: 0) }
        XCTAssertFalse(onScreen.isEmpty, "the template has a caption at 0s")

        let placed = viewModel.newCaptionFrame(preferredVisible: band, at: 0, duration: 6)
        for caption in onScreen {
            XCTAssertFalse(placed.intersects(caption.frame),
                           "a new caption must not land on \"\(caption.text)\"")
        }
    }

    func testACaptionTimedOutOfThePlayheadIsNotInTheWay() {
        let viewModel = VideoEditorViewModel(canvasSize: CGSize(width: 1080, height: 1920))
        viewModel.addTextOverlay(TextOverlay(text: "Later", startTime: 4, endTime: 6, frame: band))
        XCTAssertEqual(viewModel.newCaptionFrame(preferredVisible: band, at: 1, duration: 6), band,
                       "at 1s the 4s caption is not on screen, so the middle is free")
        XCTAssertNotEqual(viewModel.newCaptionFrame(preferredVisible: band, at: 5, duration: 6), band)
    }

    func testThePhotoEditorPlacesANewCaptionClearOfAnExistingOne() {
        let viewModel = GridEditorViewModel(canvasSize: CGSize(width: 1080, height: 1080))
        let preferred = CGRect(x: 0.12, y: 0.42, width: 0.76, height: 0.16)
        viewModel.addTextOverlay(TextOverlay(text: "Title", frame: preferred))
        let placed = viewModel.newCaptionFrame(preferred: preferred)
        XCTAssertFalse(placed.intersects(preferred))
    }

    // MARK: - 2. "Your text" is a placeholder, not content

    func testANewCaptionShowsItsDefaultAsThePlaceholder() {
        let draft = CaptionTextDraft(showsPlaceholder: true)
        XCTAssertEqual(draft.fieldText(for: "Your text"), "", "the field is empty; its prompt says Your text")
    }

    func testTheFirstKeystrokeReplacesTheDefault() {
        var draft = CaptionTextDraft(showsPlaceholder: true)
        XCTAssertEqual(draft.edit("H"), "H", "typing replaces — never appends to — the default")
        XCTAssertFalse(draft.showsPlaceholder)
        XCTAssertEqual(draft.fieldText(for: "H"), "H")
    }

    func testAnEmptyReportBeforeTypingLeavesTheDefaultOnTheCanvas() {
        var draft = CaptionTextDraft(showsPlaceholder: true)
        XCTAssertNil(draft.edit(""), "nothing typed yet: keep the default visible on the canvas")
        XCTAssertTrue(draft.showsPlaceholder)
    }

    func testAnExistingCaptionEditsItsOwnText() {
        var draft = CaptionTextDraft(showsPlaceholder: false)
        XCTAssertEqual(draft.fieldText(for: "Hello"), "Hello")
        XCTAssertEqual(draft.edit(""), "", "clearing an existing caption is the user's choice")
    }

    // MARK: - 3. Overlays stay reachable

    func testTheClampKeepsACentreOnTheCanvas() {
        XCTAssertEqual(SnapEngine.clampedToCanvas(CGPoint(x: 1.4, y: -0.3)), CGPoint(x: 1, y: 0))
        XCTAssertEqual(SnapEngine.clampedToCanvas(CGPoint(x: 0.3, y: 0.7)), CGPoint(x: 0.3, y: 0.7))
    }

    private func moveRight(_ view: UIView, times: Int) {
        let action = view.accessibilityCustomActions?.first { $0.name == CanvasAccessibility.moveRightAction }
        XCTAssertNotNil(action)
        for _ in 0..<times { _ = action?.actionHandler?(action!) }
    }

    func testACaptionCannotBeMovedOffTheCanvas() throws {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        let view = TextOverlayView()
        container.addSubview(view)
        let caption = TextOverlay(text: "Edge", frame: CGRect(x: 0.6, y: 0.4, width: 0.3, height: 0.1))
        let frame = TextRendering.frame(for: caption, in: container.bounds.size)
        view.bounds = CGRect(origin: .zero, size: frame.size)
        view.center = CGPoint(x: frame.midX, y: frame.midY)
        view.configure(with: caption, fontScale: 1)
        var last: TextOverlay?
        view.onChanged = { last = $0 }

        moveRight(view, times: 200)   // 200 × 2% of the width: far past the edge

        let moved = try XCTUnwrap(last)
        XCTAssertLessThanOrEqual(moved.frame.midX, 1 + 1e-9, "its centre stops at the edge")
        XCTAssertLessThanOrEqual(view.center.x, container.bounds.width + 1e-6)
    }

    func testAStickerCannotBeMovedOffTheCanvas() throws {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        let sticker = StickerOverlay(stickerID: "heart", symbolName: "heart.fill", colorHex: "#FF0000",
                                     center: CGPoint(x: 0.9, y: 0.5), sizeNorm: 0.2)
        let view = StickerOverlayView(overlay: sticker)
        container.addSubview(view)
        view.apply(overlay: sticker, in: container.bounds.size)
        var last: StickerOverlay?
        view.onChanged = { last = $0 }

        moveRight(view, times: 200)

        let moved = try XCTUnwrap(last)
        XCTAssertLessThanOrEqual(moved.centerX, 1 + 1e-9)
    }

    // MARK: - 4. VoiceOver follows the camera

    func testOnAPanningCollageOnlyWhatTheCameraShowsIsAnElement() throws {
        // Two panels on a 2-frame strip; the view shows one frame at a time.
        let view = VideoCanvasView(frame: CGRect(x: 0, y: 0, width: 160, height: 90))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        window.addSubview(view)
        window.isHidden = false
        windows.append(window)
        view.configure(canvasSize: CGSize(width: 160, height: 90),
                       cellFrames: [CGRect(x: 0, y: 0, width: 160, height: 90),
                                    CGRect(x: 160, y: 0, width: 160, height: 90)],
                       filled: [false, false], selectedIndex: nil,
                       pan: CanvasPan(axis: .horizontal, extent: 2))
        view.compositionDuration = 10
        view.updateTextOverlays([TextOverlay(text: "Second panel",
                                             frame: CGRect(x: 0.6, y: 0.4, width: 0.3, height: 0.1))])
        view.layoutIfNeeded()

        func elementIDs() -> [String] {
            (view.accessibilityElements as? [UIView] ?? []).map {
                $0.accessibilityIdentifier ?? $0.accessibilityLabel ?? "?"
            }
        }

        view.setPreviewTime(0)
        XCTAssertEqual(elementIDs().filter { $0.hasPrefix("videoCell-") }, ["videoCell-0"],
                       "at the start only the first panel is on screen")
        XCTAssertFalse(elementIDs().contains { $0.contains("Second panel") },
                       "a caption on the panel the camera has not reached is not reachable by VoiceOver")

        view.setPreviewTime(10)
        XCTAssertEqual(elementIDs().filter { $0.hasPrefix("videoCell-") }, ["videoCell-1"],
                       "after the pan only the second panel is")
        XCTAssertTrue(elementIDs().contains { $0.contains("Second panel") })
    }

    func testANonPanningCanvasListsEverything() {
        let view = VideoCanvasView(frame: CGRect(x: 0, y: 0, width: 108, height: 108))
        view.configure(canvasSize: CGSize(width: 1080, height: 1080),
                       cellFrames: [CGRect(x: 0, y: 0, width: 540, height: 1080),
                                    CGRect(x: 540, y: 0, width: 540, height: 1080)],
                       filled: [false, false], selectedIndex: nil)
        view.layoutIfNeeded()
        XCTAssertEqual((view.accessibilityElements ?? []).count, 2)
    }
}
