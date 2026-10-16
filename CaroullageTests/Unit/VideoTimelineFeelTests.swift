//
//  VideoTimelineFeelTests.swift
//  CaroullageTests
//
//  The timeline redesign: a playhead that runs smoothly between the player's
//  coarse reports, drags that snap to meaningful times, filmstrips anchored in
//  source time, a waveform cut to what actually plays, and a ruler whose ticks
//  fit the composition. Behaviour, not pixels — the rendering is covered by
//  visual QA.
//

import AVFoundation
import UIKit
import XCTest
@testable import Caroullage

@MainActor
final class VideoTimelineFeelTests: XCTestCase {

    private func makeTimeline(width: CGFloat = 300, inWindow: Bool = false) -> (VideoTimeline, UIWindow?) {
        let timeline = VideoTimeline()
        timeline.frame = CGRect(x: 0, y: 0, width: width, height: VideoTimeline.expandedHeight)
        var window: UIWindow?
        if inWindow {
            let host = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 400))
            host.addSubview(timeline)
            host.isHidden = false
            window = host
        }
        timeline.layoutIfNeeded()
        return (timeline, window)
    }

    private func twoClipModel(duration: Double = 10, isPlaying: Bool = false) -> VideoTimelineModel {
        VideoTimelineModel(
            duration: duration,
            clips: [.init(index: 0, start: 0, duration: 4, isFilled: true),
                    .init(index: 1, start: 0, duration: 10, isFilled: true)],
            isPlaying: isPlaying)
    }

    // MARK: - The playback clock

    func testThePlayheadRunsOnBetweenReportsWhilePlaying() {
        let (timeline, window) = makeTimeline(inWindow: true)
        defer { window?.isHidden = true }
        timeline.setModel(twoClipModel(isPlaying: true))
        timeline.setPlayhead(2)
        XCTAssertTrue(timeline.isClockRunningForTesting)

        timeline.simulateClockTickForTesting(secondsSinceReport: 0.25)

        XCTAssertEqual(timeline.playheadXForTesting, 67.5, accuracy: 1.5,
                       "2.25s of 10s across 300pt — the playhead moves between the 10 Hz reports")
        XCTAssertEqual(timeline.playheadTimeForTesting, 2, accuracy: 0.001,
                       "the reported time stays the player's truth")
    }

    func testTheClockNeverRunsFarPastTheLastReport() {
        let (timeline, window) = makeTimeline(inWindow: true)
        defer { window?.isHidden = true }
        timeline.setModel(twoClipModel(isPlaying: true))
        timeline.setPlayhead(2)

        timeline.simulateClockTickForTesting(secondsSinceReport: 5)

        XCTAssertEqual(timeline.playheadXForTesting, 75, accuracy: 1.5,
                       "a stalled player must not leave the playhead gliding on — half a second at most")
    }

    /// Review finding: the owner re-pushes the last report on EVERY document
    /// change. Treating that as a fresh report restarted the clock from a time
    /// up to 100 ms old — the playhead stepped back on each edit during playback.
    func testARepeatedReportDoesNotPullThePlayheadBack() {
        let (timeline, window) = makeTimeline(inWindow: true)
        defer { window?.isHidden = true }
        timeline.setModel(twoClipModel(isPlaying: true))
        timeline.setPlayhead(2)
        timeline.simulateClockTickForTesting(secondsSinceReport: 0.25)

        timeline.setModel(twoClipModel(isPlaying: true))   // an edit elsewhere…
        timeline.setPlayhead(2)                            // …re-pushes the same report
        timeline.layoutIfNeeded()

        XCTAssertEqual(timeline.playheadXForTesting, 67.5, accuracy: 1.5,
                       "the playhead holds where the clock carried it")
    }

    func testPressingPlayDoesNotJumpThePlayheadAhead() {
        // Paused at 2s long enough ago that the report is stale; play starts.
        let (timeline, window) = makeTimeline(inWindow: true)
        defer { window?.isHidden = true }
        timeline.setModel(twoClipModel(isPlaying: false))
        timeline.setPlayhead(2)
        timeline.backdateLastReportForTesting(by: 3)

        timeline.setModel(twoClipModel(isPlaying: true))
        timeline.setPlayhead(2)
        timeline.tickClockForTesting()

        XCTAssertEqual(timeline.playheadXForTesting, 60, accuracy: 1.5,
                       "the clock starts from where the playhead is, not half a second on")
    }

    func testTheClockOnlyRunsWhilePlaying() {
        let (timeline, window) = makeTimeline(inWindow: true)
        defer { window?.isHidden = true }
        timeline.setModel(twoClipModel(isPlaying: false))
        XCTAssertFalse(timeline.isClockRunningForTesting)

        timeline.setModel(twoClipModel(isPlaying: true))
        XCTAssertTrue(timeline.isClockRunningForTesting)

        timeline.setModel(twoClipModel(isPlaying: false))
        XCTAssertFalse(timeline.isClockRunningForTesting)
    }

    func testTheReadoutShowsTenths() {
        let (timeline, _) = makeTimeline()
        timeline.setModel(twoClipModel(duration: 8))
        timeline.setPlayhead(3.27)
        XCTAssertEqual(timeline.readoutForTesting, "0:03.2 / 0:08.0")
    }

    // MARK: - Snapping

    func testAScrubSnapsToANearbyClipEdge() {
        let (timeline, _) = makeTimeline()
        timeline.setModel(twoClipModel())   // clip 0 ends at 4s → x = 120
        var scrubbed: [Double] = []
        timeline.onScrub = { scrubbed.append($0) }

        timeline.simulatePanBegan(at: CGPoint(x: 60, y: 60))
        timeline.simulatePanChanged(at: CGPoint(x: 124, y: 60))
        timeline.simulatePanEnded(at: CGPoint(x: 124, y: 60))

        XCTAssertEqual(scrubbed.last ?? -1, 4, accuracy: 0.0001, "4pt from the cut, the scrub lands on it")
    }

    func testAScrubAwayFromEveryEdgeIsExact() {
        let (timeline, _) = makeTimeline()
        timeline.setModel(twoClipModel())
        var scrubbed: [Double] = []
        timeline.onScrub = { scrubbed.append($0) }

        timeline.simulatePanBegan(at: CGPoint(x: 60, y: 60))
        timeline.simulatePanEnded(at: CGPoint(x: 180, y: 60))

        XCTAssertEqual(scrubbed.last ?? -1, 6, accuracy: 0.0001)
    }

    func testATrimEdgeSnapsToThePlayhead() {
        let (timeline, _) = makeTimeline()
        timeline.setState(.expanded, animated: false)
        timeline.setModel(twoClipModel())
        timeline.setPlayhead(5)             // x = 150
        timeline.layoutIfNeeded()
        let frame = try? XCTUnwrap(timeline.frameForClip(at: 0))   // 0…4s → 0…120
        var trims: [(Double, Double)] = []
        timeline.onTrim = { _, start, end, _ in trims.append((start, end)) }

        let edge = CGPoint(x: (frame?.maxX ?? 120) - 1, y: frame?.midY ?? 0)
        timeline.simulatePanBegan(at: edge)
        timeline.simulatePanEnded(at: CGPoint(x: 146, y: edge.y))

        XCTAssertEqual(trims.last?.1 ?? -1, 5, accuracy: 0.0001, "trim to the playhead")
    }

    func testATrimCannotPassTheEndOfTheComposition() {
        let (timeline, _) = makeTimeline()
        timeline.setState(.expanded, animated: false)
        timeline.setModel(twoClipModel())
        timeline.layoutIfNeeded()
        let frame = timeline.frameForClip(at: 0) ?? .zero
        var ends: [Double] = []
        timeline.onTrim = { _, _, end, _ in ends.append(end) }

        timeline.simulatePanBegan(at: CGPoint(x: frame.maxX - 1, y: frame.midY))
        timeline.simulatePanEnded(at: CGPoint(x: 600, y: frame.midY))

        XCTAssertEqual(ends.last ?? -1, 10, accuracy: 0.0001)
    }

    // MARK: - Collapse / expand

    func testExpandingShowsTheLanesAndHidesTheStrip() {
        let (timeline, _) = makeTimeline()
        timeline.setModel(twoClipModel())
        timeline.setState(.expanded, animated: false)
        XCTAssertEqual(timeline.expandedClipLaneCount, 2)
        XCTAssertEqual(timeline.heightForTesting, VideoTimeline.expandedHeight)
        timeline.setState(.collapsed, animated: false)
        XCTAssertEqual(timeline.heightForTesting, VideoTimeline.collapsedHeight)
    }
}

