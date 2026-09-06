//
//  VideoStartOffsetTests.swift
//  CaroullageTests
//
//  Task 9 — a cell can begin after the others. Until now every clip started
//  together at zero, so this is the only slice that changes the composition
//  engine itself.
//
//  The first test is the one that matters most: a cell with `startOffset == 0`
//  must compose exactly as it did before, or this feature has quietly changed
//  every project ever saved. Everything else is additive on top of that.
//
//  Plan deviation: the plan said append to `CaroullageTests/Unit/VideoCompositionTests.swift`,
//  which does not exist — the builder's tests live in
//  `VideoCompositionOrientationTests` / `VideoTransitionTests` /
//  `VideoCompositionMathTests`. A new file rather than growing one of those,
//  since offsets cut across all three.
//

import AVFoundation
import CoreMedia
import XCTest
@testable import Caroullage

final class VideoStartOffsetTests: XCTestCase {

    private var scratch: [URL] = []

    override func tearDown() {
        for url in scratch { try? FileManager.default.removeItem(at: url) }
        scratch = []
        super.tearDown()
    }

    /// A real, decodable clip — the engine resolves tracks and durations off the
    /// asset, so a fake one short-circuits everything under test.
    private func makeClip(seconds: Double = 2) async throws -> AVURLAsset {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("offset-\(UUID().uuidString).mov")
        scratch.append(url)
        let size = CGSize(width: 32, height: 32)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
            ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        let fps = 10
        for frame in 0 ..< Int(seconds * Double(fps)) {
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, Int(size.width), Int(size.height),
                                kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
            let buffer = try XCTUnwrap(pixelBuffer)
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer), 0x40,
                   CVPixelBufferGetBytesPerRow(buffer) * Int(size.height))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            while !input.isReadyForMoreMediaData { await Task.yield() }
            adaptor.append(buffer, withPresentationTime:
                CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        return AVURLAsset(url: url)
    }

    private let canvas = CGSize(width: 100, height: 100)

    private func cell(
        _ asset: AVAsset, trim: VideoTrim, startOffset: Double = 0,
        isLooping: Bool = false, transition: CellTransition? = nil,
        frame: CGRect = CGRect(x: 0, y: 0, width: 100, height: 100)
    ) -> VideoCompositionCell {
        VideoCompositionCell(asset: asset, frame: frame, trim: trim, isLooping: isLooping,
                             transition: transition, startOffset: startOffset)
    }

    private func videoSegments(_ bundle: VideoCompositionBundle) -> [[AVCompositionTrackSegment]] {
        bundle.composition.tracks(withMediaType: .video).map(\.segments)
    }

    // MARK: - Backwards compatibility (the one that matters most)

    func testACellWithNoOffsetComposesExactlyAsBefore() async throws {
        let asset = try await makeClip(seconds: 2)
        let bundle = try await VideoComposer().buildComposition(
            cells: [cell(asset, trim: VideoTrim(start: 0, end: 1.5))], canvasSize: canvas)

        XCTAssertEqual(bundle.duration.seconds, 1.5, accuracy: 0.05,
                       "the composition is still exactly as long as its only clip")
        let segments = try XCTUnwrap(videoSegments(bundle).first)
        XCTAssertFalse(segments.contains(where: \.isEmpty),
                       "a clip with no offset must produce no leading gap at all")
        XCTAssertEqual(segments.first?.timeMapping.target.start.seconds ?? -1, 0, accuracy: 0.001)
    }

    func testAnUntimedTwoCellCollageIsUnchanged() async throws {
        let asset = try await makeClip(seconds: 2)
        let bundle = try await VideoComposer().buildComposition(
            cells: [cell(asset, trim: VideoTrim(start: 0, end: 1)),
                    cell(asset, trim: VideoTrim(start: 0, end: 1.8))],
            canvasSize: canvas)

        XCTAssertEqual(bundle.duration.seconds, 1.8, accuracy: 0.05,
                       "still the longest cell, exactly as before offsets existed")
        for segments in videoSegments(bundle) {
            XCTAssertFalse(segments.contains(where: \.isEmpty))
        }
    }

