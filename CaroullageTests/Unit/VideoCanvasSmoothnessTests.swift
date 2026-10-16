//
//  VideoCanvasSmoothnessTests.swift
//  CaroullageTests
//
//  The canvas half of "the preview must not blink or snap": overlay views keep
//  their identity across updates (so a change can animate from where the view
//  was, and a sticker under the finger is never torn down mid-drag), slot
//  chrome survives a layout change, and `VideoFreezeFrameView` holds, morphs
//  and releases on the rules the view controller relies on.
//

import CoreGraphics
import UIKit
import XCTest
@testable import Caroullage

@MainActor
final class VideoCanvasOverlayIdentityTests: XCTestCase {

    private func makeCanvas() -> (VideoCanvasView, UIWindow) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        let canvas = VideoCanvasView(frame: window.bounds)
        window.addSubview(canvas)
        window.isHidden = false
        canvas.configure(canvasSize: CGSize(width: 1080, height: 1080),
                         cellFrames: [CGRect(x: 0, y: 0, width: 1080, height: 1080)],
                         filled: [true], selectedIndex: nil)
        canvas.layoutIfNeeded()
        return (canvas, window)
    }

    private func sticker(_ x: Double) -> StickerOverlay {
        StickerOverlay(stickerID: "test.star", symbolName: "star.fill", colorHex: "#FFCC00",
                       center: CGPoint(x: x, y: 0.5))
    }

    func testAStickerKeepsItsViewWhenItMoves() {
        let (canvas, window) = makeCanvas()
        defer { window.isHidden = true }
        var overlay = sticker(0.3)
        canvas.updateStickerOverlays([overlay], selected: nil)
        let before = canvas.stickerOverlayViewsForTesting.first

        overlay.centerX = 0.6
        canvas.updateStickerOverlays([overlay], selected: nil)

        XCTAssertNotNil(before)
        XCTAssertTrue(canvas.stickerOverlayViewsForTesting.first === before,
                      "rebuilding the view on every change tore down the sticker under the finger")
    }

    func testDeletingAStickerLeavesTheOthersViewsInPlace() {
        let (canvas, window) = makeCanvas()
        defer { window.isHidden = true }
        let first = sticker(0.2)
        let second = sticker(0.7)
        canvas.updateStickerOverlays([first, second], selected: nil)
        let secondView = canvas.stickerOverlayViewsForTesting[1]

        canvas.updateStickerOverlays([second], selected: nil)

        XCTAssertEqual(canvas.stickerOverlayViewsForTesting.count, 1)
        XCTAssertTrue(canvas.stickerOverlayViewsForTesting[0] === secondView)
        XCTAssertEqual(canvas.stickerOverlayViewsForTesting[0].stickerID, second.id)
    }

    func testDeletingACaptionDoesNotHandItsViewToTheNextOne() {
        let (canvas, window) = makeCanvas()
        defer { window.isHidden = true }
        let first = TextOverlay(text: "One", frame: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.1))
        let second = TextOverlay(text: "Two", frame: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.1))
        canvas.updateTextOverlays([first, second])
        canvas.layoutIfNeeded()
        let secondView = canvas.textOverlayViewsForTesting[1]
        let secondFrame = secondView.frame

        canvas.updateTextOverlays([second])
        canvas.layoutIfNeeded()

        XCTAssertTrue(canvas.textOverlayViewsForTesting[0] === secondView,
                      "matched by position, the first caption's view would jump to the second's place")
        XCTAssertEqual(canvas.textOverlayViewsForTesting[0].frame, secondFrame)
    }

    func testARemovedOverlayStopsTakingTouchesAtOnce() {
        let (canvas, window) = makeCanvas()
        defer { window.isHidden = true }
        let overlay = sticker(0.5)
        canvas.updateStickerOverlays([overlay], selected: nil)
        canvas.layoutIfNeeded()
        let view = canvas.stickerOverlayViewsForTesting[0]
        let centre = view.center

        canvas.updateStickerOverlays([], selected: nil)

        XCTAssertFalse(view.isUserInteractionEnabled,
                       "a sticker fading out is no longer in the document and must not be draggable")
        XCTAssertFalse(canvas.hasInteractiveOverlay(at: centre))
    }

    func testALayoutChangeKeepsTheChromeOfTheSlotsBothLayoutsShare() {
        let (canvas, window) = makeCanvas()
        defer { window.isHidden = true }
        let size = CGSize(width: 1080, height: 1080)
        canvas.configure(canvasSize: size,
                         cellFrames: [CGRect(x: 0, y: 0, width: 540, height: 1080),
                                      CGRect(x: 540, y: 0, width: 540, height: 1080)],
                         filled: [true, false], selectedIndex: nil)
        let kept = canvas.cellChromeViewsForTesting

        canvas.configure(canvasSize: size,
                         cellFrames: [CGRect(x: 0, y: 0, width: 540, height: 540),
                                      CGRect(x: 540, y: 0, width: 540, height: 540),
                                      CGRect(x: 0, y: 540, width: 540, height: 540),
                                      CGRect(x: 540, y: 540, width: 540, height: 540)],
                         filled: [true, false, false, false], selectedIndex: nil, animated: true)
        canvas.layoutIfNeeded()

        let chrome = canvas.cellChromeViewsForTesting
        XCTAssertEqual(chrome.count, 4)
        XCTAssertTrue(chrome[0] === kept[0] && chrome[1] === kept[1],
                      "the shared slots' chrome glides to its new place instead of being rebuilt")
        XCTAssertEqual(chrome[3].frame.origin.x, 200, accuracy: 0.5)
        XCTAssertEqual(chrome[3].frame.origin.y, 200, accuracy: 0.5)
    }
}

