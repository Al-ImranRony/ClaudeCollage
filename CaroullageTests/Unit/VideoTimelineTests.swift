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

    // MARK: - setModel / lanes

    func testSetModelWithThreeClipsProducesThreeLanesWhenExpanded() {
        let timeline = makeTimeline()
        timeline.setState(.expanded, animated: false)
        timeline.setModel(threeClipModel())
        timeline.layoutIfNeeded()

        XCTAssertEqual(timeline.expandedClipLaneCount, 3)
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

    func testScrubbingDoesNotFireWhenTappingTheHeader() {
        // The header (time readouts + chevron) must not also scrub — otherwise
        // tapping the chevron would both toggle state AND seek the player.
        let timeline = makeTimeline(width: 300)
        timeline.setModel(VideoTimelineModel(duration: 10))
        timeline.layoutIfNeeded()

        var scrubbed = false
        timeline.onScrub = { _ in scrubbed = true }
        timeline.simulateChevronTap()

        XCTAssertFalse(scrubbed)
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

    // MARK: - Trim / retime dragging

    func testDraggingAClipsTrailingEdgeReportsOnTrim() {
        let timeline = makeTimeline(width: 300)
        timeline.setState(.expanded, animated: false)
        timeline.setModel(threeClipModel(duration: 12)) // clip 0: start 0, duration 4
        timeline.layoutIfNeeded()

        guard let frame = timeline.frameForClip(at: 0) else {
            return XCTFail("Expected a rendered frame for clip 0")
        }
        var trims: [(Int, Double, Double)] = []
        timeline.onTrim = { trims.append(($0, $1, $2)) }

        let trailingEdge = CGPoint(x: frame.maxX - 1, y: frame.midY)
        timeline.simulatePanBegan(at: trailingEdge)
        timeline.simulatePanChanged(at: CGPoint(x: trailingEdge.x + 20, y: frame.midY))
        timeline.simulatePanEnded(at: CGPoint(x: trailingEdge.x + 20, y: frame.midY))

        guard let last = trims.last else { return XCTFail("Expected onTrim to fire") }
        XCTAssertEqual(last.0, 0)
        XCTAssertEqual(last.1, 0, accuracy: 0.01, "The untouched (leading) edge must not move")
        XCTAssertGreaterThan(last.2, 4, "The dragged (trailing) edge must have moved later")
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
        var retimes: [(UUID, Double, Double)] = []
        timeline.onRetimeText = { retimes.append(($0, $1, $2)) }

        let leadingEdge = CGPoint(x: frame.minX + 1, y: frame.midY)
        timeline.simulatePanBegan(at: leadingEdge)
        timeline.simulatePanChanged(at: CGPoint(x: leadingEdge.x - 20, y: frame.midY))
        timeline.simulatePanEnded(at: CGPoint(x: leadingEdge.x - 20, y: frame.midY))

        guard let last = retimes.last else { return XCTFail("Expected onRetimeText to fire") }
        XCTAssertEqual(last.0, id)
        XCTAssertLessThan(last.1, 4, "The dragged (leading) edge must have moved earlier")
        XCTAssertEqual(last.2, 8, accuracy: 0.01, "The untouched (trailing) edge must not move")
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
        var trims: [(Int, Double, Double)] = []
        timeline.onTrim = { trims.append(($0, $1, $2)) }

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
