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
}
