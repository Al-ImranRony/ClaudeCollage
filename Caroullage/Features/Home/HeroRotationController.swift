//
//  HeroRotationController.swift
//  Caroullage
//
//  Step 07 — the hero card's auto-advance brain, kept off UIKit so it is
//  testable with an injected scheduler. Reduce Motion turns auto-advance off
//  entirely (swiping still works); pause/resume brackets user touches so a
//  manual interaction doesn't fight the timer.
//

import Foundation

@MainActor
final class HeroRotationController {

    /// Installs a repeating tick and returns a cancellation closure. Production
    /// code passes a real timer; tests pass a fake that captures the handler
    /// and lets the test fire it manually, so no real time ever elapses.
    typealias Scheduler = (@escaping () -> Void) -> () -> Void

    /// Fires with the new current page whenever auto-advance moves it.
    var onAdvance: ((Int) -> Void)?

    private let pageCount: Int
    private let reduceMotion: () -> Bool
    private let scheduler: Scheduler
    private var cancel: (() -> Void)?
    private var paused = false
    private var currentPage = 0

    init(
        pageCount: Int,
        reduceMotion: @escaping () -> Bool,
        scheduler: @escaping Scheduler
    ) {
        self.pageCount = pageCount
        self.reduceMotion = reduceMotion
        self.scheduler = scheduler
    }

    /// Bridges a plain closure to `Timer`'s `@Sendable` block API.
    ///
    /// `start()` forms `handler` inside a `@MainActor` method, so per SE-0420
    /// closure-isolation inference `handler` itself becomes `@MainActor`-
    /// isolated — and an isolated closure is not `Sendable`. `Timer(
    /// timeInterval:repeats:block:)`'s block parameter IS `@Sendable`, so
    /// capturing `handler` directly inside it is rejected
    /// at compile time (this is exactly the closure-isolation trap that bit
    /// the export path's PhotoKit callback, see
    /// swift6-dispatchworkitem-mainactor-trap — except here the fix is
    /// available because, unlike that callback, a timer registered on the
    /// main run loop genuinely only ever fires on the main thread).
    ///
    /// Storing `handler` as a property on this `@unchecked Sendable` box
    /// sidesteps the capture check (only the box, not the closure, crosses
    /// into the `@Sendable` timer block), while `fire()` still calls it
    /// through `assumeIsolated`, which is sound for the same main-run-loop
    /// reason.
    private final class MainActorTimerBox: @unchecked Sendable {
        private let handler: () -> Void
        init(handler: @escaping () -> Void) { self.handler = handler }
        func fire() { MainActor.assumeIsolated { handler() } }
    }

    /// The production scheduler: a repeating timer on the main run loop,
    /// registered in `.common` mode (not the `scheduledTimer` convenience,
    /// which registers `.default` only) so it keeps firing while the main
    /// run loop is in `.tracking` mode — i.e. while the user has a finger on
    /// any scroll view. The Home screen scrolls vertically and hosts
    /// horizontally-scrolling strips alongside the hero card, so without
    /// `.common` the hero would visibly freeze on every scroll gesture.
    static func timerScheduler(interval: TimeInterval = 4) -> Scheduler {
        { handler in
            let box = MainActorTimerBox(handler: handler)
            let timer = Timer(timeInterval: interval, repeats: true) { _ in
                box.fire()
            }
            RunLoop.main.add(timer, forMode: .common)
            return { timer.invalidate() }
        }
    }

    /// Starts auto-advance. A no-op if already running, if there's nothing to
    /// advance between (0 or 1 pages), or if Reduce Motion is on. Clears any
    /// pause left over from a previous run so a stop/start cycle (e.g. the
    /// view disappearing mid-touch, before the matching `resume()` arrives)
    /// can't leave a freshly-started rotation silently paused forever.
    func start() {
        guard cancel == nil, pageCount > 1, !reduceMotion() else { return }
        paused = false
        cancel = scheduler { [weak self] in self?.tick() }
    }

    /// Stops auto-advance and tears down the underlying scheduler. Safe to
    /// call whether or not `start()` ran.
    func stop() {
        cancel?()
        cancel = nil
    }

    /// Safety net: `Timer`/the scheduler's underlying resource is retained by
    /// the run loop independently of this controller, so a caller that
    /// forgets to call `stop()` before releasing its last reference would
    /// otherwise leak a live repeating timer for the rest of the app's
    /// lifetime.
    ///
    /// A plain `deinit` on a `@MainActor` class is still *nonisolated* under
    /// Swift 6 — it can run on whatever thread drops the last reference, so
    /// the compiler rejects touching `cancel` (a non-`Sendable` closure)
    /// from it. `isolated deinit` (SE-0371) opts in to hopping to the main
    /// actor before the body runs, which is what actually makes this safe.
    isolated deinit {
        cancel?()
    }

    /// Suppresses advances without tearing down the scheduler — cheaper than
    /// stop/start around a brief user touch, and avoids reinstalling a timer
    /// (which would reset its interval) for every finger-down/up.
    func pause() { paused = true }
    func resume() { paused = false }

    /// The user swiped manually; future auto-advances continue from where
    /// they landed rather than snapping back to the pre-swipe page.
    func noteUserMoved(to page: Int) { currentPage = page }

    private func tick() {
        guard !paused, pageCount > 1, !reduceMotion() else { return }
        currentPage = (currentPage + 1) % pageCount
        onAdvance?(currentPage)
    }
}
