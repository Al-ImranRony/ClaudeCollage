//
//  VideoTimelineTests.swift
//  CaroullageTests
//
//  The timeline's coordinate maths. Kept free of UIKit so the mapping between
//  seconds and points is pinned without a window — the same split that made
//  EditorStageGeometry testable.
//

import UIKit
import XCTest
@testable import Caroullage

final class VideoTimelineTests: XCTestCase {

    private let width: CGFloat = 300

    func testTimeZeroMapsToTheLeadingEdge() {
        XCTAssertEqual(
            VideoTimelineGeometry.x(forTime: 0, duration: 10, width: width), 0, accuracy: 0.01)
    }

    func testTheFullDurationMapsToTheTrailingEdge() {
        XCTAssertEqual(
            VideoTimelineGeometry.x(forTime: 10, duration: 10, width: width), 300, accuracy: 0.01)
    }

    func testTimeMapsProportionally() {
        XCTAssertEqual(
            VideoTimelineGeometry.x(forTime: 2.5, duration: 10, width: width), 75, accuracy: 0.01)
    }

    func testMappingIsInvertible() {
        let x = VideoTimelineGeometry.x(forTime: 3.75, duration: 10, width: width)
        XCTAssertEqual(
            VideoTimelineGeometry.time(forX: x, duration: 10, width: width), 3.75, accuracy: 0.001)
    }

    func testAZeroDurationDoesNotDivideByZero() {
        // An empty project has no clips. This must not produce NaN and poison a frame.
        let x = VideoTimelineGeometry.x(forTime: 5, duration: 0, width: width)
        XCTAssertFalse(x.isNaN)
        XCTAssertEqual(x, 0, accuracy: 0.01)
    }

    func testTimeIsClampedIntoTheComposition() {
        XCTAssertEqual(
            VideoTimelineGeometry.time(forX: -50, duration: 10, width: width), 0, accuracy: 0.001)
        XCTAssertEqual(
            VideoTimelineGeometry.time(forX: 900, duration: 10, width: width), 10, accuracy: 0.001)
    }

    func testAClipLaneRectSpansItsOwnWindow() {
        let rect = VideoTimelineGeometry.laneRect(
            start: 2, duration: 3, compositionDuration: 10,
            in: CGRect(x: 0, y: 0, width: width, height: 20))

        XCTAssertEqual(rect.minX, 60, accuracy: 0.01)
        XCTAssertEqual(rect.width, 90, accuracy: 0.01)
    }

    // MARK: - laneRect clipping (Task 7 feeds this live, uncommitted drag values)

    func testALaneStartingBeforeZeroClipsToTheVisiblePortion() {
        // A live drag can push a clip's start negative before it settles. The
        // rect must describe only the visible portion, clamped to the leading edge.
        let rect = VideoTimelineGeometry.laneRect(
            start: -2, duration: 3, compositionDuration: 10,
            in: CGRect(x: 0, y: 0, width: width, height: 20))

        XCTAssertEqual(rect.minX, 0, accuracy: 0.01)
        XCTAssertEqual(rect.width, 30, accuracy: 0.01)
    }

    func testALaneExtendingPastTheCompositionEndClipsToTheVisiblePortion() {
        let rect = VideoTimelineGeometry.laneRect(
            start: 8, duration: 5, compositionDuration: 10,
            in: CGRect(x: 0, y: 0, width: width, height: 20))

        XCTAssertEqual(rect.minX, 240, accuracy: 0.01)
        XCTAssertEqual(rect.width, 60, accuracy: 0.01)
    }

    func testALaneWhollyOutsideCollapsesToZeroWidthAtTheNearerEdge() {
        let rect = VideoTimelineGeometry.laneRect(
            start: 15, duration: 2, compositionDuration: 10,
            in: CGRect(x: 0, y: 0, width: width, height: 20))

        XCTAssertEqual(rect.minX, 300, accuracy: 0.01)
        XCTAssertEqual(rect.width, 0, accuracy: 0.01)
    }

    // MARK: - Degenerate sizes (a view has zero width before its first layout pass)

    func testTimeForXIsSafeForZeroDuration() {
        let time = VideoTimelineGeometry.time(forX: 150, duration: 0, width: width)
        XCTAssertFalse(time.isNaN)
        XCTAssertFalse(time.isInfinite)
        XCTAssertEqual(time, 0, accuracy: 0.001)
    }

    func testTimeForXIsSafeForZeroWidth() {
        let time = VideoTimelineGeometry.time(forX: 150, duration: 10, width: 0)
        XCTAssertFalse(time.isNaN)
        XCTAssertFalse(time.isInfinite)
        XCTAssertEqual(time, 0, accuracy: 0.001)
    }

