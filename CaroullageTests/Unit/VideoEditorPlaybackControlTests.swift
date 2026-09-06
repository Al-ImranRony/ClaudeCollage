//
//  VideoEditorPlaybackControlTests.swift
//  CaroullageTests
//
//  Plan-defect fix: Task 5's `VideoTimeline` API had no play callback and no
//  `isPlaying` field, and Task 6 then removed the toolbar Play button and made
//  the preview autoplay continuously — leaving no way to pause the video
//  editor's preview anywhere on screen. `VideoTimeline.onTogglePlayback` /
//  `VideoTimelineModel.isPlaying` close the plan gap; `VideoEditorViewController
//  .setPlaying(_:)` is the single choke point that keeps the timeline's icon
//  honest about what `player` is actually doing, including across a
//  composition rebuild that must not resume playback for someone who
//  deliberately paused (Task 6's regression: it used to call `player.play()`
//  unconditionally).
//
//  Exercises the real `VideoEditorViewController` embedded in a real window —
//  mirrors `VideoEditorPlaybackObserverTests`/`VideoEditorRailTests`' own
//  setup — against a REAL (if tiny) decodable video fixture, so
//  `rebuildComposition()`'s full async path (debounce + `buildBundle()` +
//  seek) actually runs end to end, rather than short-circuiting on the
//  `try?` failure a fake, never-decoded asset would hit immediately.
//

import AVFoundation
import CoreGraphics
import UIKit
import XCTest
@testable import Caroullage

@MainActor
final class VideoEditorPlaybackControlTests: XCTestCase {

    private var windows: [UIWindow] = []
    private var scratch: [URL] = []

    override func tearDown() async throws {
        for url in scratch { try? FileManager.default.removeItem(at: url) }
        scratch = []
        await MainActor.run { windows.removeAll() }
        try await super.tearDown()
    }

    // MARK: - A real, decodable fixture

    private func tempURL(ext: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoEditorPlaybackControlTest-\(UUID().uuidString).\(ext)")
        scratch.append(url)
        return url
    }