// MARK: - Media values

final class VideoTimelineMediaTests: XCTestCase {

    private func image(_ width: CGFloat, _ height: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { _ in }
    }

    func testAFilmstripPicksTheFrameForASourceTime() {
        let frames = (0 ..< 4).map { _ in image(16, 9) }
        let strip = VideoTimelineFilmstrip(frames: frames, sourceDuration: 8)
        XCTAssertTrue(strip.frame(at: 0) === frames[0])
        XCTAssertTrue(strip.frame(at: 2.1) === frames[1])
        XCTAssertTrue(strip.frame(at: 7.9) === frames[3])
        XCTAssertTrue(strip.frame(at: 8) === frames[3], "the very end is the last frame, not past it")
        XCTAssertTrue(strip.frame(at: -1) === frames[0])
        XCTAssertEqual(strip.aspectRatio, 16.0 / 9.0, accuracy: 0.001)
    }

    func testAWaveformIsCutToTheTrimWindow() {
        let peaks: [Float] = (0 ..< 100).map { Float($0) / 100 }   // 10s track, 10 peaks/s
        let waveform = VideoTimelineMediaLoader.waveform(
            peaks: peaks, sourceDuration: 10, trim: VideoTrim(start: 2, end: 6), compositionDuration: 30)
        XCTAssertEqual(waveform?.duration ?? -1, 4, accuracy: 0.001)
        XCTAssertEqual(waveform?.peaks.first ?? -1, 0.2, accuracy: 0.001)
        XCTAssertEqual(waveform?.peaks.count, 40)
    }