    func testLaneRectIsSafeForZeroCompositionDuration() {
        // An empty composition has no duration yet.
        let rect = VideoTimelineGeometry.laneRect(
            start: 2, duration: 3, compositionDuration: 0,
            in: CGRect(x: 0, y: 0, width: width, height: 20))

        XCTAssertFalse(rect.minX.isNaN)
        XCTAssertFalse(rect.width.isNaN)
        XCTAssertFalse(rect.minX.isInfinite)
        XCTAssertFalse(rect.width.isInfinite)
        XCTAssertEqual(rect.width, 0, accuracy: 0.01)
    }

    func testLaneRectIsSafeForZeroWidthBounds() {
        let rect = VideoTimelineGeometry.laneRect(
            start: 2, duration: 3, compositionDuration: 10,
            in: CGRect(x: 0, y: 0, width: 0, height: 20))

        XCTAssertFalse(rect.minX.isNaN)
        XCTAssertFalse(rect.width.isNaN)
        XCTAssertFalse(rect.minX.isInfinite)
        XCTAssertFalse(rect.width.isInfinite)
        XCTAssertEqual(rect.width, 0, accuracy: 0.01)
    }

    // MARK: - Non-zero-origin bounds

    func testLaneRectHonorsANonZeroOriginBounds() {
        let rect = VideoTimelineGeometry.laneRect(
            start: 2, duration: 3, compositionDuration: 10,
            in: CGRect(x: 40, y: 5, width: width, height: 20))

        XCTAssertEqual(rect.minX, 100, accuracy: 0.01)
        XCTAssertEqual(rect.minY, 5, accuracy: 0.01)
        XCTAssertEqual(rect.width, 90, accuracy: 0.01)
    }
}

// MARK: - VideoTimeline (Task 5: collapsed strip and expanded lanes)

/// Exercises the view itself, not just its maths. Every test lays the view out
/// for real (an explicit frame + `layoutIfNeeded()`) rather than asserting on
/// unlaid-out constants — the zero-height ToolButton/close-button bugs in
/// Plan 1 (`EditorChromeTests`) passed every test that skipped that step.
@MainActor
final class VideoTimelineViewTests: XCTestCase {

    private func makeTimeline(width: CGFloat = 320) -> VideoTimeline {
        let timeline = VideoTimeline()
        timeline.frame = CGRect(x: 0, y: 0, width: width, height: VideoTimeline.expandedHeight)
        timeline.layoutIfNeeded()
        return timeline
    }

    private func threeClipModel(duration: Double = 12) -> VideoTimelineModel {
        VideoTimelineModel(
            duration: duration,
            clips: [
                .init(index: 0, start: 0, duration: 4, isFilled: true),
                .init(index: 1, start: 4, duration: 4, isFilled: false),
                .init(index: 2, start: 8, duration: 4, isFilled: true),
            ],
            textPills: [],
            musicTitle: nil)
    }

    // MARK: - State and height

    func testTheDefaultStateIsCollapsed() {
        let timeline = VideoTimeline()
        XCTAssertEqual(timeline.state, .collapsed)
        XCTAssertEqual(timeline.heightForTesting, VideoTimeline.collapsedHeight, accuracy: 0.01)
    }

    func testExpandingGrowsTheOwnedHeightConstraint() {
        let timeline = makeTimeline()
        XCTAssertEqual(timeline.heightForTesting, VideoTimeline.collapsedHeight, accuracy: 0.01)

        timeline.setState(.expanded, animated: false)
        timeline.layoutIfNeeded()

        XCTAssertEqual(timeline.state, .expanded)
        XCTAssertEqual(timeline.heightForTesting, VideoTimeline.expandedHeight, accuracy: 0.01)
        XCTAssertGreaterThan(VideoTimeline.expandedHeight, VideoTimeline.collapsedHeight)
        // Real layout, not just the constant: the view must actually resolve to
        // that height, not merely hold a constraint nobody applied.
        XCTAssertEqual(timeline.bounds.height, VideoTimeline.expandedHeight, accuracy: 0.5)
    }

    func testCollapsingBackReturnsTheOwnedHeightConstraint() {
        let timeline = makeTimeline()
        timeline.setState(.expanded, animated: false)
        timeline.layoutIfNeeded()

        timeline.setState(.collapsed, animated: false)
        timeline.layoutIfNeeded()

        XCTAssertEqual(timeline.state, .collapsed)
        XCTAssertEqual(timeline.heightForTesting, VideoTimeline.collapsedHeight, accuracy: 0.01)
    }

    func testTappingTheChevronReportsTheOppositeStateWithoutChangingItsOwnState() {
        // The view never mutates its own state from an interaction — it reports
        // through a callback and waits for the owner to call setState, the same
        // split EditorToolRail/EditorPanel use for every other control here.
        let timeline = makeTimeline()
        var reported: VideoTimeline.State?
        timeline.onToggleState = { reported = $0 }

        timeline.simulateChevronTap()

        XCTAssertEqual(reported, .expanded)
        XCTAssertEqual(timeline.state, .collapsed, "setState was never called back, so state must not have moved")
    }

