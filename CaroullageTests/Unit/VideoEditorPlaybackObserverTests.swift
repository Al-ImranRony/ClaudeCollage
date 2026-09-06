//
//  VideoEditorPlaybackObserverTests.swift
//  CaroullageTests
//
//  The playback-time observer that drives the canvas's timed-text preview (see
//  `VideoEditorViewController.startObservingPlaybackTime`) must survive a
//  `viewWillDisappear` that doesn't lead to an actual pop — most notably the
//  system interactive back-swipe. `isMovingFromParent` turns true as soon as a
//  pop TRANSITION BEGINS, not only once it commits, so tearing the observer
//  down in `viewWillDisappear` (guarded by that flag, as the code used to)
//  drops it the moment the user starts a back-swipe — including one they then
//  cancel, leaving the VC on screen with nothing left to re-arm it and the
//  caption-timing preview frozen for the rest of that screen's life.
//
//  Driving a *cancelled* interactive swipe for real needs a live gesture
//  recognizer and animation, which a headless unit test can't do. The defect
//  is still directly reproducible, though: `isMovingFromParent` is only
//  meaningful from *inside* an appearance-transition callback that UIKit
//  itself drives via `beginAppearanceTransition`/`endAppearanceTransition` —
//  calling `viewWillDisappear` directly (without that machinery) never sets it
//  (confirmed empirically; UIKit also logs "calling -viewWillDisappear:
//  directly ... is not supported" if you try). So this reproduces the exact
//  shape of a cancelled pop with the same public APIs a container view
//  controller (which is what UINavigationController is) uses under the hood:
//    1. `willMove(toParent: nil)` marks the pending removal.
//    2. `beginAppearanceTransition(false, animated:)` fires `viewWillDisappear`
//       — this is the moment `isMovingFromParent` reads `true`, matching a
//       back-swipe that has begun but not committed.
//    3. Cancelling never calls `endAppearanceTransition()` for that
//       disappearance. Instead the reverse (appearing) transition begins —
//       `viewDidDisappear` is *never* reached, exactly like a real cancelled
//       swipe (UIKit replays `viewWillAppear`/`viewDidAppear` instead).
//

import UIKit
import XCTest
@testable import Caroullage

@MainActor
final class VideoEditorPlaybackObserverTests: XCTestCase {

    private var windows: [UIWindow] = []

    override func tearDown() async throws {
        await MainActor.run { windows.removeAll() }
        try await super.tearDown()
    }

    /// Embeds the editor as a real child of `container` — the same manual
    /// containment a navigation controller performs for a push — so
    /// `viewDidLoad`/`viewWillAppear`/`viewDidAppear` all run for real.
    private func makeEditorInContainer() -> (container: UIViewController, editor: VideoEditorViewController) {
        let viewModel = VideoEditorViewModel(canvasSize: CGSize(width: 1080, height: 1080))
        let editor = VideoEditorViewController(viewModel: viewModel)
        let container = UIViewController()

        container.addChild(editor)
        editor.view.frame = container.view.bounds
        container.view.addSubview(editor.view)
        editor.didMove(toParent: container)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = container
        windows.append(window)
        window.isHidden = false
        window.layoutIfNeeded()

        return (container, editor)
    }

    func testACancelledBackSwipeLeavesThePlaybackObserverLive() {
        let (container, editor) = makeEditorInContainer()
        XCTAssertTrue(editor.isObservingPlaybackTimeForTesting,
                      "Precondition: viewDidLoad registers the observer")

        // The system interactive back-swipe begins: this is the real path to
        // `viewWillDisappear` seeing `isMovingFromParent == true`, before the
        // pop ever commits.
        editor.willMove(toParent: nil)
        editor.beginAppearanceTransition(false, animated: true)

        // The user cancels the swipe: the disappearance is never finished
        // (`endAppearanceTransition` is not called for it, so `viewDidDisappear`
        // never fires) — instead the reverse, appearing transition begins, and
        // the VC is re-settled with its existing parent.
        editor.beginAppearanceTransition(true, animated: true)
        editor.endAppearanceTransition()
        editor.didMove(toParent: container)

        XCTAssertTrue(editor.isObservingPlaybackTimeForTesting,
                      "A cancelled swipe must not freeze the caption-timing preview")
    }

    func testAGenuinePopStillRemovesThePlaybackObserver() {
        // The fix must not turn into a leak: once the pop actually completes,
        // the observer (and the player it would otherwise keep alive) must go.
        let (_, editor) = makeEditorInContainer()

        editor.willMove(toParent: nil)
        editor.beginAppearanceTransition(false, animated: false)
        editor.view.removeFromSuperview()
        editor.endAppearanceTransition()
        editor.removeFromParent()

        XCTAssertFalse(editor.isObservingPlaybackTimeForTesting,
                       "A completed pop must still release the observer")
    }
}