    private func solidImage(_ side: Int, r: UInt8, g: UInt8, b: UInt8) -> CGImage {
        let bpr = side * 4
        var px = [UInt8](repeating: 0, count: bpr * side)
        for p in stride(from: 0, to: px.count, by: 4) {
            px[p] = r; px[p + 1] = g; px[p + 2] = b; px[p + 3] = 255
        }
        let ctx = CGContext(data: &px, width: side, height: side, bitsPerComponent: 8, bytesPerRow: bpr,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    /// A real, decodable solid-colour clip via the slice-1 slideshow writer
    /// (same technique `VideoCompositionTests`/`ExportServiceTests` use) — long
    /// enough that a rebuild mid-playback has somewhere to seek back to, short
    /// enough to keep the suite fast.
    private func makeRealVideoAsset() async throws -> AVAsset {
        let url = tempURL(ext: "mp4")
        try await VideoComposer().renderSlideshow(
            frames: [solidImage(64, r: 200, g: 40, b: 40)],
            size: CGSize(width: 64, height: 64),
            secondsPerFrame: 0.5,
            to: url)
        return AVURLAsset(url: url)
    }

    // MARK: - Editor setup

    private func makeEditor(asset: AVAsset) -> VideoEditorViewController {
        let viewModel = VideoEditorViewModel(canvasSize: CGSize(width: 1080, height: 1080))
        viewModel.setVideo(assetID: UUID(), asset: asset, forCellAt: 0)
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

    /// AVPlayer's `timeControlStatus` can sit at `.waitingToPlayAtSpecifiedRate`
    /// for a moment after `play()` even for a fully-local, already-loaded item —
    /// it settles to `.playing` asynchronously, not necessarily within the same
    /// run-loop turn. Polls instead of asserting immediately so the test isn't
    /// racing AVFoundation's own internal buffering state.
    private func waitUntil(
        timeout: TimeInterval = 3, _ condition: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    // MARK: - Tests

    func testTheEditorLoadsPausedRatherThanAutoplaying() async throws {
        let editor = makeEditor(asset: try await makeRealVideoAsset())
        await editor.waitForPendingRebuildForTesting()

        let tl = try timeline(in: editor)
        XCTAssertEqual(tl.playbackButtonForHitTesting.accessibilityLabel, "Play",
                       "A freshly loaded composition must start paused, not autoplaying — " +
                       "Task 7 needs a still frame to scrub against, which a continuously " +
                       "playing preview cannot offer.")
        XCTAssertFalse(editor.isPlayerPlayingForTesting)
    }

    func testTappingTheTimelinesPlaybackControlTogglesTheRealPlayer() async throws {
        let editor = makeEditor(asset: try await makeRealVideoAsset())
        await editor.waitForPendingRebuildForTesting()
        let tl = try timeline(in: editor)

        tl.simulatePlaybackTap()
        await waitUntil { editor.isPlayerPlayingForTesting }
        XCTAssertTrue(editor.isPlayerPlayingForTesting, "Tapping play must actually start the AVPlayer")
        XCTAssertEqual(tl.playbackButtonForHitTesting.accessibilityLabel, "Pause")

        tl.simulatePlaybackTap()
        await waitUntil { !editor.isPlayerPlayingForTesting }
        XCTAssertFalse(editor.isPlayerPlayingForTesting, "Tapping again must actually pause the AVPlayer")
        XCTAssertEqual(tl.playbackButtonForHitTesting.accessibilityLabel, "Play")
    }

    func testPausingSurvivesACompositionRebuild() async throws {
        let editor = makeEditor(asset: try await makeRealVideoAsset())
        await editor.waitForPendingRebuildForTesting()
        let tl = try timeline(in: editor)

        // Start playing, then deliberately pause.
        tl.simulatePlaybackTap()
        await waitUntil { editor.isPlayerPlayingForTesting }
        XCTAssertTrue(editor.isPlayerPlayingForTesting, "Precondition: now playing")
        tl.simulatePlaybackTap()
        await waitUntil { !editor.isPlayerPlayingForTesting }
        XCTAssertFalse(editor.isPlayerPlayingForTesting, "Precondition: now paused")

        // Any document edit triggers a rebuild — flip a plain (non-interactive)
        // per-cell control so `viewModel.onChanged` fires and `rebuildComposition`
        // reruns its full async path end to end.
        editor.viewModelForTesting.setLooping(false, forCellAt: 0)
        await editor.waitForPendingRebuildForTesting()

        XCTAssertFalse(editor.isPlayerPlayingForTesting,
                       "A rebuild must not resume playback for a user who deliberately paused")
        XCTAssertEqual(tl.playbackButtonForHitTesting.accessibilityLabel, "Play",
                       "The timeline's icon must not lie about the paused player")
    }

    func testPlayingSurvivesACompositionRebuildToo() async throws {
        // The other half of the same fix: a rebuild while genuinely playing
        // must keep playing, not over-correct into freezing on every edit.
        let editor = makeEditor(asset: try await makeRealVideoAsset())
        await editor.waitForPendingRebuildForTesting()
        let tl = try timeline(in: editor)

        tl.simulatePlaybackTap()
        await waitUntil { editor.isPlayerPlayingForTesting }
        XCTAssertTrue(editor.isPlayerPlayingForTesting, "Precondition: now playing")

        editor.viewModelForTesting.setLooping(false, forCellAt: 0)
        await editor.waitForPendingRebuildForTesting()
        await waitUntil { editor.isPlayerPlayingForTesting }

        XCTAssertTrue(editor.isPlayerPlayingForTesting,
                      "A rebuild must preserve an in-progress playback, not silently pause it")
        XCTAssertEqual(tl.playbackButtonForHitTesting.accessibilityLabel, "Pause")
    }
}