    func testTappingTheChevronWhileExpandedProposesCollapsed() {
        let timeline = makeTimeline()
        timeline.setState(.expanded, animated: false)
        var reported: VideoTimeline.State?
        timeline.onToggleState = { reported = $0 }

        timeline.simulateChevronTap()

        XCTAssertEqual(reported, .collapsed)
    }

    // MARK: - The chevron's hit target (regression: zero-height controls shipped twice in Plan 1)

    func testTheChevronHasARealHitTarget() {
        let timeline = makeTimeline()
        let chevron = timeline.chevronButtonForHitTesting

        XCTAssertGreaterThan(chevron.bounds.width, 0, "Chevron must derive a real width")
        XCTAssertGreaterThan(chevron.bounds.height, 0, "Chevron must derive a real height")

        let centre = chevron.convert(CGPoint(x: chevron.bounds.midX, y: chevron.bounds.midY), to: timeline)
        let hit = timeline.hitTest(centre, with: nil)

        XCTAssertTrue(hit?.isDescendant(of: chevron) ?? false,
                     "Hit-testing the chevron's visual centre must reach the chevron itself, " +
                     "not a parent view — a control pinned only by center anchors resolves to " +
                     "zero size and draws fine but cannot be tapped.")
    }

    // MARK: - Playback control (plan-defect fix: restores play/pause)

    func testTappingThePlaybackControlReportsThroughOnTogglePlayback() {
        let timeline = makeTimeline()
        var toggled = false
        timeline.onTogglePlayback = { toggled = true }

        timeline.simulatePlaybackTap()

        XCTAssertTrue(toggled)
    }

    func testTappingThePlaybackControlDoesNotChangeItsOwnIcon() {
        // Same split as the chevron: the view only ever reports the tap, it
        // never applies the toggle itself — the icon only moves via setModel.
        let timeline = makeTimeline()
        timeline.onTogglePlayback = {}
        XCTAssertEqual(timeline.playbackButtonForHitTesting.accessibilityLabel, "Play")

        timeline.simulatePlaybackTap()

        XCTAssertEqual(timeline.playbackButtonForHitTesting.accessibilityLabel, "Play",
                       "setModel was never called back, so the icon must not have moved")
    }

    func testThePlaybackControlShowsPlayWhenTheModelIsNotPlaying() {
        let timeline = makeTimeline()
        var model = VideoTimelineModel(duration: 10)
        model.isPlaying = false

        timeline.setModel(model)

        XCTAssertEqual(timeline.playbackButtonForHitTesting.accessibilityLabel, "Play")
    }

    func testThePlaybackControlShowsPauseWhenTheModelIsPlaying() {
        let timeline = makeTimeline()
        var model = VideoTimelineModel(duration: 10)
        model.isPlaying = true

        timeline.setModel(model)

        XCTAssertEqual(timeline.playbackButtonForHitTesting.accessibilityLabel, "Pause")
    }

    func testThePlaybackControlKeepsTheVideoPlayButtonIdentifier() {
        // The old transport Play button's identifier — restoring it keeps the
        // control discoverable to the UI suite under the same name.
        let timeline = makeTimeline()
        XCTAssertEqual(timeline.playbackButtonForHitTesting.accessibilityIdentifier, "videoPlayButton")
    }

    // MARK: - The playback control's hit target (same regression class as the chevron)

    func testTheHeaderControlsAreExposedAsButtonsNotBareContainers() {
        // Both are plain `UIControl`s, which are not accessibility elements and
        // carry no `.button` trait — VoiceOver announced the only way to pause
        // the preview as an unlabelled container. A UI test asserting
        // `app.buttons["videoPlayButton"]` matched nothing at all.
        let timeline = makeTimeline()

        for (control, name) in [(timeline.playbackButtonForHitTesting, "playback"),
                                (timeline.chevronButtonForHitTesting, "chevron")] {
            XCTAssertTrue(control.isAccessibilityElement,
                          "the \(name) control must be an accessibility element")
            XCTAssertTrue(control.accessibilityTraits.contains(.button),
                          "the \(name) control must announce itself as a button")
            XCTAssertFalse(control.accessibilityLabel?.isEmpty ?? true,
                           "the \(name) control must say what it does")
        }
    }

