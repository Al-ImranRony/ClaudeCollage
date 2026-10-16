//
//  VideoTemplateEditorTests.swift
//  CaroullageTests
//
//  What the video templates added to the EDITOR: filling every empty slot in
//  one pick, placing new overlays in the visible frame of a panning strip, the
//  canvas following the camera (and tapping through it), captions animating on
//  the canvas but resting while selected and paused, and the style presets
//  staying readable.
//

import AVFoundation
import XCTest
@testable import Caroullage

@MainActor
final class VideoTemplateEditorTests: XCTestCase {

    private var windows: [UIWindow] = []

    override func tearDown() async throws {
        windows.forEach { $0.isHidden = true }
        windows = []
    }

    private func makeAsset() -> AVAsset {
        AVURLAsset(url: URL(fileURLWithPath: "/tmp/clip-\(UUID().uuidString).mov"))
    }

    // MARK: - Fill every empty slot

    func testFillingEmptySlotsGoesInLayoutOrderAsOneUndoStep() {
        let viewModel = VideoEditorViewModel(template: VideoTemplateCatalog.lyricStack)
        viewModel.setVideo(assetID: UUID(), asset: makeAsset(), forCellAt: 1)
        XCTAssertEqual(viewModel.emptyCellIndices, [0, 2])

        let first = makeAsset(), second = makeAsset(), extra = makeAsset()
        let filled = viewModel.fillEmptyCells(with: [first, second, extra])

        XCTAssertEqual(filled, 2, "only as many as there are empty slots")
        XCTAssertTrue(viewModel.asset(forCellAt: 0) === first)
        XCTAssertTrue(viewModel.asset(forCellAt: 2) === second)
        XCTAssertTrue(viewModel.emptyCellIndices.isEmpty)
        XCTAssertTrue(viewModel.cells.allSatisfy(\.isLooping), "fresh clips loop, as a single pick does")

        viewModel.undo()
        XCTAssertEqual(viewModel.emptyCellIndices, [0, 2], "one undo takes the whole batch back")
    }

    func testFillingWithNothingRecordsNothing() {
        let viewModel = VideoEditorViewModel(template: VideoTemplateCatalog.titleGrid)
        XCTAssertEqual(viewModel.fillEmptyCells(with: []), 0)
        XCTAssertFalse(viewModel.canUndo)
    }

    // MARK: - Placement on a panning strip

    func testWithoutAPanANewOverlayKeepsItsFrame() {
        let viewModel = VideoEditorViewModel(canvasSize: CGSize(width: 1080, height: 1920))
        let rect = CGRect(x: 0.1, y: 0.4, width: 0.8, height: 0.1)
        XCTAssertEqual(viewModel.layoutRect(forVisibleRect: rect, at: 3, duration: 6), rect)
    }

    func testOnAPanningStripANewOverlayLandsWhereTheCameraIs() {
        let viewModel = VideoEditorViewModel(template: VideoTemplateCatalog.travelFilmstrip)  // 2.5 frames
        viewModel.setGlide(.wholeVideo)   // one pass, so t = duration is the strip's end
        let rect = CGRect(x: 0, y: 0.4, width: 1, height: 0.1)   // the whole visible frame

        let atStart = viewModel.layoutRect(forVisibleRect: rect, at: 0, duration: 10)
        XCTAssertEqual(atStart.minX, 0, accuracy: 1e-9)
        XCTAssertEqual(atStart.width, 0.4, accuracy: 1e-9, "one frame of a 2.5-frame strip")

        let atEnd = viewModel.layoutRect(forVisibleRect: rect, at: 10, duration: 10)
        XCTAssertEqual(atEnd.maxX, 1, accuracy: 1e-9, "the last frame of the strip")
        XCTAssertEqual(atEnd.minY, 0.4, accuracy: 1e-9, "a horizontal pan leaves y alone")
    }

    // MARK: - Canvas

    private func makeCanvas(pan: CanvasPan?, frames: [CGRect], canvas: CGSize) -> VideoCanvasView {
        let view = VideoCanvasView(frame: CGRect(x: 0, y: 0, width: canvas.width / 10, height: canvas.height / 10))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        window.addSubview(view)
        window.isHidden = false
        windows.append(window)
        view.configure(canvasSize: canvas, cellFrames: frames,
                       filled: frames.map { _ in false }, selectedIndex: nil, pan: pan)
        view.layoutIfNeeded()
        return view
    }