    func testAWaveformStopsWhereTheCompositionDoes() {
        let peaks = [Float](repeating: 0.5, count: 100)
        let waveform = VideoTimelineMediaLoader.waveform(
            peaks: peaks, sourceDuration: 10, trim: VideoTrim(), compositionDuration: 3)
        XCTAssertEqual(waveform?.duration ?? -1, 3, accuracy: 0.001, "music is cut to the collage, like the export")
        XCTAssertEqual(waveform?.peaks.count, 30)
    }

    /// The reader itself, on real audio: one silent second then one loud one
    /// must come back as a flat first half and a full second half.
    func testTheWaveformReaderFindsWhereTheSoundIs() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoTimelineWaveform-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let rate = 44_100.0
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate * 2)))
        buffer.frameLength = buffer.frameCapacity
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0 ..< Int(buffer.frameLength) {
            samples[index] = index < Int(rate) ? 0 : Float(sin(Double(index) * 2 * .pi * 440 / rate)) * 0.8
        }
        try file.write(from: buffer)

        let peaks = await VideoTimelineMediaLoader.peaksForTesting(of: AVURLAsset(url: url), count: 20)

        XCTAssertGreaterThanOrEqual(peaks.count, 19)
        XCTAssertLessThan(peaks.prefix(8).max() ?? 1, 0.05, "the silent second reads as silence")
        XCTAssertGreaterThan(peaks.suffix(8).min() ?? 0, 0.8, "the loud second reads as loud")
    }

    func testNoPeaksMeansNoWaveform() {
        XCTAssertNil(VideoTimelineMediaLoader.waveform(
            peaks: [], sourceDuration: 10, trim: VideoTrim(), compositionDuration: 3))
    }

    @MainActor
    func testTheRulerLabelsAtAReadableInterval() {
        XCTAssertEqual(TimeRulerView.majorInterval(duration: 8, width: 400), 2,
                       "50pt/s: one label per second would crowd, every two reads")
        XCTAssertEqual(TimeRulerView.majorInterval(duration: 120, width: 400), 30)
        XCTAssertEqual(TimeRulerView.majorInterval(duration: 2, width: 400), 0.5)
    }

    func testTheModelCarriesEachClipsInPoint() {
        var cell = VideoCellState()
        cell.videoID = UUID()
        cell.trim = VideoTrim(start: 1.5, end: 4)
        let model = VideoTimelineModelBuilder.make(
            cells: [cell, VideoCellState()], sourceDurations: [0: 10], textOverlays: [])
        XCTAssertEqual(model.clips[0].sourceStart, 1.5, accuracy: 0.0001)
        XCTAssertEqual(model.clips[1].sourceStart, 0, "an empty slot has no in-point")
    }
}

// MARK: - Filmstrip anchoring

@MainActor
final class FilmstripTilesViewTests: XCTestCase {

    func testTilesStayAnchoredInSourceTimeWhenTheLeadingEdgeMoves() {
        // Square frames in a 20pt-tall strip: 20pt tiles; at 10pt per second
        // each tile covers 2s of source, showing the frame from its middle.
        let frames = (0 ..< 10).map { _ in UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { _ in } }
        let strip = VideoTimelineFilmstrip(frames: frames, sourceDuration: 10)
        let tiles = FilmstripTilesView(frame: CGRect(x: 0, y: 0, width: 100, height: 20))
        tiles.configure(filmstrip: strip, sourceStart: 0, sourceSpan: 10)
        tiles.layoutIfNeeded()
        let before = tiles.subviews.compactMap { $0 as? UIImageView }.filter { !$0.isHidden }
        XCTAssertEqual(before.first?.frame.minX ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(before.first { $0.image === frames[3] }?.frame.minX ?? -1, 20, accuracy: 0.01,
                       "the 2–4s tile shows the 3s frame")

        // Trim half a second off the front: the strip starts 0.5s later in the
        // source and is 5pt narrower. Every frame must move left by exactly
        // those 5pt — stay put in source time — not be re-cut from the edge.
        tiles.frame = CGRect(x: 0, y: 0, width: 95, height: 20)
        tiles.configure(filmstrip: strip, sourceStart: 0.5, sourceSpan: 9.5)
        tiles.layoutIfNeeded()
        let after = tiles.subviews.compactMap { $0 as? UIImageView }.filter { !$0.isHidden }
        XCTAssertEqual(after.first { $0.image === frames[3] }?.frame.minX ?? -1, 15, accuracy: 0.01,
                       "anchored in source time, not slid along with the edge")
        XCTAssertEqual(after.first?.frame.minX ?? 1, -5, accuracy: 0.01,
                       "the tile under the handle is partly uncovered, not re-cut")
    }
}
