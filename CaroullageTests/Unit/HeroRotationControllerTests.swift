//
//  HeroRotationControllerTests.swift
//  CaroullageTests
//
//  Step 07 — the hero's auto-advance timing logic, tested with an injected
//  scheduler so zero real time elapses: the test drives ticks by calling a
//  captured closure, never by sleeping.
//

import XCTest
@testable import Caroullage

@MainActor
final class HeroRotationControllerTests: XCTestCase {

    /// Builds a controller wired to a fake scheduler, plus a `tick` closure the
    /// test calls to simulate the scheduler firing. `installCount` counts how
    /// many times the controller actually installed a scheduler (used to check
    /// `start()` idempotency and Reduce-Motion/single-page suppression).
    private func makeController(count: Int, reduceMotion: Bool = false)
        -> (controller: HeroRotationController, tick: () -> Void, installCount: () -> Int, advanced: () -> [Int])
    {
        var handler: (() -> Void)?
        var installs = 0
        var advances: [Int] = []

        let controller = HeroRotationController(
            pageCount: count,
            reduceMotion: { reduceMotion },
            scheduler: { newHandler in
                installs += 1
                handler = newHandler
                return { handler = nil }
            })
        controller.onAdvance = { advances.append($0) }

        return (
            controller,
            { handler?() },
            { installs },
            { advances }
        )
    }

    func testAdvancesAndWraps() {
        let (controller, tick, _, advanced) = makeController(count: 3)
        controller.start()
        tick(); tick(); tick(); tick()
        XCTAssertEqual(advanced(), [1, 2, 0, 1])
    }

    func testPauseSuppressesAdvanceResumeRestoresIt() {
        let (controller, tick, _, advanced) = makeController(count: 3)
        controller.start()
        controller.pause()
        tick()
        XCTAssertEqual(advanced(), [], "paused: a tick produces nothing")

        controller.resume()
        tick()
        XCTAssertEqual(advanced(), [1], "resumed: the next tick advances")
    }

    func testReduceMotionNeverAutoAdvances() {
        let (controller, tick, installCount, advanced) = makeController(count: 3, reduceMotion: true)
        controller.start()
        tick()
        XCTAssertEqual(advanced(), [], "reduce motion: start() + a tick produces nothing")
        XCTAssertEqual(installCount(), 0, "reduce motion: start() shouldn't even install a scheduler")
    }

    func testManualSwipeResyncsThePage() {
        let (controller, tick, _, advanced) = makeController(count: 4)
        controller.start()
        controller.noteUserMoved(to: 2)
        tick()
        XCTAssertEqual(advanced(), [3], "advance continues from the swiped-to page, not the old one")
    }

    func testSinglePageNeverAdvances() {
        let (controller, tick, installCount, advanced) = makeController(count: 1)
        controller.start()
        tick()
        XCTAssertEqual(advanced(), [], "a single page has nowhere to advance to")
        XCTAssertEqual(installCount(), 0, "a single page shouldn't install a scheduler at all")
    }

    func testZeroPagesNeverAdvances() {
        let (controller, tick, installCount, advanced) = makeController(count: 0)
        controller.start()
        tick()
        XCTAssertEqual(advanced(), [], "zero pages: nothing to advance to")
        XCTAssertEqual(installCount(), 0, "zero pages shouldn't install a scheduler at all")
    }

    func testStopPreventsFurtherAdvances() {
        // stop() must cancel the scheduler so a tick fired after stop() (e.g. a
        // race with a real timer's last queued fire) is inert.
        let (controller, tick, _, advanced) = makeController(count: 3)
        controller.start()
        tick()
        controller.stop()
        tick()
        XCTAssertEqual(advanced(), [1], "the tick after stop() is dropped")
    }

    func testStartIsIdempotent() {
        // Calling start() twice must not install a second scheduler — that
        // would double-advance on every real tick.
        let (controller, tick, installCount, advanced) = makeController(count: 3)
        controller.start()
        controller.start()
        XCTAssertEqual(installCount(), 1, "a second start() must not install a second scheduler")
        tick()
        XCTAssertEqual(advanced(), [1], "only one advance per tick even after a redundant start()")
    }

    func testStopStartCycleClearsAStalePause() {
        // Failure sequence this guards against: start() -> pause() (a touch
        // begins) -> stop() (the view disappears mid-touch, e.g. the user
        // navigates away, so the matching resume() never arrives) -> start()
        // (the view reappears). Without a reset, paused stays true forever
        // and the reinstalled timer ticks into a silent no-op for the rest
        // of the session.
        let (controller, tick, _, advanced) = makeController(count: 3)
        controller.start()
        controller.pause()
        controller.stop()
        controller.start()
        tick()
        XCTAssertEqual(advanced(), [1], "a fresh start() must not inherit a stale paused state")
    }

    func testDeinitCancelsTheScheduler() {
        // Timer.scheduledTimer/RunLoop retain the underlying timer
        // independently of this controller, so if a caller drops its last
        // reference without calling stop(), deinit must still tear it down
        // or the timer leaks and fires for the rest of the app's lifetime.
        var cancelled = false
        var controller: HeroRotationController? = HeroRotationController(
            pageCount: 3,
            reduceMotion: { false },
            scheduler: { _ in { cancelled = true } })
        controller?.start()
        XCTAssertFalse(cancelled, "the scheduler shouldn't be cancelled while the controller is alive")

        controller = nil
        XCTAssertTrue(cancelled, "deinit must cancel the scheduler")
    }
}
