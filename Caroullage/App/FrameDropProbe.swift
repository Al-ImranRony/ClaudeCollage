//
//  FrameDropProbe.swift
//  Caroullage
//
//  Debug-only. The simulator does not report XCTest's hitch metrics (they need
//  a device), so the scroll-performance suite measures dropped frames itself:
//  a display link on the main run loop, in every mode, totals how far each
//  frame landed past its deadline. Anything that blocks the main thread — a
//  synchronous render, a lazy image decode, a layout storm — delays the next
//  tick and shows up here as hitch time.
//
//  It also SCROLLS, because XCUITest cannot be in the room while it measures:
//  every synthesized swipe first snapshots the whole accessibility tree on the
//  main thread, and that snapshot — not the app — dominated a profile of
//  swipe-driven runs. So the test taps the probe once; the probe drives the
//  screen's main scroll view down and back up at fling speed by itself, counts
//  only the frames inside that drive, and publishes one result string as the
//  probe's accessibility value for the test to read once at the end.
//
//  Installed only under `-FrameProbe`; compiled out of Release.
//

#if DEBUG
import UIKit

@MainActor
final class FrameDropProbe {

    static let shared = FrameDropProbe()

    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private let trigger = UIButton(type: .custom)

    // The current drive.
    private weak var target: UIScrollView?
    private var phase: Phase = .idle
    private var phaseStart: CFTimeInterval = 0
    private var startOffset: CGFloat = 0
    private var endOffset: CGFloat = 0
    private var stats: [Phase: (hitch: Double, severe: Int, frames: Int)] = [:]

    private enum Phase: Hashable { case idle, down, rest, up }

    /// Points per second: a brisk fling, held for the whole drive.
    private static let speed: CGFloat = 3000

    func install(in window: UIWindow) {
        guard link == nil else { return }
        trigger.frame = CGRect(x: 0, y: window.bounds.midY, width: 30, height: 30)
        trigger.alpha = 0.02
        trigger.backgroundColor = .black
        trigger.accessibilityIdentifier = "frameDropProbe"
        trigger.accessibilityValue = "idle"
        trigger.addAction(UIAction { [weak self] _ in self?.startDrive() }, for: .touchUpInside)
        window.addSubview(trigger)

        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    // MARK: - Driving

    private func startDrive() {
        guard phase == .idle, let window = trigger.window,
              let scrollView = Self.mainScrollView(in: window) else {
            trigger.accessibilityValue = "error=no-scroll-view"
            return
        }
        target = scrollView
        stats = [:]
        trigger.accessibilityValue = "running"
        let top = -scrollView.adjustedContentInset.top
        let bottom = max(top, scrollView.contentSize.height + scrollView.adjustedContentInset.bottom
                         - scrollView.bounds.height)
        scrollView.setContentOffset(CGPoint(x: 0, y: top), animated: false)
        begin(.down, from: top, to: bottom)
    }

    private func begin(_ next: Phase, from: CGFloat, to: CGFloat) {
        phase = next
        phaseStart = CACurrentMediaTime()
        startOffset = from
        endOffset = to
    }

    /// The largest vertically-scrolling, on-screen scroll view: Home's page or
    /// a tab's grid — never a horizontal strip.
    private static func mainScrollView(in window: UIWindow) -> UIScrollView? {
        var best: (UIScrollView, CGFloat)?
        func visit(_ view: UIView) {
            if let scroll = view as? UIScrollView, scroll.window != nil, !scroll.isHidden,
               scroll.contentSize.height > scroll.bounds.height + 200 {
                let frame = scroll.convert(scroll.bounds, to: window).intersection(window.bounds)
                let area = frame.width * frame.height
                if area > (best?.1 ?? 0) { best = (scroll, area) }
            }
            view.subviews.forEach(visit)
        }
        visit(window)
        return best?.0
    }

    // MARK: - Measuring

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        defer { lastTimestamp = now }

        if phase != .idle, lastTimestamp > 0 {
            let expected = max(link.duration, 1.0 / 120)
            let late = (now - lastTimestamp) - expected
            var entry = stats[phase] ?? (0, 0, 0)
            entry.frames += 1
            // Half a frame of slack: display-link jitter is not a hitch.
            if late > expected * 0.5 {
                entry.hitch += late * 1000
                if late > 0.05 { entry.severe += 1 }
            }
            stats[phase] = entry
        }
        advanceDrive()
    }

    private func advanceDrive() {
        guard let target, phase != .idle else { return }
        let elapsed = CACurrentMediaTime() - phaseStart
        switch phase {
        case .down, .up:
            let distance = endOffset - startOffset
            let duration = abs(distance) / Self.speed
            let progress = duration > 0 ? min(elapsed / duration, 1) : 1
            target.contentOffset.y = startOffset + distance * progress
            guard progress >= 1 else { return }
            if phase == .down {
                begin(.rest, from: endOffset, to: endOffset)
            } else {
                finish()
            }
        case .rest:
            if elapsed > 0.5 { begin(.up, from: startOffset, to: -target.adjustedContentInset.top) }
        case .idle:
            break
        }
    }

    private func finish() {
        phase = .idle
        func part(_ name: String, _ p: Phase) -> String {
            let s = stats[p] ?? (0, 0, 0)
            return String(format: "%@HitchMs=%.1f %@Severe=%d %@Frames=%d", name, s.hitch, name, s.severe, name, s.frames)
        }
        trigger.accessibilityValue = "done " + part("down", .down) + " " + part("up", .up)
    }
}
#endif