    func testThePlaybackControlHasARealHitTarget() {
        let timeline = makeTimeline()
        let playback = timeline.playbackButtonForHitTesting

        XCTAssertGreaterThan(playback.bounds.width, 0, "Playback control must derive a real width")
        XCTAssertGreaterThan(playback.bounds.height, 0, "Playback control must derive a real height")

        let centre = playback.convert(CGPoint(x: playback.bounds.midX, y: playback.bounds.midY), to: timeline)
        let hit = timeline.hitTest(centre, with: nil)

        XCTAssertTrue(hit?.isDescendant(of: playback) ?? false,
                     "Hit-testing the playback control's visual centre must reach the control itself, " +
                     "not a parent view — a control pinned only by center anchors resolves to " +
                     "zero size and draws fine but cannot be tapped.")
    }

    // MARK: - setModel / lanes

    func testSetModelWithThreeClipsProducesThreeLanesWhenExpanded() {
        let timeline = makeTimeline()
        timeline.setState(.expanded, animated: false)
        timeline.setModel(threeClipModel())
        timeline.layoutIfNeeded()

        XCTAssertEqual(timeline.expandedClipLaneCount, 3)
    }

    // MARK: - The music lane
    //
    // Plan 2's done-criteria name it alongside the clip and text lanes, and it
    // was the only one of the three with no test at all.

    func testTheExpandedTimelineNamesTheDocumentsMusic() {
        let timeline = makeTimeline()
        timeline.setState(.expanded, animated: false)
        var model = threeClipModel()
        model.musicTitle = "Music"
        timeline.setModel(model)
        timeline.layoutIfNeeded()

        XCTAssertTrue(timeline.musicLaneIsLaidOutForTesting, "the lane is on screen, not just configured")
        XCTAssertEqual(timeline.musicLaneTextForTesting, "Music")
    }

    func testTheMusicLaneSaysSoWhenThereIsNoMusic() {
        // The lane is always present — an empty one that said nothing would read
        // as a rendering bug rather than as "you have not added music".
        let timeline = makeTimeline()
        timeline.setState(.expanded, animated: false)
        timeline.setModel(threeClipModel())
        timeline.layoutIfNeeded()

        XCTAssertTrue(timeline.musicLaneIsLaidOutForTesting)
        XCTAssertEqual(timeline.musicLaneTextForTesting, "No music added")
    }

    func testSetModelWithNoClipsProducesNoLanes() {
        let timeline = makeTimeline()
        timeline.setState(.expanded, animated: false)
        timeline.setModel(VideoTimelineModel(duration: 10))
        timeline.layoutIfNeeded()

        XCTAssertEqual(timeline.expandedClipLaneCount, 0)
    }

    func testReplacingTheModelRebuildsTheLaneCount() {
        let timeline = makeTimeline()
        timeline.setState(.expanded, animated: false)
        timeline.setModel(threeClipModel())
        timeline.layoutIfNeeded()
        XCTAssertEqual(timeline.expandedClipLaneCount, 3)

        timeline.setModel(VideoTimelineModel(duration: 6, clips: [
            .init(index: 0, start: 0, duration: 6, isFilled: true),
        ]))
        timeline.layoutIfNeeded()

        XCTAssertEqual(timeline.expandedClipLaneCount, 1)
    }

    func testTextPillCountMatchesTheModelWhenExpanded() {
        let timeline = makeTimeline()
        timeline.setState(.expanded, animated: false)
        var model = threeClipModel()
        model.textPills = [
            .init(id: UUID(), label: "Hello", start: 1, end: 3),
            .init(id: UUID(), label: "World", start: 5, end: 6),
        ]
        timeline.setModel(model)
        timeline.layoutIfNeeded()

        XCTAssertEqual(timeline.expandedTextPillCount, 2)
    }

    // MARK: - The TextPill start/end -> laneRect start/duration conversion

    func testATextPillsWidthReflectsEndMinusStartNotEndAlone() {
        // VideoTimelineModel.TextPill is modelled as start/end, but laneRect
        // takes start/duration. Getting this wrong doesn't fail to compile —
        // it silently renders the pill at the wrong width.
        let timeline = makeTimeline(width: 300)
        timeline.setState(.expanded, animated: false)
        let id = UUID()
        var model = VideoTimelineModel(duration: 10)
        model.textPills = [.init(id: id, label: "Caption", start: 2, end: 5)]
        timeline.setModel(model)
        timeline.layoutIfNeeded()

        guard let frame = timeline.frameForTextPill(id: id) else {
            return XCTFail("Expected a rendered frame for the text pill")
        }

        // start=2, duration=(5-2)=3, compositionDuration=10, width=300
        // -> minX = 60, width = 90 (see VideoTimelineGeometry's own tests).
        XCTAssertEqual(frame.minX, 60, accuracy: 1.5)
        XCTAssertEqual(frame.width, 90, accuracy: 1.5)

        // If `end` (5) had been passed directly as the duration instead of
        // `end - start` (3), the rendered width would be 150, not 90.
        XCTAssertLessThan(frame.width, 120, "Width looks like it used `end` instead of `end - start`")
    }