@MainActor
final class VideoFreezeFrameViewTests: XCTestCase {

    private func image(_ width: Int = 100, _ height: Int = 100) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(UIColor.systemTeal.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    private func makeView() -> (VideoFreezeFrameView, UIWindow) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let view = VideoFreezeFrameView(frame: window.bounds)
        window.addSubview(view)
        window.isHidden = false
        return (view, window)
    }

    func testTheCropMapsViewPointsOntoTheFramesPixels() {
        let crop = VideoFreezeFrameView.cropRect(
            for: CGRect(x: 100, y: 0, width: 100, height: 200),
            videoRect: CGRect(x: 0, y: 0, width: 200, height: 200),
            imageSize: CGSize(width: 1080, height: 1080))
        XCTAssertEqual(crop, CGRect(x: 540, y: 0, width: 540, height: 1080))
    }

    func testTheCropHonoursALetterboxedVideoRect() {
        let crop = VideoFreezeFrameView.cropRect(
            for: CGRect(x: 0, y: 50, width: 200, height: 50),
            videoRect: CGRect(x: 0, y: 50, width: 200, height: 100),
            imageSize: CGSize(width: 400, height: 200))
        XCTAssertEqual(crop, CGRect(x: 0, y: 0, width: 400, height: 100))
    }

    func testTheCropOfARectOutsideTheVideoIsNil() {
        XCTAssertNil(VideoFreezeFrameView.cropRect(
            for: CGRect(x: 300, y: 300, width: 10, height: 10),
            videoRect: CGRect(x: 0, y: 0, width: 200, height: 200),
            imageSize: CGSize(width: 100, height: 100)))
    }

    func testHoldingShowsTheWholeFrame() {
        let (view, window) = makeView()
        defer { window.isHidden = true }
        view.hold(image(), videoRect: view.bounds)
        XCTAssertTrue(view.isHolding)
        XCTAssertTrue(view.isShowingFullFrameForTesting)
        XCTAssertFalse(view.isHidden)
    }

    func testHoldingNothingWhenNothingIsHeldStaysOut() {
        let (view, window) = makeView()
        defer { window.isHidden = true }
        view.hold(nil, videoRect: view.bounds)
        XCTAssertFalse(view.isHolding, "no frame to show means no cover, not an empty black one")
        XCTAssertTrue(view.isHidden)
    }

    func testTheHoldWaitsForTheNewItemThenFades() {
        let (view, window) = makeView()
        defer { window.isHidden = true }
        view.hold(image(), videoRect: view.bounds)
        var ready = false
        view.release { ready }

        view.tickForTesting()
        XCTAssertEqual(view.alpha, 1, "must not fade before the new item draws — that is the blink")

        ready = true
        view.tickForTesting()
        XCTAssertEqual(view.alpha, 0, accuracy: 0.001, "fades once the new item is drawing")
    }

    func testANewHoldCancelsAFadeInProgress() {
        let (view, window) = makeView()
        defer { window.isHidden = true }
        view.hold(image(), videoRect: view.bounds)
        view.release { true }
        view.tickForTesting()

        view.hold(image(), videoRect: view.bounds)

        XCTAssertEqual(view.alpha, 1)
        XCTAssertTrue(view.isHolding)
    }

