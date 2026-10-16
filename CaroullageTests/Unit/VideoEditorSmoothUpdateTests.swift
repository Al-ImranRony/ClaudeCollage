//
//  VideoEditorSmoothUpdateTests.swift
//  CaroullageTests
//
//  The video editor's preview blinked on every edit — dragging a caption,
//  dropping a sticker, even selecting a clip. Every document change funnelled
//  through `viewModel.onChanged` into `rebuildComposition()`, which built a
//  brand-new `AVPlayerItem` and swapped it in; the player layer shows nothing
//  between losing the old item and drawing the new one's first frame. Yet the
//  preview composition carries no overlays at all (the canvas draws captions
//  and stickers as live views), so those rebuilds were pure cost.
//
//  These tests pin the contract at the player: an edit that cannot change what
//  the composition renders must leave the player's item alone, and an edit
//  that can must still replace it.
//

import AVFoundation
import CoreGraphics
import UIKit
import XCTest
@testable import Caroullage

@MainActor
final class VideoEditorSmoothUpdateTests: XCTestCase {

    private var windows: [UIWindow] = []
    private var scratch: [URL] = []

    override func tearDown() async throws {
        for url in scratch { try? FileManager.default.removeItem(at: url) }
        scratch = []
        windows.removeAll()
        try await super.tearDown()
    }

    // MARK: - Fixture (same technique as VideoEditorPlaybackControlTests)