    // MARK: - Duration

    func testTheCompositionRunsUntilTheLastCellENDSNotTheLongestOne() async throws {
        // The whole point: a 1s clip starting at 2s ends at 3s, which is later
        // than a 1.8s clip that starts at zero. Taking the longest DURATION
        // (the old rule) would cut it off at 1.8s.
        let asset = try await makeClip(seconds: 2)
        let bundle = try await VideoComposer().buildComposition(
            cells: [cell(asset, trim: VideoTrim(start: 0, end: 1.8)),
                    cell(asset, trim: VideoTrim(start: 0, end: 1), startOffset: 2)],
            canvasSize: canvas)

        XCTAssertEqual(bundle.duration.seconds, 3, accuracy: 0.05)
    }

    // MARK: - The gap is real

    func testAnOffsetCellContributesNothingBeforeItsStart() async throws {
        let asset = try await makeClip(seconds: 2)
        let bundle = try await VideoComposer().buildComposition(
            cells: [cell(asset, trim: VideoTrim(start: 0, end: 1), startOffset: 1.5)],
            canvasSize: canvas)

        let segments = try XCTUnwrap(videoSegments(bundle).first)
        let leading = try XCTUnwrap(segments.first, "expected a leading segment")
        XCTAssertTrue(leading.isEmpty,
                      "the cell must be absent before its offset, not merely transparent")
        XCTAssertEqual(leading.timeMapping.target.duration.seconds, 1.5, accuracy: 0.05)

        let content = try XCTUnwrap(segments.first(where: { !$0.isEmpty }))
        XCTAssertEqual(content.timeMapping.target.start.seconds, 1.5, accuracy: 0.05,
                       "the clip itself starts at its offset")
    }

    func testALoopingCellWithAnOffsetFillsFromItsOffsetToTheEnd() async throws {
        let asset = try await makeClip(seconds: 2)
        let bundle = try await VideoComposer().buildComposition(
            cells: [cell(asset, trim: VideoTrim(start: 0, end: 4)),
                    cell(asset, trim: VideoTrim(start: 0, end: 0.5),
                         startOffset: 1, isLooping: true)],
            canvasSize: canvas)

        let looping = try XCTUnwrap(videoSegments(bundle).last)
        XCTAssertEqual(looping.first?.isEmpty, true, "it still waits for its offset")
        let filled = looping.filter { !$0.isEmpty }
        let end = try XCTUnwrap(filled.last).timeMapping.target.end.seconds
        XCTAssertEqual(end, bundle.duration.seconds, accuracy: 0.1,
                       "a looping cell fills from its offset to the end, not to offset + duration")
    }

    // MARK: - Transitions move with the cell

    func testATransitionFiresRelativeToTheCellsOwnStart() async throws {
        let asset = try await makeClip(seconds: 2)
        let bundle = try await VideoComposer().buildComposition(
            cells: [cell(asset, trim: VideoTrim(start: 0, end: 1.5),
                         startOffset: 1,
                         transition: CellTransition(style: .crossfade, duration: 0.5, startTime: 0))],
            canvasSize: canvas)

        let instruction = try XCTUnwrap(
            bundle.videoComposition.instructions.first as? AVVideoCompositionInstruction)
        let layer = try XCTUnwrap(instruction.layerInstructions.first)
        var from: Float = 0
        var to: Float = 0
        var range = CMTimeRange.zero
        XCTAssertTrue(layer.getOpacityRamp(for: CMTime(seconds: 1.1, preferredTimescale: 600),
                                           startOpacity: &from, endOpacity: &to, timeRange: &range))
        XCTAssertEqual(range.start.seconds, 1, accuracy: 0.05,
                       "a fade-in at the clip's own time 0 must happen when the clip appears, " +
                       "not a second before it while nothing is on screen")
    }

    // MARK: - Beat sync