    // MARK: - Playhead

    func testThePlayheadMovesWithSetPlayheadWhileCollapsed() {
        let timeline = makeTimeline(width: 300)
        timeline.setModel(VideoTimelineModel(duration: 10))
        timeline.layoutIfNeeded()

        timeline.setPlayhead(0)
        timeline.layoutIfNeeded()
        let atStart = timeline.playheadXForTesting

        timeline.setPlayhead(5)
        timeline.layoutIfNeeded()
        let atMiddle = timeline.playheadXForTesting

        XCTAssertEqual(atStart, 0, accuracy: 1.5)
        XCTAssertEqual(atMiddle, 150, accuracy: 1.5)
        XCTAssertGreaterThan(atMiddle, atStart)
    }

    func testThePlayheadMovesWithSetPlayheadWhileExpanded() {
        let timeline = makeTimeline(width: 300)
        timeline.setState(.expanded, animated: false)
        timeline.setModel(threeClipModel(duration: 12))
        timeline.layoutIfNeeded()

        timeline.setPlayhead(0)
        timeline.layoutIfNeeded()
        let atStart = timeline.playheadXForTesting

        timeline.setPlayhead(6)
        timeline.layoutIfNeeded()
        let atMiddle = timeline.playheadXForTesting

        XCTAssertEqual(atStart, 0, accuracy: 1.5)
        XCTAssertEqual(atMiddle, 150, accuracy: 1.5)
    }

    // MARK: - Scrubbing

    func testScrubbingReportsATimeThroughOnScrub() {
        let timeline = makeTimeline(width: 300)
        timeline.setModel(VideoTimelineModel(duration: 10))
        timeline.layoutIfNeeded()

        var scrubbed: Double?
        timeline.onScrub = { scrubbed = $0 }

        timeline.simulateTap(at: CGPoint(x: 150, y: timeline.bounds.height / 2))

        XCTAssertEqual(scrubbed ?? -1, 5, accuracy: 0.5)
    }

    /// Renamed from `testScrubbingDoesNotFireWhenTappingTheHeader`: what this
    /// actually exercises is `simulateChevronTap`, i.e. `sendActions(for:
    /// .touchUpInside)` on the button directly — it never goes anywhere near
    /// `tapGesture`/`performTap` or the `gestureRecognizer(_:shouldReceive:)`
    /// exclusion those rely on. It still documents a real (if narrow) fact —
    /// firing the chevron's own action doesn't happen to also trip `onScrub`
    /// — but the header-touch exclusion itself is covered by
    /// `testGestureRecognizerShouldReceiveExcludesHeaderTouchesButNotOthers`
    /// below, which calls the delegate method directly.
    func testSimulatedChevronTapOnlyFiresItsOwnActionNotOnScrub() {
        let timeline = makeTimeline(width: 300)
        timeline.setModel(VideoTimelineModel(duration: 10))
        timeline.layoutIfNeeded()

        var scrubbed = false
        timeline.onScrub = { _ in scrubbed = true }
        timeline.simulateChevronTap()

        XCTAssertFalse(scrubbed)
    }

    /// A `UITouch` whose `view` is fixed at construction. `UITouch` has no
    /// public way to attach a view to a plain instance, so this overrides the
    /// one property `gestureRecognizer(_:shouldReceive:)` actually reads.
    private final class FakeTouch: UITouch {
        private let fakeView: UIView?
        init(view: UIView?) {
            self.fakeView = view
            super.init()
        }
        override var view: UIView? { fakeView }
    }

    /// Exercises `gestureRecognizer(_:shouldReceive:)` itself — the delegate
    /// method `testSimulatedChevronTapOnlyFiresItsOwnActionNotOnScrub`
    /// (formerly `testScrubbingDoesNotFireWhenTappingTheHeader`) nominally
    /// guarded but never actually called, since it went through
    /// `sendActions` instead. Before this test existed, nothing in the suite
    /// referenced the delegate method at all, so deleting it changed nothing
    /// observable; this one calls it directly, so removing the method now
    /// fails the build.
    func testGestureRecognizerShouldReceiveExcludesHeaderTouchesButNotOthers() {
        let timeline = makeTimeline()
        let recognizer = UIPanGestureRecognizer()

        let headerTouch = FakeTouch(view: timeline.chevronButtonForHitTesting)
        XCTAssertFalse(
            timeline.gestureRecognizer(recognizer, shouldReceive: headerTouch),
            "A touch on the header (the chevron) must be excluded from the timeline's own gestures")

        let bodyTouch = FakeTouch(view: timeline)
        XCTAssertTrue(
            timeline.gestureRecognizer(recognizer, shouldReceive: bodyTouch),
            "A touch outside the header must still be received")
    }