    func testAMorphCutsOnePiecePerFilledSlotAndDropsRemovedOnes() {
        let (view, window) = makeView()
        defer { window.isHidden = true }
        view.morph(image(), videoRect: view.bounds,
                   from: [0: CGRect(x: 0, y: 0, width: 100, height: 200),
                          1: CGRect(x: 100, y: 0, width: 100, height: 200)],
                   to: [CGRect(x: 0, y: 0, width: 200, height: 200)],
                   duration: 0)
        XCTAssertTrue(view.isHolding)
        XCTAssertEqual(view.pieceCountForTesting, 1, "slot 1 is gone in the new layout")
        XCTAssertFalse(view.isShowingFullFrameForTesting)
    }

    func testAMorphWithNoFrameAndNothingHeldDoesNothing() {
        let (view, window) = makeView()
        defer { window.isHidden = true }
        view.morph(nil, videoRect: view.bounds,
                   from: [0: view.bounds], to: [view.bounds], duration: 0)
        XCTAssertFalse(view.isHolding)
    }

    // Review finding: pieces cut at the first layout tap used to outlive the
    // item that replaced them — browsing layouts while playing froze the
    // preview on that first frame.

    func testBeforeTheNewItemDrawsAFreshGrabDoesNotReplaceThePieces() {
        let (view, window) = makeView()
        defer { window.isHidden = true }
        let first = image()
        view.morph(first, videoRect: view.bounds, from: [0: view.bounds], to: [view.bounds], duration: 0)

        view.hold(image(), videoRect: view.bounds)   // the rebuild's swap, old item still drawing

        XCTAssertEqual(view.pieceCountForTesting, 1, "the pieces show the new layout; the player does not yet")
        XCTAssertTrue(view.frozenImageForTesting === first)
    }

    func testOnceTheNewItemDrawsAFreshHoldReplacesThePieces() {
        let (view, window) = makeView()
        defer { window.isHidden = true }
        view.morph(image(), videoRect: view.bounds, from: [0: view.bounds], to: [view.bounds], duration: 0)
        view.release { true }
        view.tickForTesting()                        // the layout's own item is drawing; fading

        let fresh = image()
        view.hold(fresh, videoRect: view.bounds)

        XCTAssertEqual(view.pieceCountForTesting, 0)
        XCTAssertTrue(view.isShowingFullFrameForTesting)
        XCTAssertTrue(view.frozenImageForTesting === fresh, "the old pieces must not pop back")
    }

    func testOnceTheNewItemDrawsTheNextLayoutChangeIsCutFromAFreshFrame() {
        let (view, window) = makeView()
        defer { window.isHidden = true }
        let halves = [0: CGRect(x: 0, y: 0, width: 100, height: 200),
                      1: CGRect(x: 100, y: 0, width: 100, height: 200)]
        view.morph(image(), videoRect: view.bounds, from: halves, to: [view.bounds], duration: 0)
        view.release { true }
        view.tickForTesting()

        let fresh = image()
        view.morph(fresh, videoRect: view.bounds, from: [0: view.bounds],
                   to: [halves[0]!, halves[1]!], duration: 0)

        XCTAssertTrue(view.frozenImageForTesting === fresh)
        XCTAssertEqual(view.pieceCountForTesting, 1)
    }

    func testAHoldNobodyReleasesStillLetsGo() {
        // A rebuild that stalls must not leave a still frame over live video.
        let (view, window) = makeView()
        defer { window.isHidden = true }
        view.morph(image(), videoRect: view.bounds, from: [0: view.bounds], to: [view.bounds], duration: 0)

        view.tickForTesting(secondsLater: 1)
        XCTAssertEqual(view.alpha, 1, "a rebuild takes a moment; that is not a stall")
        view.tickForTesting(secondsLater: VideoFreezeFrameView.watchdogTimeout + 0.1)
        XCTAssertEqual(view.alpha, 0, accuracy: 0.001)
    }

    func testAMorphReaimsPiecesAlreadyInFlight() {
        let (view, window) = makeView()
        defer { window.isHidden = true }
        let half = CGRect(x: 0, y: 0, width: 100, height: 200)
        view.morph(image(), videoRect: view.bounds, from: [0: half], to: [view.bounds], duration: 0)
        view.morph(nil, videoRect: view.bounds, from: [:], to: [half], duration: 0)
        XCTAssertEqual(view.pieceCountForTesting, 1, "the second change moves the same piece on")
    }
}