    private func solidImage(_ side: Int) -> CGImage {
        let bpr = side * 4
        var px = [UInt8](repeating: 0, count: bpr * side)
        for p in stride(from: 0, to: px.count, by: 4) {
            px[p] = 40; px[p + 1] = 160; px[p + 2] = 90; px[p + 3] = 255
        }
        let ctx = CGContext(data: &px, width: side, height: side, bitsPerComponent: 8, bytesPerRow: bpr,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    private func makeRealVideoAsset() async throws -> AVAsset {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoEditorSmoothUpdateTest-\(UUID().uuidString).mp4")
        scratch.append(url)
        try await VideoComposer().renderSlideshow(
            frames: [solidImage(64)], size: CGSize(width: 64, height: 64),
            secondsPerFrame: 0.5, to: url)
        return AVURLAsset(url: url)
    }

    private func makeEditor() async throws -> VideoEditorViewController {
        let viewModel = VideoEditorViewModel(canvasSize: CGSize(width: 1080, height: 1080))
        viewModel.setVideo(assetID: UUID(), asset: try await makeRealVideoAsset(), forCellAt: 0)
        let editor = VideoEditorViewController(viewModel: viewModel)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = editor
        windows.append(window)
        window.isHidden = false
        window.layoutIfNeeded()
        await editor.waitForPendingRebuildForTesting()
        return editor
    }

    /// The item on screen once whatever rebuild an edit scheduled has landed.
    private func settledItem(_ editor: VideoEditorViewController) async throws -> AVPlayerItem {
        await editor.waitForPendingRebuildForTesting()
        return try XCTUnwrap(editor.currentPlayerItemForTesting, "the preview should have an item")
    }

    // MARK: - Edits that cannot change the composition

    func testAddingAndMovingACaptionLeavesThePlayersItemAlone() async throws {
        let editor = try await makeEditor()
        let before = try await settledItem(editor)

        let id = editor.addTextOverlayForTesting()
        var overlay = try XCTUnwrap(editor.viewModelForTesting.textOverlay(id: id))
        overlay.frameX += 0.1
        editor.viewModelForTesting.updateTextOverlayInteractive(overlay)
        editor.viewModelForTesting.commitInteractive()

        let after = try await settledItem(editor)
        XCTAssertTrue(before === after,
                      "a caption is drawn by a live view over the player — moving one must not " +
                      "rebuild the composition, whose item swap is the blink")
    }

    func testAddingAndMovingAStickerLeavesThePlayersItemAlone() async throws {
        let editor = try await makeEditor()
        let before = try await settledItem(editor)

        let id = editor.viewModelForTesting.addSticker(
            StickerOverlay(stickerID: "test.star", symbolName: "star.fill", colorHex: "#FFCC00"))
        var sticker = try XCTUnwrap(editor.viewModelForTesting.stickerOverlays.first { $0.id == id })
        sticker.centerX = 0.3
        editor.viewModelForTesting.updateStickerInteractive(sticker)
        editor.viewModelForTesting.commitInteractive()

        let after = try await settledItem(editor)
        XCTAssertTrue(before === after, "moving a sticker must not swap the player's item")
    }

    func testSelectingAClipLeavesThePlayersItemAlone() async throws {
        let editor = try await makeEditor()
        let before = try await settledItem(editor)

        editor.selectClipForTesting(0)
        editor.clearSelectionForTesting()

        let after = try await settledItem(editor)
        XCTAssertTrue(before === after, "selection is chrome, not composition")
    }

    func testUndoingACaptionMoveLeavesThePlayersItemAlone() async throws {
        let editor = try await makeEditor()
        _ = editor.addTextOverlayForTesting()
        let before = try await settledItem(editor)

        editor.viewModelForTesting.undo()

        let after = try await settledItem(editor)
        XCTAssertTrue(before === after, "undoing an overlay-only step must not rebuild the video")
    }

    // MARK: - Edits that do change it

    func testAClipControlStillRebuildsTheComposition() async throws {
        let editor = try await makeEditor()
        let before = try await settledItem(editor)

        editor.viewModelForTesting.setLooping(false, forCellAt: 0)

        let after = try await settledItem(editor)
        XCTAssertFalse(before === after, "a per-cell control changes what plays, so it must rebuild")
    }

    func testALayoutChangeStillRebuildsTheComposition() async throws {
        let editor = try await makeEditor()
        let before = try await settledItem(editor)

        editor.viewModelForTesting.changeLayout(.grid(.fourSquare))

        let after = try await settledItem(editor)
        XCTAssertFalse(before === after, "a new layout is a new composition")
    }

    // MARK: - Holding the frame over a swap

    private func waitUntil(timeout: TimeInterval = 3, _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// The whole freeze-frame mechanism rests on reading the frame on screen;
    /// if that read comes back empty, every swap still blinks and every layout
    /// change snaps. Checked against a real player drawing a real composition.
    func testTheFrameOnScreenCanBeReadBackWhilePaused() async throws {
        let editor = try await makeEditor()
        let item = try await settledItem(editor)
        await waitUntil { item.status != .unknown }
        try XCTSkipIf(item.status == .failed,
                      "this runtime cannot display a video composition (iOS 27.0 simulator)")
        let canvas = try XCTUnwrap(editor.view.recursiveSubviews.compactMap { $0 as? VideoCanvasView }.first)
        await waitUntil { canvas.playerLayer.isReadyForDisplay }

        let frame = VideoFreezeFrameView.currentFrame(of: canvas.playerLayer)

        XCTAssertNotNil(frame, "paused: layer buffer \(canvas.playerLayer.displayedPixelBuffer() != nil), " +
                        "tap outputs \(item.outputs.count)")
    }

    /// `AVPlayerLayer` draws the video in a private sublayer of the canvas's
    /// backing layer. A held frame placed at subview index 0 sat UNDER it: a
    /// layout glide then moved its pieces invisibly behind the old video.
    func testTheHeldFrameSitsAboveTheVideoAndBelowTheSlots() async throws {
        let editor = try await makeEditor()
        let item = try await settledItem(editor)
        await waitUntil { item.status != .unknown }
        try XCTSkipIf(item.status == .failed,
                      "this runtime cannot display a video composition (iOS 27.0 simulator)")
        let canvas = try XCTUnwrap(editor.view.recursiveSubviews.compactMap { $0 as? VideoCanvasView }.first)
        await waitUntil { canvas.playerLayer.isReadyForDisplay }

        editor.viewModelForTesting.changeLayout(.grid(.fourSquare))

        let freeze = try XCTUnwrap(canvas.freezeFrameViewForTesting)
        XCTAssertTrue(freeze.isHolding, "a layout change holds the frame for its glide")
        let sublayers = canvas.layer.sublayers ?? []
        let viewLayers = Set(canvas.subviews.map { ObjectIdentifier($0.layer) })
        let freezeIndex = try XCTUnwrap(sublayers.firstIndex { $0 === freeze.layer })
        for (index, sublayer) in sublayers.enumerated() where !viewLayers.contains(ObjectIdentifier(sublayer)) {
            XCTAssertLessThan(index, freezeIndex, "the player's own video layer must be under the held frame")
        }
        // The chrome lives in the canvas's strip (layout space for a pan), so
        // what is ordered against the held frame is its canvas-level ancestor.
        var chromeHost: UIView = canvas.cellChromeViewsForTesting[0]
        while let parent = chromeHost.superview, parent !== canvas { chromeHost = parent }
        let chromeIndex = try XCTUnwrap(sublayers.firstIndex { $0 === chromeHost.layer })
        XCTAssertLessThan(freezeIndex, chromeIndex, "the slot chrome stays on top of the held frame")
    }

    func testAnOverlayEditDoesNotSwallowAPendingCompositionRebuild() async throws {
        // The gate must compare against what was last SCHEDULED, not cancel a
        // rebuild that is still in its debounce when an overlay edit lands.
        let editor = try await makeEditor()
        let before = try await settledItem(editor)

        editor.viewModelForTesting.setLooping(false, forCellAt: 0)
        _ = editor.addTextOverlayForTesting()

        let after = try await settledItem(editor)
        XCTAssertFalse(before === after, "the looping change must still reach the player")
    }
}