    // MARK: - Selection

    func testTappingAClipsMiddleReportsOnSelectClip() {
        let timeline = makeTimeline(width: 300)
        timeline.setState(.expanded, animated: false)
        timeline.setModel(threeClipModel())
        timeline.layoutIfNeeded()

        guard let frame = timeline.frameForClip(at: 1) else {
            return XCTFail("Expected a rendered frame for clip 1")
        }
        var selected: Int?
        timeline.onSelectClip = { selected = $0 }

        timeline.simulateTap(at: CGPoint(x: frame.midX, y: frame.midY))

        XCTAssertEqual(selected, 1)
    }

    func testTappingATextPillsMiddleReportsOnSelectText() {
        let timeline = makeTimeline(width: 300)
        timeline.setState(.expanded, animated: false)
        let id = UUID()
        var model = VideoTimelineModel(duration: 10)
        model.textPills = [.init(id: id, label: "Caption", start: 2, end: 8)]
        timeline.setModel(model)
        timeline.layoutIfNeeded()

        guard let frame = timeline.frameForTextPill(id: id) else {
            return XCTFail("Expected a rendered frame for the text pill")
        }
        var selected: UUID?
        timeline.onSelectText = { selected = $0 }

        timeline.simulateTap(at: CGPoint(x: frame.midX, y: frame.midY))

        XCTAssertEqual(selected, id)
    }

    // MARK: - Selection rendering (Fix 2: the model can now express selection)

    func testASelectedClipRendersTheAccentColorUnlikeAnUnselectedClip() {
        let timeline = makeTimeline(width: 300)
        timeline.setState(.expanded, animated: false)
        var model = threeClipModel()
        model.selectedClipIndex = 1
        timeline.setModel(model)
        timeline.layoutIfNeeded()

        let light = UITraitCollection(userInterfaceStyle: .light)
        let accent = Theme.Color.accent.resolvedColor(with: light)

        XCTAssertEqual(timeline.colorForClip(at: 1)?.resolvedColor(with: light), accent,
                       "The selected clip must render the indigo state color")
        XCTAssertNotEqual(timeline.colorForClip(at: 0)?.resolvedColor(with: light), accent,
                          "An unselected clip must not render the indigo state color")
    }

    func testASelectedTextPillRendersTheAccentColorUnlikeAnUnselectedPill() {
        let timeline = makeTimeline(width: 300)
        timeline.setState(.expanded, animated: false)
        let selectedID = UUID()
        let otherID = UUID()
        var model = VideoTimelineModel(duration: 10)
        model.textPills = [
            .init(id: selectedID, label: "Selected", start: 1, end: 3),
            .init(id: otherID, label: "Other", start: 5, end: 6),
        ]
        model.selectedTextID = selectedID
        timeline.setModel(model)
        timeline.layoutIfNeeded()

        let light = UITraitCollection(userInterfaceStyle: .light)
        let accent = Theme.Color.accent.resolvedColor(with: light)

        XCTAssertEqual(timeline.colorForTextPill(id: selectedID)?.resolvedColor(with: light), accent,
                       "The selected text pill must render the indigo state color")
        XCTAssertNotEqual(timeline.colorForTextPill(id: otherID)?.resolvedColor(with: light), accent,
                          "An unselected text pill must not render the indigo state color")
    }

    // MARK: - Trim / retime dragging

    func testDraggingAClipsTrailingEdgeReportsOnTrim() {
        let timeline = makeTimeline(width: 300)
        timeline.setState(.expanded, animated: false)
        timeline.setModel(threeClipModel(duration: 12)) // clip 0: start 0, duration 4
        timeline.layoutIfNeeded()

        guard let frame = timeline.frameForClip(at: 0) else {
            return XCTFail("Expected a rendered frame for clip 0")
        }
        var trims: [(Int, Double, Double, VideoTimeline.EditPhase)] = []
        timeline.onTrim = { trims.append(($0, $1, $2, $3)) }

        let trailingEdge = CGPoint(x: frame.maxX - 1, y: frame.midY)
        timeline.simulatePanBegan(at: trailingEdge)
        timeline.simulatePanChanged(at: CGPoint(x: trailingEdge.x + 20, y: frame.midY))
        timeline.simulatePanEnded(at: CGPoint(x: trailingEdge.x + 20, y: frame.midY))

        guard let last = trims.last else { return XCTFail("Expected onTrim to fire") }
        XCTAssertEqual(last.0, 0)
        XCTAssertEqual(last.1, 0, accuracy: 0.01, "The untouched (leading) edge must not move")
        XCTAssertGreaterThan(last.2, 4, "The dragged (trailing) edge must have moved later")
        XCTAssertEqual(last.3, .committed, "The final report from a completed drag must be committed")
    }