    func testTheCanvasFollowsTheCameraAndTapsLandThroughIt() {
        // Two 160-wide panels on a 2-frame strip; the view is 16pt wide.
        let canvas = makeCanvas(
            pan: CanvasPan(axis: .horizontal, extent: 2),
            frames: [CGRect(x: 0, y: 0, width: 160, height: 90),
                     CGRect(x: 160, y: 0, width: 160, height: 90)],
            canvas: CGSize(width: 160, height: 90))
        canvas.compositionDuration = 10

        canvas.setPreviewTime(0)
        XCTAssertEqual(canvas.cameraOffsetForTesting.x, 0, accuracy: 1e-6)
        XCTAssertEqual(canvas.cellIndex(at: CGPoint(x: 8, y: 4)), 0)

        canvas.setPreviewTime(10)
        XCTAssertEqual(canvas.cameraOffsetForTesting.x, 16, accuracy: 1e-6, "a full frame travelled")
        XCTAssertEqual(canvas.cellIndex(at: CGPoint(x: 8, y: 4)), 1,
                       "the same spot on screen is now over the second panel")
    }

    func testCaptionsAnimateWhilePlayingAndRestWhilePaused() throws {
        let canvas = makeCanvas(pan: nil, frames: [CGRect(x: 0, y: 0, width: 1080, height: 1920)],
                                canvas: CGSize(width: 1080, height: 1920))
        let caption = TextOverlay(text: "One two three", animation: .words, startTime: 0, endTime: 6,
                                  frame: CGRect(x: 0.1, y: 0.4, width: 0.8, height: 0.1))
        canvas.updateTextOverlays([caption])
        canvas.setPreviewTime(0.05)
        let view = try XCTUnwrap(canvas.textOverlayViewsForTesting.first as? TextOverlayView)
        XCTAssertNil(view.animationFrameForTesting,
                     "paused (the default), a caption shows its finished state — never an empty frame")

        canvas.animatesCaptions = true
        let revealing = try XCTUnwrap(view.animationFrameForTesting, "playing: mid-reveal")
        XCTAssertLessThan(revealing.rangeAlphas.last?.alpha ?? 1, 1)

        canvas.animatesCaptions = false
        XCTAssertNil(view.animationFrameForTesting)
    }

    func testAFreshTemplateOpensPausedWithItsCaptionsAtRest() throws {
        let viewModel = VideoEditorViewModel(template: VideoTemplateCatalog.titleGrid)
        let editor = VideoEditorViewController(viewModel: viewModel)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = editor
        window.isHidden = false
        windows.append(window)
        window.layoutIfNeeded()

        let canvas = try XCTUnwrap(editor.view.recursiveSubviews.compactMap { $0 as? VideoCanvasView }.first)
        XCTAssertFalse(canvas.animatesCaptions)
        let titles = canvas.textOverlayViewsForTesting.compactMap { $0 as? TextOverlayView }
        XCTAssertEqual(titles.count, 2)
        XCTAssertTrue(titles.allSatisfy { !$0.isHidden && $0.animationFrameForTesting == nil },
                      "the fading title is fully visible at 0:00 on a paused preview")
    }

    // MARK: - Style presets stay readable

    func testALabelBoxTurnsWhiteTextToInkOnCream() {
        let white = TextOverlay(text: "hi", colorHex: "#FFFFFF")
        let boxed = VideoEditorViewController.applying(.box, to: white)
        XCTAssertEqual(boxed.style.kind, .box)
        XCTAssertFalse(UIColor(hex: boxed.colorHex).isLight, "ink text…")
        XCTAssertTrue(UIColor(hex: boxed.style.colorHex).isLight, "…on a light label")
    }

    func testAPaintedStyleNeverMatchesItsText() {
        for kind in [TextStyle.Kind.pill, .highlight] {
            for text in ["#FFFFFF", "#111111"] {
                let styled = VideoEditorViewController.applying(kind, to: TextOverlay(text: "hi", colorHex: text))
                XCTAssertNotEqual(UIColor(hex: styled.colorHex).isLight,
                                  UIColor(hex: styled.style.colorHex).isLight,
                                  "\(kind) under \(text) text")
            }
        }
    }

    func testTheBoxIsASnugLabelNotACapsule() throws {
        let overlay = TextOverlay(text: "Label", fontSize: 60,
                                  style: TextStyle(kind: .box, colorHex: "#FFFFFF", width: 30))
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 300)
        let box = try XCTUnwrap(TextRendering.backgroundRect(for: overlay, in: frame, fontScale: 1))
        XCTAssertLessThan(box.cornerRadius, box.rect.height / 4, "barely rounded")

        var pill = overlay
        pill.style.kind = .pill
        let capsule = try XCTUnwrap(TextRendering.backgroundRect(for: pill, in: frame, fontScale: 1))
        XCTAssertGreaterThan(capsule.cornerRadius, box.cornerRadius)
    }
}
