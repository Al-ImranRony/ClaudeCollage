//
//  BeatSyncTests.swift
//  ClaudeCollageTests
//
//  Step 04 slice 6c — turning detected beats into per-cell transition timing.
//  `CellTransition` gains a `startTime` (when the intro fires), `BeatSyncPlanner`
//  maps beats onto cells, and the video editor's `applyBeatSync` writes the result
//  onto its cells. All pure value logic.
//

import XCTest
import AVFoundation
import CoreGraphics
@testable import ClaudeCollage

@MainActor
final class BeatSyncTests: XCTestCase {

    // MARK: - CellTransition.startTime

    func testStartTimeDefaultsToZero() {
        XCTAssertEqual(CellTransition(style: .crossfade).startTime, 0, accuracy: 1e-9)
    }

    func testStartTimeClampedNonNegative() {
        XCTAssertEqual(CellTransition(style: .crossfade, startTime: -3).startTime, 0, accuracy: 1e-9)
    }

    func testStartTimeRoundTripsAndDefaultsOnOldBlobs() throws {
        let original = CellTransition(style: .zoomIn, duration: 0.4, startTime: 1.25)
        let decoded = try JSONDecoder().decode(
            CellTransition.self, from: try JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)

        // A slice-4/5 blob with no startTime key must still decode (→ 0).
        let old = "{\"style\":\"crossfade\",\"duration\":0.5}".data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(CellTransition.self, from: old).startTime, 0, accuracy: 1e-9)
    }

    // MARK: - BeatSyncPlanner

    func testPlannerAssignsOneCellPerBeatInOrder() {
        let times = BeatSyncPlanner.startTimes(
            cellCount: 3, beats: [0.5, 1.0, 1.5, 2.0], within: 3)
        XCTAssertEqual(times, [0.5, 1.0, 1.5])
    }

    func testPlannerReusesLastBeatWhenFewerBeatsThanCells() {
        let times = BeatSyncPlanner.startTimes(
            cellCount: 4, beats: [0.5, 1.0], within: 3)
        XCTAssertEqual(times, [0.5, 1.0, 1.0, 1.0])
    }

    func testPlannerIgnoresBeatsPastTheDuration() {
        let times = BeatSyncPlanner.startTimes(
            cellCount: 2, beats: [0.5, 5.0], within: 3)
        XCTAssertEqual(times, [0.5, 0.5], "the 5s beat is outside a 3s clip and is dropped")
    }

    func testPlannerFallsBackToZeroWithoutBeats() {
        XCTAssertEqual(BeatSyncPlanner.startTimes(cellCount: 3, beats: [], within: 3), [0, 0, 0])
    }

    func testPlannerSortsUnorderedBeats() {
        let times = BeatSyncPlanner.startTimes(
            cellCount: 3, beats: [1.5, 0.5, 1.0], within: 3)
        XCTAssertEqual(times, [0.5, 1.0, 1.5])
    }

    // MARK: - View model integration

    private func makeViewModel() -> VideoEditorViewModel {
        VideoEditorViewModel(canvasSize: CGSize(width: 1080, height: 1080), layout: .grid(.fourSquare))
    }

    private func makeAsset() -> AVAsset {
        AVURLAsset(url: URL(fileURLWithPath: "/tmp/clip-\(UUID().uuidString).mov"))
    }

    func testApplyBeatSyncGivesEachCellAStartTime() {
        let vm = makeViewModel()
        vm.applyBeatSync(startTimes: [0.0, 0.5, 1.0, 1.5])
        XCTAssertEqual(vm.cells[1].transition?.startTime ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(vm.cells[3].transition?.startTime ?? -1, 1.5, accuracy: 1e-9)
    }

    func testApplyBeatSyncKeepsAnExistingTransitionStyle() {
        let vm = makeViewModel()
        vm.setTransition(CellTransition(style: .slideLeft, duration: 0.3), forCellAt: 0)
        vm.applyBeatSync(startTimes: [0.75, 0, 0, 0])
        XCTAssertEqual(vm.cells[0].transition?.style, .slideLeft, "sync retimes, it doesn't restyle")
        XCTAssertEqual(vm.cells[0].transition?.duration ?? -1, 0.3, accuracy: 1e-9)
        XCTAssertEqual(vm.cells[0].transition?.startTime ?? -1, 0.75, accuracy: 1e-9)
    }

    func testApplyBeatSyncGivesAPlainCellADefaultTransition() {
        let vm = makeViewModel()
        XCTAssertNil(vm.cells[2].transition)
        vm.applyBeatSync(startTimes: [0, 0, 1.0, 0])
        XCTAssertNotNil(vm.cells[2].transition, "a cell with no transition gets one so it can pop in")
        XCTAssertEqual(vm.cells[2].transition?.startTime ?? -1, 1.0, accuracy: 1e-9)
    }

    func testApplyBeatSyncIsUndoable() {
        let vm = makeViewModel()
        vm.applyBeatSync(startTimes: [0, 0.5, 1.0, 1.5])
        XCTAssertTrue(vm.canUndo)
        vm.undo()
        XCTAssertNil(vm.cells[1].transition, "undo removes the sync-applied transitions")
    }

    func testSyncToBeatsPlansThenApplies() {
        let vm = makeViewModel()
        vm.syncToBeats([0.5, 1.0, 1.5, 2.0], compositionDuration: 3)
        XCTAssertEqual(vm.cells[0].transition?.startTime ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(vm.cells[2].transition?.startTime ?? -1, 1.5, accuracy: 1e-9)
    }
}