    @MainActor
    func testBeatSyncExpressesTheBeatAgainstTheCellsOwnStart() {
        // `startTimes` are absolute times in the collage; `CellTransition.startTime`
        // is relative to the cell. A cell entering at 2s told to reveal on the
        // 3s beat must hold for 1s of its own life — not 3, which would put the
        // reveal at 5s.
        let vm = VideoEditorViewModel(canvasSize: CGSize(width: 100, height: 100),
                                      layout: .grid(.twoUpVertical))
        vm.setStartOffset(2, forCellAt: 1)

        vm.applyBeatSync(startTimes: [0, 3])

        XCTAssertEqual(vm.cells[0].transition?.startTime ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(vm.cells[1].transition?.startTime ?? -1, 1, accuracy: 0.001,
                       "3s absolute minus the cell's own 2s entry")
    }

    @MainActor
    func testABeatBeforeACellExistsCollapsesToItsEntry() {
        let vm = VideoEditorViewModel(canvasSize: CGSize(width: 100, height: 100),
                                      layout: .grid(.twoUpVertical))
        vm.setStartOffset(5, forCellAt: 0)

        vm.applyBeatSync(startTimes: [1, 0])

        XCTAssertEqual(vm.cells[0].transition?.startTime ?? -1, 0, accuracy: 0.001,
                       "the earliest a cell can appear is when it appears")
    }

    // MARK: - The view model's own setter

    @MainActor
    func testSettingAnOffsetIsUndoableAndClamped() {
        let vm = VideoEditorViewModel(canvasSize: CGSize(width: 100, height: 100),
                                      layout: .grid(.twoUpVertical))
        vm.setStartOffset(1.5, forCellAt: 0)
        XCTAssertEqual(vm.cells[0].startOffset, 1.5, accuracy: 0.001)

        vm.setStartOffset(-3, forCellAt: 0)
        XCTAssertEqual(vm.cells[0].startOffset, 0, "a negative offset is clamped, not stored")

        vm.undo()
        XCTAssertEqual(vm.cells[0].startOffset, 1.5, accuracy: 0.001)
    }

    // MARK: - The maths, without the engine

    func testCompositionDurationTakesTheLatestEnd() {
        XCTAssertEqual(
            VideoCompositionMath.compositionDuration(cellSpans: [(0, 4), (2, 3)]), 5, accuracy: 0.001)
        XCTAssertEqual(
            VideoCompositionMath.compositionDuration(cellSpans: [(0, 4), (1, 1)]), 4, accuracy: 0.001)
        XCTAssertEqual(VideoCompositionMath.compositionDuration(cellSpans: []), 0)
    }

    func testANegativeOffsetOrDurationCannotDragTheCompositionBackwards() {
        XCTAssertEqual(
            VideoCompositionMath.compositionDuration(cellSpans: [(-5, 2)]), 2, accuracy: 0.001)
        XCTAssertEqual(
            VideoCompositionMath.compositionDuration(cellSpans: [(1, -3)]), 1, accuracy: 0.001)
    }

    // MARK: - The model field

    func testStartOffsetDefaultsToZeroAndClampsNegatives() {
        XCTAssertEqual(VideoCellState().startOffset, 0)
        XCTAssertEqual(VideoCellState(startOffset: -4).startOffset, 0)
    }

    func testACellSavedBeforeOffsetsExistedDecodesToZero() throws {
        let json = Data(#"{"isLooping":false,"isMuted":false,"volume":1}"#.utf8)
        let cell = try JSONDecoder().decode(VideoCellState.self, from: json)
        XCTAssertEqual(cell.startOffset, 0)
    }

    func testANegativeOffsetInACorruptProjectIsClampedOnDecode() throws {
        let json = Data(#"{"startOffset":-9,"volume":1}"#.utf8)
        let cell = try JSONDecoder().decode(VideoCellState.self, from: json)
        XCTAssertEqual(cell.startOffset, 0)
    }

    func testStartOffsetRoundTrips() throws {
        let cell = VideoCellState(videoID: UUID(), startOffset: 2.5)
        let decoded = try JSONDecoder().decode(
            VideoCellState.self, from: try JSONEncoder().encode(cell))
        XCTAssertEqual(decoded.startOffset, 2.5, accuracy: 0.001)
    }
}