    func testDraggingATextPillsLeadingEdgeReportsOnRetimeText() {
        let timeline = makeTimeline(width: 300)
        timeline.setState(.expanded, animated: false)
        let id = UUID()
        var model = VideoTimelineModel(duration: 12)
        model.textPills = [.init(id: id, label: "Caption", start: 4, end: 8)]
        timeline.setModel(model)
        timeline.layoutIfNeeded()

        guard let frame = timeline.frameForTextPill(id: id) else {
            return XCTFail("Expected a rendered frame for the text pill")
        }
        var retimes: [(UUID, Double, Double, VideoTimeline.EditPhase)] = []
        timeline.onRetimeText = { retimes.append(($0, $1, $2, $3)) }

        let leadingEdge = CGPoint(x: frame.minX + 1, y: frame.midY)
        timeline.simulatePanBegan(at: leadingEdge)
        timeline.simulatePanChanged(at: CGPoint(x: leadingEdge.x - 20, y: frame.midY))
        timeline.simulatePanEnded(at: CGPoint(x: leadingEdge.x - 20, y: frame.midY))

        guard let last = retimes.last else { return XCTFail("Expected onRetimeText to fire") }
        XCTAssertEqual(last.0, id)
        XCTAssertLessThan(last.1, 4, "The dragged (leading) edge must have moved earlier")
        XCTAssertEqual(last.2, 8, accuracy: 0.01, "The untouched (trailing) edge must not move")
        XCTAssertEqual(last.3, .committed, "The final report from a completed drag must be committed")
    }

    // MARK: - Narrow-clip edge resolution (Fix 3)

    func testANarrowClipIsTrimmableFromBothEdges() {
        let timeline = makeTimeline(width: 380)
        timeline.setState(.expanded, animated: false)
        // ~1.5s of a 30s composition at 380pt renders under 24pt wide — the
        // mainstream "short quick-cut clip" case a fixed 12pt-per-side
        // tolerance couldn't reach on its trailing edge at all (it all
        // resolved to the leading edge first).
        let model = VideoTimelineModel(duration: 30, clips: [
            .init(index: 0, start: 10, duration: 1.5, isFilled: true),
        ])
        timeline.setModel(model)
        timeline.layoutIfNeeded()

        guard let frame = timeline.frameForClip(at: 0) else {
            return XCTFail("Expected a rendered frame for the narrow clip")
        }
        XCTAssertLessThan(frame.width, 24, "Precondition: narrower than 2x the old fixed tolerance")

        var trims: [(Int, Double, Double, VideoTimeline.EditPhase)] = []
        timeline.onTrim = { trims.append(($0, $1, $2, $3)) }

        let trailingEdge = CGPoint(x: frame.maxX - 1, y: frame.midY)
        timeline.simulatePanBegan(at: trailingEdge)
        timeline.simulatePanEnded(at: CGPoint(x: trailingEdge.x + 30, y: frame.midY))

        guard let trailingResult = trims.last else {
            return XCTFail("Expected the trailing-edge drag to report onTrim")
        }
        XCTAssertEqual(trailingResult.1, 10, accuracy: 0.01, "Dragging the trailing edge must not move the start")
        XCTAssertGreaterThan(trailingResult.2, 11.5, "Dragging the trailing edge must move the end later")

        trims.removeAll()

        let leadingEdge = CGPoint(x: frame.minX + 1, y: frame.midY)
        timeline.simulatePanBegan(at: leadingEdge)
        timeline.simulatePanEnded(at: CGPoint(x: leadingEdge.x - 5, y: frame.midY))

        guard let leadingResult = trims.last else {
            return XCTFail("Expected the leading-edge drag to report onTrim")
        }
        XCTAssertLessThan(leadingResult.1, 10, "Dragging the leading edge must move the start earlier")
        XCTAssertEqual(leadingResult.2, 11.5, accuracy: 0.01, "Dragging the leading edge must not move the end")
    }

    // MARK: - Edit phase (Fix 1: trim/retime must distinguish in-progress from committed)

    func testDraggingAClipReportsChangedThroughoutAndExactlyOneCommittedAtTheEnd() {
        let timeline = makeTimeline(width: 300)
        timeline.setState(.expanded, animated: false)
        timeline.setModel(threeClipModel(duration: 12))
        timeline.layoutIfNeeded()

        guard let frame = timeline.frameForClip(at: 0) else {
            return XCTFail("Expected a rendered frame for clip 0")
        }
        var phases: [VideoTimeline.EditPhase] = []
        timeline.onTrim = { _, _, _, phase in phases.append(phase) }

        let trailingEdge = CGPoint(x: frame.maxX - 1, y: frame.midY)
        timeline.simulatePanBegan(at: trailingEdge) // 1 report (.changed)
        timeline.simulatePanChanged(at: CGPoint(x: trailingEdge.x + 5, y: frame.midY))
        timeline.simulatePanChanged(at: CGPoint(x: trailingEdge.x + 10, y: frame.midY))
        timeline.simulatePanChanged(at: CGPoint(x: trailingEdge.x + 15, y: frame.midY)) // 3 more, all .changed
        timeline.simulatePanEnded(at: CGPoint(x: trailingEdge.x + 20, y: frame.midY)) // 1 report (.committed)

        XCTAssertEqual(phases.count, 5, "Precondition: began + 3 changed + ended")
        XCTAssertEqual(phases.filter { $0 == .committed }.count, 1,
                       "A drag must commit exactly once, at .ended")
        XCTAssertEqual(phases.filter { $0 == .changed }.count, 4,
                       "Every other report — began, plus every .changed tick — must be .changed")
        XCTAssertEqual(phases.last, .committed, "The commit must be the drag's final report")
    }

    func testACancelledDragReportsChangedButNeverCommitted() {
        let timeline = makeTimeline(width: 300)
        timeline.setState(.expanded, animated: false)
        timeline.setModel(threeClipModel(duration: 12))
        timeline.layoutIfNeeded()

        guard let frame = timeline.frameForClip(at: 0) else {
            return XCTFail("Expected a rendered frame for clip 0")
        }
        var phases: [VideoTimeline.EditPhase] = []
        timeline.onTrim = { _, _, _, phase in phases.append(phase) }

        let trailingEdge = CGPoint(x: frame.maxX - 1, y: frame.midY)
        timeline.simulatePanBegan(at: trailingEdge)
        timeline.simulatePanChanged(at: CGPoint(x: trailingEdge.x + 10, y: frame.midY))
        // The system interrupts the touch (e.g. an incoming call) instead of
        // a normal lift-off.
        timeline.simulatePanCancelled(at: CGPoint(x: trailingEdge.x + 20, y: frame.midY))

        XCTAssertFalse(phases.isEmpty, "Precondition: the drag must have reported at least once")
        XCTAssertTrue(phases.allSatisfy { $0 == .changed },
                     "A gesture the system cancelled must never be reported as committed")
    }

    // MARK: - Stale gesture state (Trap #4)

    func testReplacingTheModelMidDragCancelsTheDragRatherThanActingOnStaleIndices() {
        let timeline = makeTimeline(width: 300)
        timeline.setState(.expanded, animated: false)
        timeline.setModel(threeClipModel(duration: 12))
        timeline.layoutIfNeeded()

        guard let frame = timeline.frameForClip(at: 2) else {
            return XCTFail("Expected a rendered frame for clip 2")
        }
        var trims: [(Int, Double, Double, VideoTimeline.EditPhase)] = []
        timeline.onTrim = { trims.append(($0, $1, $2, $3)) }

        let trailingEdge = CGPoint(x: frame.maxX - 1, y: frame.midY)
        timeline.simulatePanBegan(at: trailingEdge)
        XCTAssertFalse(trims.isEmpty, "Precondition: the drag must have reported at least once")
        trims.removeAll()

        // The document changes underneath the in-flight drag — clip 2 no longer exists.
        timeline.setModel(VideoTimelineModel(duration: 12, clips: [
            .init(index: 0, start: 0, duration: 12, isFilled: true),
        ]))
        timeline.layoutIfNeeded()

        // Continuing the same gesture must not act on the index it captured
        // before the replacement — it must not crash and must not report.
        timeline.simulatePanChanged(at: CGPoint(x: trailingEdge.x + 20, y: frame.midY))
        timeline.simulatePanEnded(at: CGPoint(x: trailingEdge.x + 20, y: frame.midY))

        XCTAssertTrue(trims.isEmpty, "A drag in progress must not act on indices the new model invalidated")
    }

    // MARK: - Degenerate model (no duration yet)

    func testAZeroDurationModelDoesNotProduceNaNGeometryOrCrash() {
        let timeline = makeTimeline(width: 300)
        timeline.setState(.expanded, animated: false)
        timeline.setModel(VideoTimelineModel(duration: 0, clips: [
            .init(index: 0, start: 0, duration: 0, isFilled: false),
        ]))
        timeline.layoutIfNeeded()

        guard let frame = timeline.frameForClip(at: 0) else {
            return XCTFail("Expected a rendered (possibly zero-width) frame for clip 0")
        }
        XCTAssertFalse(frame.minX.isNaN)
        XCTAssertFalse(frame.width.isNaN)

        timeline.setPlayhead(0)
        timeline.layoutIfNeeded()
        XCTAssertFalse(timeline.playheadXForTesting.isNaN)
    }
}
