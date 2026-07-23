//
//  VideoCompositionTests.swift
//  ClaudeCollageTests
//
//  Step 04 slice 3 — the AVMutableComposition assembly: one video track per cell,
//  per-cell trim (in/out), loop-to-fill, per-cell affine-transform layout, and an
//  AVMutableAudioMix carrying per-cell mute/volume. Exercised against REAL assets
//  generated on the fly (solid-colour videos via the slice-1 VideoComposer, plus a
//  silent-audio+video fixture), with the composited output read back frame-by-frame
//  through AVAssetReaderVideoCompositionOutput to prove cells land where intended.
//

import XCTest
import AVFoundation
import CoreGraphics
import CoreMedia
@testable import ClaudeCollage

final class VideoCompositionTests: XCTestCase {

    private var scratch: [URL] = []

    override func tearDown() {
        for url in scratch { try? FileManager.default.removeItem(at: url) }
        scratch = []
        super.tearDown()
    }

    // MARK: - Track assembly

    func testBuildsOneVideoTrackPerCell() async throws {
        let a = try await makeSolidVideo(r: 230, g: 20, b: 20, seconds: 1)
        let b = try await makeSolidVideo(r: 20, g: 20, b: 230, seconds: 1)
        let cells = [
            VideoCompositionCell(asset: AVURLAsset(url: a), frame: CGRect(x: 0, y: 0, width: 80, height: 160)),
            VideoCompositionCell(asset: AVURLAsset(url: b), frame: CGRect(x: 80, y: 0, width: 80, height: 160))
        ]
        let bundle = try await VideoComposer().buildComposition(cells: cells,
                                                                canvasSize: CGSize(width: 160, height: 160))
        let tracks = try await bundle.composition.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 2, "one composition video track per cell")
        XCTAssertEqual(bundle.renderSize, CGSize(width: 160, height: 160))
    }

    func testDurationIsLongestTrimmedCell() async throws {
        let a = try await makeSolidVideo(r: 200, g: 200, b: 200, seconds: 2)
        let b = try await makeSolidVideo(r: 100, g: 100, b: 100, seconds: 2)
        let cells = [
            VideoCompositionCell(asset: AVURLAsset(url: a), frame: unit(160),
                                 trim: VideoTrim(start: 0, end: 1.0)),
            VideoCompositionCell(asset: AVURLAsset(url: b), frame: unit(160),
                                 trim: VideoTrim(start: 0, end: 1.5))
        ]
        let bundle = try await VideoComposer().buildComposition(cells: cells, canvasSize: sq(160))
        XCTAssertEqual(bundle.duration.seconds, 1.5, accuracy: 0.1, "duration follows the longest cell")
    }

    func testTrimAppliesInOutPoints() async throws {
        let a = try await makeSolidVideo(r: 200, g: 100, b: 50, seconds: 2)
        let cell = VideoCompositionCell(asset: AVURLAsset(url: a), frame: unit(160),
                                        trim: VideoTrim(start: 0.5, end: 1.5))
        let bundle = try await VideoComposer().buildComposition(cells: [cell], canvasSize: sq(160))
        let track = try await bundle.composition.loadTracks(withMediaType: .video).first!
        let dur = try await track.load(.timeRange).duration.seconds
        XCTAssertEqual(dur, 1.0, accuracy: 0.1, "trimmed [0.5,1.5] → a 1s segment")
    }

    func testLoopFillsCompositionDuration() async throws {
        let short = try await makeSolidVideo(r: 10, g: 200, b: 10, seconds: 1)   // 1s, loops
        let long = try await makeSolidVideo(r: 10, g: 10, b: 200, seconds: 3)    // 3s, sets duration
        let cells = [
            VideoCompositionCell(asset: AVURLAsset(url: short), frame: unit(160), isLooping: true),
            VideoCompositionCell(asset: AVURLAsset(url: long), frame: unit(160))
        ]
        let bundle = try await VideoComposer().buildComposition(cells: cells, canvasSize: sq(160))
        let tracks = try await bundle.composition.loadTracks(withMediaType: .video)
        let shortDur = try await tracks[0].load(.timeRange).duration.seconds
        XCTAssertEqual(shortDur, bundle.duration.seconds, accuracy: 0.15,
                       "looping cell fills to the composition duration")
    }

    func testNonLoopingShortCellEndsEarly() async throws {
        let short = try await makeSolidVideo(r: 10, g: 200, b: 10, seconds: 1)
        let long = try await makeSolidVideo(r: 10, g: 10, b: 200, seconds: 3)
        let cells = [
            VideoCompositionCell(asset: AVURLAsset(url: short), frame: unit(160), isLooping: false),
            VideoCompositionCell(asset: AVURLAsset(url: long), frame: unit(160))
        ]
        let bundle = try await VideoComposer().buildComposition(cells: cells, canvasSize: sq(160))
        let tracks = try await bundle.composition.loadTracks(withMediaType: .video)
        let shortDur = try await tracks[0].load(.timeRange).duration.seconds
        XCTAssertEqual(shortDur, 1.0, accuracy: 0.1, "non-looping short cell does not fill the duration")
        XCTAssertLessThan(shortDur, bundle.duration.seconds - 0.5)
    }

    // MARK: - Audio mix

    func testVideoOnlySourceProducesNoAudioParams() async throws {
        let a = try await makeSolidVideo(r: 200, g: 200, b: 200, seconds: 1)  // slideshow has no audio
        let cell = VideoCompositionCell(asset: AVURLAsset(url: a), frame: unit(160))
        let bundle = try await VideoComposer().buildComposition(cells: [cell], canvasSize: sq(160))
        XCTAssertTrue(bundle.audioMix.inputParameters.isEmpty, "no source audio → nothing to mix")
    }

    func testAudioMixMutesCell() async throws {
        let av = try await makeSilentAudioVideo(seconds: 1)
        let cell = VideoCompositionCell(asset: AVURLAsset(url: av), frame: unit(160), isMuted: true)
        let bundle = try await VideoComposer().buildComposition(cells: [cell], canvasSize: sq(160))
        let params = try XCTUnwrap(bundle.audioMix.inputParameters.first)
        var start: Float = -1, end: Float = -1
        params.getVolumeRamp(for: .zero, startVolume: &start, endVolume: &end, timeRange: nil)
        XCTAssertEqual(start, 0, accuracy: 1e-4, "muted cell mixes at 0 gain")
    }

    func testAudioMixAppliesVolume() async throws {
        let av = try await makeSilentAudioVideo(seconds: 1)
        let cell = VideoCompositionCell(asset: AVURLAsset(url: av), frame: unit(160), volume: 0.4)
        let bundle = try await VideoComposer().buildComposition(cells: [cell], canvasSize: sq(160))
        let params = try XCTUnwrap(bundle.audioMix.inputParameters.first)
        var start: Float = -1, end: Float = -1
        params.getVolumeRamp(for: .zero, startVolume: &start, endVolume: &end, timeRange: nil)
        XCTAssertEqual(start, 0.4, accuracy: 1e-4, "volume 0.4 → 0.4 mix gain")
    }

    // MARK: - Per-cell affine-transform placement (composited pixel readback)

    func testHorizontalSplitPlacesCellsLeftAndRight() async throws {
        let red = try await makeSolidVideo(r: 235, g: 20, b: 20, seconds: 1)
        let blue = try await makeSolidVideo(r: 20, g: 20, b: 235, seconds: 1)
        let cells = [
            VideoCompositionCell(asset: AVURLAsset(url: red), frame: CGRect(x: 0, y: 0, width: 80, height: 160)),
            VideoCompositionCell(asset: AVURLAsset(url: blue), frame: CGRect(x: 80, y: 0, width: 80, height: 160))
        ]
        let bundle = try await VideoComposer().buildComposition(cells: cells, canvasSize: sq(160))
        let left = try await compositedPixel(bundle, x: 40, y: 80)
        let right = try await compositedPixel(bundle, x: 120, y: 80)
        XCTAssertGreaterThan(left.r, 150); XCTAssertLessThan(left.b, 90)   // left cell = red
        XCTAssertGreaterThan(right.b, 150); XCTAssertLessThan(right.r, 90) // right cell = blue
    }

    func testVerticalSplitPlacesCellsTopAndBottom() async throws {
        let red = try await makeSolidVideo(r: 235, g: 20, b: 20, seconds: 1)
        let blue = try await makeSolidVideo(r: 20, g: 20, b: 235, seconds: 1)
        let cells = [
            VideoCompositionCell(asset: AVURLAsset(url: red), frame: CGRect(x: 0, y: 0, width: 160, height: 80)),
            VideoCompositionCell(asset: AVURLAsset(url: blue), frame: CGRect(x: 0, y: 80, width: 160, height: 80))
        ]
        let bundle = try await VideoComposer().buildComposition(cells: cells, canvasSize: sq(160))
        let top = try await compositedPixel(bundle, x: 80, y: 40)
        let bottom = try await compositedPixel(bundle, x: 80, y: 120)
        XCTAssertGreaterThan(top.r, 150); XCTAssertLessThan(top.b, 90)      // top cell = red
        XCTAssertGreaterThan(bottom.b, 150); XCTAssertLessThan(bottom.r, 90)// bottom cell = blue
    }

    // MARK: - Overlay baking (composited at write-time in export)

    func testStickerOverlayBakesIntoExport() async throws {
        let red = try await makeSolidVideo(r: 220, g: 30, b: 30, seconds: 1)
        // A green square sticker in the TOP region (centre y = 0.25), over red video.
        let sticker = StickerOverlay(symbolName: "square.fill", colorHex: "#20E020",
                                     center: CGPoint(x: 0.5, y: 0.25), sizeNorm: 0.5)
        let cell = VideoCompositionCell(asset: AVURLAsset(url: red), frame: unit(160))
        let bundle = try await VideoComposer().buildComposition(
            cells: [cell], canvasSize: sq(160), stickerOverlays: [sticker])
        let out = tempURL(ext: "mp4")
        try await VideoComposer().export(bundle: bundle, to: out)

        let top = try await filePixel(out, x: 80, y: 40)     // inside the sticker box
        let bottom = try await filePixel(out, x: 80, y: 135) // below it → bare video
        XCTAssertGreaterThan(top.g, 120, "green sticker baked into the exported top region")
        XCTAssertLessThan(top.r, 120)
        XCTAssertGreaterThan(bottom.r, 150, "video (red) shows where no overlay covers")
        XCTAssertLessThan(bottom.g, 120)
    }

    // MARK: - Transitions (layer-instruction ramps)

    func testCrossfadeAddsOpacityRamp() async throws {
        let v = try await makeSolidVideo(r: 200, g: 200, b: 200, seconds: 1)
        let cell = VideoCompositionCell(asset: AVURLAsset(url: v), frame: unit(160),
                                        transition: CellTransition(style: .crossfade, duration: 0.5))
        let bundle = try await VideoComposer().buildComposition(cells: [cell], canvasSize: sq(160))
        let layer = try XCTUnwrap(firstLayerInstruction(bundle))
        var start: Float = -1, end: Float = -1
        var range = CMTimeRange.zero
        XCTAssertTrue(layer.getOpacityRamp(for: .zero, startOpacity: &start, endOpacity: &end, timeRange: &range))
        XCTAssertEqual(start, 0, accuracy: 1e-4)
        XCTAssertEqual(end, 1, accuracy: 1e-4)
    }

    func testSlideAddsTransformRamp() async throws {
        let v = try await makeSolidVideo(r: 200, g: 200, b: 200, seconds: 1)
        let cell = VideoCompositionCell(asset: AVURLAsset(url: v), frame: unit(160),
                                        transition: CellTransition(style: .slideLeft, duration: 0.5))
        let bundle = try await VideoComposer().buildComposition(cells: [cell], canvasSize: sq(160))
        let layer = try XCTUnwrap(firstLayerInstruction(bundle))
        var start = CGAffineTransform.identity, end = CGAffineTransform.identity
        var range = CMTimeRange.zero
        XCTAssertTrue(layer.getTransformRamp(for: .zero, start: &start, end: &end, timeRange: &range))
        XCTAssertNotEqual(start, end, "slide ramps the transform from an offset to rest")
    }

    func testCrossfadeFirstFrameShowsBackground() async throws {
        // A white cell with a crossfade is (near) transparent at t=0 → dark bg.
        let white = try await makeSolidVideo(r: 235, g: 235, b: 235, seconds: 1)
        let cell = VideoCompositionCell(asset: AVURLAsset(url: white), frame: unit(160),
                                        transition: CellTransition(style: .crossfade, duration: 0.5))
        let bundle = try await VideoComposer().buildComposition(cells: [cell], canvasSize: sq(160))
        let px = try await compositedPixel(bundle, x: 80, y: 80)
        XCTAssertLessThan(px.r, 90, "crossfade starts transparent → dark at t=0")
        XCTAssertLessThan(px.g, 90)
        XCTAssertLessThan(px.b, 90)
    }

    func testNoTransitionIsFullyOpaque() async throws {
        let v = try await makeSolidVideo(r: 200, g: 200, b: 200, seconds: 1)
        let cell = VideoCompositionCell(asset: AVURLAsset(url: v), frame: unit(160))
        let bundle = try await VideoComposer().buildComposition(cells: [cell], canvasSize: sq(160))
        let layer = try XCTUnwrap(firstLayerInstruction(bundle))
        var start: Float = -1, end: Float = -1
        var range = CMTimeRange.zero
        XCTAssertFalse(layer.getOpacityRamp(for: .zero, startOpacity: &start, endOpacity: &end, timeRange: &range),
                       "a cell with no transition has no opacity ramp")
    }

    // MARK: - Beat-synced transition start (slice 6c)

    func testTransitionStartTimeShiftsTheRampWindow() async throws {
        let v = try await makeSolidVideo(r: 200, g: 200, b: 200, seconds: 2)
        let cell = VideoCompositionCell(
            asset: AVURLAsset(url: v), frame: unit(160),
            transition: CellTransition(style: .crossfade, duration: 0.5, startTime: 0.8))
        let bundle = try await VideoComposer().buildComposition(cells: [cell], canvasSize: sq(160))
        let layer = try XCTUnwrap(firstLayerInstruction(bundle))
        var start: Float = -1, end: Float = -1
        var range = CMTimeRange.zero
        XCTAssertTrue(layer.getOpacityRamp(for: CMTime(seconds: 0.8, preferredTimescale: 600),
                                           startOpacity: &start, endOpacity: &end, timeRange: &range))
        XCTAssertEqual(range.start.seconds, 0.8, accuracy: 0.05, "the fade-in begins on the beat, not at t=0")
        XCTAssertEqual(range.duration.seconds, 0.5, accuracy: 0.05)
    }

    func testCellHeldTransparentBeforeItsBeatThenVisibleAfter() async throws {
        // A white cell that fades in at t=1.0: dark before the beat, bright after.
        let white = try await makeSolidVideo(r: 235, g: 235, b: 235, seconds: 2)
        let cell = VideoCompositionCell(
            asset: AVURLAsset(url: white), frame: unit(160),
            transition: CellTransition(style: .crossfade, duration: 0.3, startTime: 1.0))
        let bundle = try await VideoComposer().buildComposition(cells: [cell], canvasSize: sq(160))

        let before = try await compositedPixel(bundle, x: 80, y: 80, atSeconds: 0.3)
        let after = try await compositedPixel(bundle, x: 80, y: 80, atSeconds: 1.6)
        XCTAssertLessThan(before.r, 90, "held transparent (dark) before the beat")
        XCTAssertGreaterThan(after.r, 150, "faded in (bright) after the beat")
    }

    // MARK: - Mixed photo + video

    func testMixedPhotoAndVideoComposition() async throws {
        let redVideo = try await makeSolidVideo(r: 230, g: 20, b: 20, seconds: 2) // left, drives duration
        let bluePhoto = solidImage(160, r: 20, g: 20, b: 230)                     // right, still photo
        let videoCell = VideoCompositionCell(asset: AVURLAsset(url: redVideo),
                                             frame: CGRect(x: 0, y: 0, width: 80, height: 160))
        let stillURL = tempURL(ext: "mp4")
        let photoCell = try await VideoComposer().photoCell(
            image: bluePhoto, frame: CGRect(x: 80, y: 0, width: 80, height: 160), to: stillURL)

        let bundle = try await VideoComposer().buildComposition(cells: [videoCell, photoCell], canvasSize: sq(160))
        let tracks = try await bundle.composition.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 2, "photo cell joins the composition as a video track")
        XCTAssertEqual(bundle.duration.seconds, 2.0, accuracy: 0.15, "duration follows the 2s video; the photo loops")

        let left = try await compositedPixel(bundle, x: 40, y: 80)    // video → red
        let right = try await compositedPixel(bundle, x: 120, y: 80)  // photo → blue
        XCTAssertGreaterThan(left.r, 150); XCTAssertLessThan(left.b, 90)
        XCTAssertGreaterThan(right.b, 150); XCTAssertLessThan(right.r, 90)
    }

    // MARK: - Audio muxing into export (slice 5a)

    func testExportMuxesCellAudioTrack() async throws {
        // A cell whose source carries audio → the exported file has an audio track
        // (slice 4 export was video-only).
        let av = try await makeSilentAudioVideo(seconds: 1)
        let cell = VideoCompositionCell(asset: AVURLAsset(url: av), frame: unit(160))
        let bundle = try await VideoComposer().buildComposition(cells: [cell], canvasSize: sq(160))
        let out = tempURL(ext: "mp4")
        try await VideoComposer().export(bundle: bundle, to: out)
        let audio = try await AVURLAsset(url: out).loadTracks(withMediaType: .audio)
        XCTAssertEqual(audio.count, 1, "cell audio is muxed into the exported file")
    }

    func testBackgroundMusicMixesIntoExport() async throws {
        // A silent-source video (no cell audio) + a background-music track → the
        // export carries audible audio that can only have come from the music.
        let silent = try await makeSolidVideo(r: 200, g: 200, b: 200, seconds: 1)  // no audio
        let music = try await makeToneAudio(seconds: 2)
        let cell = VideoCompositionCell(asset: AVURLAsset(url: silent), frame: unit(160))
        let bundle = try await VideoComposer().buildComposition(
            cells: [cell], canvasSize: sq(160),
            music: BackgroundMusic(asset: AVURLAsset(url: music), volume: 1))
        let out = tempURL(ext: "mp4")
        try await VideoComposer().export(bundle: bundle, to: out)

        let audio = try await AVURLAsset(url: out).loadTracks(withMediaType: .audio)
        XCTAssertEqual(audio.count, 1, "background music is muxed even when cells are silent")
        let rms = try await audioRMS(out)
        XCTAssertGreaterThan(rms, 0.02, "the music tone is audible in the export")
    }

    func testBackgroundMusicVolumeZeroIsSilent() async throws {
        let silent = try await makeSolidVideo(r: 200, g: 200, b: 200, seconds: 1)
        let music = try await makeToneAudio(seconds: 2)
        let cell = VideoCompositionCell(asset: AVURLAsset(url: silent), frame: unit(160))
        let bundle = try await VideoComposer().buildComposition(
            cells: [cell], canvasSize: sq(160),
            music: BackgroundMusic(asset: AVURLAsset(url: music), volume: 0))
        let out = tempURL(ext: "mp4")
        try await VideoComposer().export(bundle: bundle, to: out)
        let rms = try await audioRMS(out)
        XCTAssertLessThan(rms, 0.01, "music mixed at 0 gain → (near) silent export")
    }

    func testBackgroundMusicAddsTrackTrimmedToDuration() async throws {
        // Music longer than the composition is trimmed to the composition duration,
        // and rides the audio mix at its own gain — even with silent cells.
        let video = try await makeSolidVideo(r: 100, g: 100, b: 100, seconds: 1)  // 1s → duration
        let music = try await makeToneAudio(seconds: 5)                            // 5s → trimmed
        let cell = VideoCompositionCell(asset: AVURLAsset(url: video), frame: unit(160))
        let bundle = try await VideoComposer().buildComposition(
            cells: [cell], canvasSize: sq(160),
            music: BackgroundMusic(asset: AVURLAsset(url: music), volume: 0.5))
        let audio = try await bundle.composition.loadTracks(withMediaType: .audio)
        XCTAssertEqual(audio.count, 1, "music track added even though the cell has no audio")
        let dur = try await audio[0].load(.timeRange).duration.seconds
        XCTAssertEqual(dur, bundle.duration.seconds, accuracy: 0.1, "music trimmed to composition duration")
        XCTAssertEqual(bundle.audioMix.inputParameters.count, 1, "music gets a mix parameter")
    }

    // MARK: - Archiving a non-file-backed asset (slice 5d)

    /// Photos hands back slo-mo clips as an `AVComposition`, which has no file URL,
    /// so it can't be copied into a project on save. `AVMutableComposition` is the
    /// same shape of thing, and stands in for it headlessly here.
    private func makeNonFileBackedAsset(from url: URL, withAudio: Bool = false) async throws -> AVAsset {
        let source = AVURLAsset(url: url)
        let duration = try await source.load(.duration)
        let composition = AVMutableComposition()
        if let videoTrack = try await source.loadTracks(withMediaType: .video).first,
           let track = composition.addMutableTrack(withMediaType: .video,
                                                   preferredTrackID: kCMPersistentTrackID_Invalid) {
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration),
                                      of: videoTrack, at: .zero)
        }
        if withAudio, let audioTrack = try await source.loadTracks(withMediaType: .audio).first,
           let track = composition.addMutableTrack(withMediaType: .audio,
                                                   preferredTrackID: kCMPersistentTrackID_Invalid) {
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration),
                                      of: audioTrack, at: .zero)
        }
        return composition
    }

    func testArchiveWritesAPlayableFileFromANonFileBackedAsset() async throws {
        let source = try await makeSolidVideo(r: 225, g: 35, b: 35, seconds: 1)
        let asset = try await makeNonFileBackedAsset(from: source)
        XCTAssertNil(asset as? AVURLAsset, "the stand-in really has no file URL")

        let out = tempURL(ext: "mp4")
        try await VideoComposer().archive(asset: asset, to: out)

        XCTAssertTrue(FileManager.default.fileExists(atPath: out.path))
        let archived = AVURLAsset(url: out)
        let tracks = try await archived.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1, "the archived file carries the video")
        let pixel = try await filePixel(out, x: 80, y: 80)
        XCTAssertGreaterThan(pixel.r, 150, "the archived frames are the source frames")
        XCTAssertLessThan(pixel.b, 90)
    }

    func testArchivePreservesDuration() async throws {
        let source = try await makeSolidVideo(r: 90, g: 90, b: 200, seconds: 2)
        let asset = try await makeNonFileBackedAsset(from: source)
        let out = tempURL(ext: "mp4")
        try await VideoComposer().archive(asset: asset, to: out)

        let duration = try await AVURLAsset(url: out).load(.duration).seconds
        XCTAssertEqual(duration, 2.0, accuracy: 0.2, "archiving keeps the clip's length")
    }

    func testArchiveKeepsAudio() async throws {
        let source = try await makeSilentAudioVideo(seconds: 1)
        let asset = try await makeNonFileBackedAsset(from: source, withAudio: true)
        let out = tempURL(ext: "mp4")
        try await VideoComposer().archive(asset: asset, to: out)

        let audio = try await AVURLAsset(url: out).loadTracks(withMediaType: .audio)
        XCTAssertEqual(audio.count, 1, "the clip's audio survives archiving")
    }

    func testArchiveIsCancellable() async throws {
        let source = try await makeSolidVideo(r: 10, g: 10, b: 10, seconds: 1)
        let asset = try await makeNonFileBackedAsset(from: source)
        let out = tempURL(ext: "mp4")
        let token = ExportCancellationToken()
        token.cancel()
        do {
            try await VideoComposer().archive(asset: asset, to: out, cancellation: token)
            XCTFail("a cancelled archive must not complete")
        } catch let error as VideoComposer.ComposerError {
            XCTAssertEqual(error, .cancelled)
        }
    }

    // MARK: - Aspect-fill + crop (quality-hardening #4)

    /// A solid-colour video at an explicit (possibly non-square) size.
    private func makeSolidVideoSized(_ size: CGSize, r: UInt8, g: UInt8, b: UInt8,
                                     seconds: Double = 1) async throws -> URL {
        let url = tempURL(ext: "mp4")
        let image = solidImage(Int(size.width), r: r, g: g, b: b)   // colour is what matters
        try await VideoComposer().renderSlideshow(frames: [image], size: size,
                                                  secondsPerFrame: seconds, to: url)
        return url
    }

    func testFillCoversTheCellWithNoLetterbox() async throws {
        // A wide 320×160 source in a tall 80×160 cell: aspect-FIT would leave black
        // bars top and bottom; aspect-FILL must cover the whole cell.
        let wide = try await makeSolidVideoSized(CGSize(width: 320, height: 160), r: 230, g: 30, b: 30)
        let cell = VideoCompositionCell(asset: AVURLAsset(url: wide),
                                        frame: CGRect(x: 0, y: 0, width: 80, height: 160))
        let bundle = try await VideoComposer().buildComposition(cells: [cell], canvasSize: sq(160))
        // Top and bottom of the cell — the letterbox zones under fit.
        let top = try await compositedPixel(bundle, x: 40, y: 8)
        let bottom = try await compositedPixel(bundle, x: 40, y: 152)
        XCTAssertGreaterThan(top.r, 150, "cell top is covered by video, not a black bar")
        XCTAssertGreaterThan(bottom.r, 150, "cell bottom is covered too")
    }

    func testFilledCellDoesNotOverflowIntoItsNeighbour() async throws {
        // Left cell filled with a wide red source; right cell blue. If fill didn't
        // crop, the scaled-up red would bleed past the divider into the right cell.
        let wideRed = try await makeSolidVideoSized(CGSize(width: 320, height: 160), r: 230, g: 30, b: 30)
        let blue = try await makeSolidVideoSized(CGSize(width: 160, height: 160), r: 30, g: 30, b: 230)
        let cells = [
            VideoCompositionCell(asset: AVURLAsset(url: wideRed), frame: CGRect(x: 0, y: 0, width: 80, height: 160)),
            VideoCompositionCell(asset: AVURLAsset(url: blue), frame: CGRect(x: 80, y: 0, width: 80, height: 160))
        ]
        let bundle = try await VideoComposer().buildComposition(cells: cells, canvasSize: sq(160))
        let rightNearDivider = try await compositedPixel(bundle, x: 88, y: 80)  // just inside the right cell
        XCTAssertGreaterThan(rightNearDivider.b, 150, "right cell stays blue")
        XCTAssertLessThan(rightNearDivider.r, 90, "the filled left cell is cropped — no red bleed")
    }

    // MARK: - Per-cell pan/zoom framing (quality-hardening #5)

    /// A video whose left half is `left` and right half is `right`.
    private func makeTwoToneVideo(width: Int, height: Int,
                                  left: (UInt8, UInt8, UInt8), right: (UInt8, UInt8, UInt8)) async throws -> URL {
        let bpr = width * 4
        var px = [UInt8](repeating: 0, count: bpr * height)
        for y in 0..<height {
            for x in 0..<width {
                let i = y * bpr + x * 4
                let c = x < width / 2 ? left : right
                px[i] = c.0; px[i + 1] = c.1; px[i + 2] = c.2; px[i + 3] = 255
            }
        }
        let ctx = CGContext(data: &px, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bpr,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = ctx.makeImage()!
        let url = tempURL(ext: "mp4")
        try await VideoComposer().renderSlideshow(frames: [image],
                                                  size: CGSize(width: width, height: height),
                                                  secondsPerFrame: 1, to: url)
        return url
    }

    func testPanningACellChangesWhichPartOfTheClipIsShown() async throws {
        // A wide left=red / right=blue clip in a square cell. Panning fully left
        // shows red at the cell centre; panning right shows blue.
        let source = try await makeTwoToneVideo(width: 200, height: 100,
                                                left: (230, 30, 30), right: (30, 30, 230))
        func centrePixel(panX: Double) async throws -> (r: UInt8, g: UInt8, b: UInt8) {
            let cell = VideoCompositionCell(
                asset: AVURLAsset(url: source), frame: unit(160),
                transform: CellTransform(panX: panX))
            let bundle = try await VideoComposer().buildComposition(cells: [cell], canvasSize: sq(160))
            return try await compositedPixel(bundle, x: 80, y: 80)
        }
        let panLeft = try await centrePixel(panX: -1)
        let panRight = try await centrePixel(panX: 1)
        XCTAssertGreaterThan(panLeft.r, 150, "panned left → red half fills the cell")
        XCTAssertLessThan(panLeft.b, 90)
        XCTAssertGreaterThan(panRight.b, 150, "panned right → blue half fills the cell")
        XCTAssertLessThan(panRight.r, 90)
    }

    // MARK: - Export render size (quality-hardening #1)

    func testBuildRespectsAnExplicitRenderSize() async throws {
        let red = try await makeSolidVideo(r: 235, g: 20, b: 20, seconds: 1)
        let cell = VideoCompositionCell(asset: AVURLAsset(url: red), frame: unit(160))
        let bundle = try await VideoComposer().buildComposition(
            cells: [cell], canvasSize: sq(160), renderSize: CGSize(width: 320, height: 320))
        XCTAssertEqual(bundle.renderSize, CGSize(width: 320, height: 320))
        XCTAssertEqual(bundle.videoComposition.renderSize, CGSize(width: 320, height: 320))
    }

    func testExportedFileMatchesTheRenderSize() async throws {
        let red = try await makeSolidVideo(r: 235, g: 20, b: 20, seconds: 1)
        let cell = VideoCompositionCell(asset: AVURLAsset(url: red), frame: unit(160))
        let bundle = try await VideoComposer().buildComposition(
            cells: [cell], canvasSize: sq(160), renderSize: CGSize(width: 480, height: 480))
        let out = tempURL(ext: "mp4")
        try await VideoComposer().export(bundle: bundle, to: out)
        let track = try await AVURLAsset(url: out).loadTracks(withMediaType: .video).first!
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size.width, 480, accuracy: 1, "the exported file is at the requested resolution")
        XCTAssertEqual(size.height, 480, accuracy: 1)
    }

    func testRenderSizeScalesCellPlacement() async throws {
        // Horizontal split rendered at 2×: the left/right cells still land left/right.
        let red = try await makeSolidVideo(r: 235, g: 20, b: 20, seconds: 1)
        let blue = try await makeSolidVideo(r: 20, g: 20, b: 235, seconds: 1)
        let cells = [
            VideoCompositionCell(asset: AVURLAsset(url: red), frame: CGRect(x: 0, y: 0, width: 80, height: 160)),
            VideoCompositionCell(asset: AVURLAsset(url: blue), frame: CGRect(x: 80, y: 0, width: 80, height: 160))
        ]
        let bundle = try await VideoComposer().buildComposition(
            cells: cells, canvasSize: sq(160), renderSize: CGSize(width: 320, height: 320))
        let left = try await compositedPixel(bundle, x: 80, y: 160)    // left half at 2×
        let right = try await compositedPixel(bundle, x: 240, y: 160)  // right half at 2×
        XCTAssertGreaterThan(left.r, 150); XCTAssertLessThan(left.b, 90)
        XCTAssertGreaterThan(right.b, 150); XCTAssertLessThan(right.r, 90)
    }

    // MARK: - Cancellation (slice 6a)

    func testCancelledExportThrowsCancelledAndLeavesNoFile() async throws {
        let video = try await makeSolidVideo(r: 120, g: 120, b: 120, seconds: 1)
        let cell = VideoCompositionCell(asset: AVURLAsset(url: video), frame: unit(160))
        let bundle = try await VideoComposer().buildComposition(cells: [cell], canvasSize: sq(160))
        let out = tempURL(ext: "mp4")

        let token = ExportCancellationToken()
        token.cancel()   // already cancelled → the write loop must bail on its first check

        do {
            try await VideoComposer().export(bundle: bundle, to: out, cancellation: token)
            XCTFail("a cancelled export must not complete")
        } catch let error as VideoComposer.ComposerError {
            XCTAssertEqual(error, .cancelled)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path),
                       "a cancelled export cleans up its partial file")
    }

    func testCancelledSlideshowThrowsCancelled() async throws {
        let out = tempURL(ext: "mp4")
        let token = ExportCancellationToken()
        token.cancel()
        do {
            try await VideoComposer().renderSlideshow(
                frames: [solidImage(160, r: 10, g: 10, b: 10)], size: sq(160),
                secondsPerFrame: 1, to: out, cancellation: token)
            XCTFail("a cancelled slideshow must not complete")
        } catch let error as VideoComposer.ComposerError {
            XCTAssertEqual(error, .cancelled)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path))
    }

    func testUncancelledExportStillCompletesAndReportsFullProgress() async throws {
        let video = try await makeSolidVideo(r: 60, g: 180, b: 60, seconds: 1)
        let cell = VideoCompositionCell(asset: AVURLAsset(url: video), frame: unit(160))
        let bundle = try await VideoComposer().buildComposition(cells: [cell], canvasSize: sq(160))
        let out = tempURL(ext: "mp4")

        let recorder = ProgressRecorder()
        try await VideoComposer().export(bundle: bundle, to: out,
                                         progress: { recorder.record($0) },
                                         cancellation: ExportCancellationToken())

        XCTAssertTrue(FileManager.default.fileExists(atPath: out.path))
        XCTAssertGreaterThan(recorder.values.count, 0, "progress is reported during the export")
        XCTAssertEqual(recorder.values.last ?? 0, 1.0, accuracy: 0.15,
                       "progress runs through to (about) 1.0")
        XCTAssertTrue(recorder.isMonotonic, "progress never goes backwards")
    }

    /// Collects progress callbacks from the exporter's private queue.
    private final class ProgressRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [Float] = []
        func record(_ value: Float) {
            lock.lock(); storage.append(value); lock.unlock()
        }
        var values: [Float] {
            lock.lock(); defer { lock.unlock() }; return storage
        }
        var isMonotonic: Bool {
            let snapshot = values
            return zip(snapshot, snapshot.dropFirst()).allSatisfy { $0 <= $1 }
        }
    }

    // MARK: - Fixtures & helpers

    private func firstLayerInstruction(_ bundle: VideoCompositionBundle) -> AVVideoCompositionLayerInstruction? {
        (bundle.videoComposition.instructions.first as? AVVideoCompositionInstruction)?.layerInstructions.first
    }


    private func sq(_ side: CGFloat) -> CGSize { CGSize(width: side, height: side) }
    private func unit(_ side: CGFloat) -> CGRect { CGRect(x: 0, y: 0, width: side, height: side) }

    private func tempURL(ext: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VidCompTest-\(UUID().uuidString).\(ext)")
        scratch.append(url)
        return url
    }

    private func solidImage(_ side: Int, r: UInt8, g: UInt8, b: UInt8) -> CGImage {
        let bpr = side * 4
        var px = [UInt8](repeating: 0, count: bpr * side)
        for p in stride(from: 0, to: px.count, by: 4) {
            px[p] = r; px[p + 1] = g; px[p + 2] = b; px[p + 3] = 255
        }
        let ctx = CGContext(data: &px, width: side, height: side, bitsPerComponent: 8, bytesPerRow: bpr,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    /// A solid-colour video (no audio) via the slice-1 slideshow writer.
    private func makeSolidVideo(r: UInt8, g: UInt8, b: UInt8, seconds: Double) async throws -> URL {
        let url = tempURL(ext: "mp4")
        try await VideoComposer().renderSlideshow(frames: [solidImage(160, r: r, g: g, b: b)],
                                                  size: sq(160), secondsPerFrame: seconds, to: url)
        return url
    }

    /// A short video that also carries a (silent) mono AAC audio track, so the
    /// audio-mix path has a real track to attach parameters to.
    private func makeSilentAudioVideo(seconds: Double) async throws -> URL {
        let url = tempURL(ext: "mov")
        try? FileManager.default.removeItem(at: url)
        let side = 160
        let writer = try AVAssetWriter(url: url, fileType: .mov)

        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: side, AVVideoHeightKey: side])
        vInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: vInput,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                          kCVPixelBufferWidthKey as String: side,
                                          kCVPixelBufferHeightKey as String: side])

        let sampleRate = 44_100.0
        let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: 1,
            AVSampleRateKey: sampleRate, AVEncoderBitRateKey: 64_000])
        aInput.expectsMediaDataInRealTime = false

        writer.add(vInput)
        writer.add(aInput)
        guard writer.startWriting() else { throw writer.error ?? NSError(domain: "fixture", code: 1) }
        writer.startSession(atSourceTime: .zero)

        let fps = 30
        let frameTotal = Int(seconds * Double(fps))
        let img = solidImage(side, r: 120, g: 120, b: 120)
        for f in 0..<frameTotal {
            while !vInput.isReadyForMoreMediaData { try? await Task.sleep(nanoseconds: 2_000_000) }
            guard let pb = pixelBuffer(from: img, side: side) else { break }
            adaptor.append(pb, withPresentationTime: CMTime(value: Int64(f), timescale: Int32(fps)))
        }
        vInput.markAsFinished()

        let chunk = 1024
        let audioTotal = Int(seconds * sampleRate)
        var written = 0
        while written < audioTotal {
            while !aInput.isReadyForMoreMediaData { try? await Task.sleep(nanoseconds: 2_000_000) }
            let n = min(chunk, audioTotal - written)
            guard let sb = silenceBuffer(sampleRate: sampleRate, frames: n,
                                         pts: CMTime(value: Int64(written), timescale: Int32(sampleRate))) else { break }
            aInput.append(sb)
            written += n
        }
        aInput.markAsFinished()

        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            writer.finishWriting { c.resume() }
        }
        return url
    }

    /// An audio-only file carrying a real (non-silent) sine tone, so the
    /// background-music path has something audible to mix and read back.
    private func makeToneAudio(seconds: Double, frequency: Double = 440) async throws -> URL {
        let url = tempURL(ext: "m4a")
        try? FileManager.default.removeItem(at: url)
        let sampleRate = 44_100.0
        let writer = try AVAssetWriter(url: url, fileType: .m4a)
        let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: 1,
            AVSampleRateKey: sampleRate, AVEncoderBitRateKey: 96_000])
        aInput.expectsMediaDataInRealTime = false
        writer.add(aInput)
        guard writer.startWriting() else { throw writer.error ?? NSError(domain: "fixture", code: 2) }
        writer.startSession(atSourceTime: .zero)

        let chunk = 1024
        let total = Int(seconds * sampleRate)
        var written = 0
        while written < total {
            while !aInput.isReadyForMoreMediaData { try? await Task.sleep(nanoseconds: 2_000_000) }
            let n = min(chunk, total - written)
            guard let sb = toneBuffer(sampleRate: sampleRate, frames: n, startFrame: written,
                                      frequency: frequency,
                                      pts: CMTime(value: Int64(written), timescale: Int32(sampleRate))) else { break }
            aInput.append(sb)
            written += n
        }
        aInput.markAsFinished()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            writer.finishWriting { c.resume() }
        }
        return url
    }

    private func toneBuffer(sampleRate: Double, frames: Int, startFrame: Int,
                            frequency: Double, pts: CMTime) -> CMSampleBuffer? {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
            mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0,
                                             layout: nil, magicCookieSize: 0, magicCookie: nil,
                                             extensions: nil, formatDescriptionOut: &format) == noErr,
              let format else { return nil }
        var samples = [Int16](repeating: 0, count: frames)
        let amp = 0.6 * Double(Int16.max)
        for i in 0..<frames {
            let t = Double(startFrame + i) / sampleRate
            samples[i] = Int16(amp * sin(2 * .pi * frequency * t))
        }
        let dataSize = frames * 2
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
                                                 blockLength: dataSize, blockAllocator: kCFAllocatorDefault,
                                                 customBlockSource: nil, offsetToData: 0, dataLength: dataSize,
                                                 flags: kCMBlockBufferAssureMemoryNowFlag,
                                                 blockBufferOut: &block) == kCMBlockBufferNoErr,
              let block else { return nil }
        _ = samples.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block,
                                          offsetIntoDestination: 0, dataLength: dataSize)
        }
        var sample: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: Int32(sampleRate)),
                                        presentationTimeStamp: pts, decodeTimeStamp: .invalid)
        var sizeArr = [2]
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block,
                                        formatDescription: format, sampleCount: frames,
                                        sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                        sampleSizeEntryCount: 1, sampleSizeArray: &sizeArr,
                                        sampleBufferOut: &sample) == noErr else { return nil }
        return sample
    }

    /// Decodes the exported file's audio track to 16-bit PCM and returns its RMS
    /// amplitude in 0…1 — a proxy for "is there audible sound in the export?".
    private func audioRMS(_ url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return 0 }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false])
        reader.add(output)
        reader.startReading()
        var sumSquares = 0.0
        var count = 0
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var data = [Int16](repeating: 0, count: length / 2)
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &data)
            for v in data {
                let n = Double(v) / Double(Int16.max)
                sumSquares += n * n
            }
            count += data.count
        }
        guard count > 0 else { return 0 }
        return (sumSquares / Double(count)).squareRoot()
    }

    private func pixelBuffer(from image: CGImage, side: Int) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, side, side, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferCGImageCompatibilityKey: true,
                             kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &pb)
        guard let buffer = pb else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let ctx = CGContext(data: base, width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return buffer
    }

    private func silenceBuffer(sampleRate: Double, frames: Int, pts: CMTime) -> CMSampleBuffer? {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
            mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0,
                                             layout: nil, magicCookieSize: 0, magicCookie: nil,
                                             extensions: nil, formatDescriptionOut: &format) == noErr,
              let format else { return nil }
        let dataSize = frames * 2
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
                                                 blockLength: dataSize, blockAllocator: kCFAllocatorDefault,
                                                 customBlockSource: nil, offsetToData: 0, dataLength: dataSize,
                                                 flags: kCMBlockBufferAssureMemoryNowFlag,
                                                 blockBufferOut: &block) == kCMBlockBufferNoErr,
              let block else { return nil }
        CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: dataSize)
        var sample: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: Int32(sampleRate)),
                                        presentationTimeStamp: pts, decodeTimeStamp: .invalid)
        var sizeArr = [2]
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block,
                                        formatDescription: format, sampleCount: frames,
                                        sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                        sampleSizeEntryCount: 1, sampleSizeArray: &sizeArr,
                                        sampleBufferOut: &sample) == noErr else { return nil }
        return sample
    }

    /// Reads the composited first frame through the video composition and returns
    /// the BGRA pixel at (x, y).
    private func compositedPixel(_ bundle: VideoCompositionBundle, x: Int, y: Int) async throws
        -> (r: UInt8, g: UInt8, b: UInt8) {
        let tracks = try await bundle.composition.loadTracks(withMediaType: .video)
        let reader = try AVAssetReader(asset: bundle.composition)
        let output = AVAssetReaderVideoCompositionOutput(
            videoTracks: tracks,
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.videoComposition = bundle.videoComposition
        reader.add(output)
        reader.startReading()
        guard let sample = output.copyNextSampleBuffer(),
              let buffer = CMSampleBufferGetImageBuffer(sample) else {
            throw NSError(domain: "readback", code: 1)
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let bpr = CVPixelBufferGetBytesPerRow(buffer)
        let i = y * bpr + x * 4
        return (r: base[i + 2], g: base[i + 1], b: base[i])   // BGRA
    }

    /// Reads the composited frame at `atSeconds` (pulls frames until the target
    /// time is reached) and returns the BGRA pixel at (x, y). Used to prove a
    /// beat-synced cell is held/animated at the right moment.
    private func compositedPixel(_ bundle: VideoCompositionBundle, x: Int, y: Int,
                                 atSeconds target: Double) async throws
        -> (r: UInt8, g: UInt8, b: UInt8) {
        let tracks = try await bundle.composition.loadTracks(withMediaType: .video)
        let reader = try AVAssetReader(asset: bundle.composition)
        let output = AVAssetReaderVideoCompositionOutput(
            videoTracks: tracks,
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.videoComposition = bundle.videoComposition
        reader.add(output)
        reader.startReading()
        var chosen: CMSampleBuffer?
        while let sample = output.copyNextSampleBuffer() {
            chosen = sample
            if CMSampleBufferGetPresentationTimeStamp(sample).seconds >= target { break }
        }
        guard let sample = chosen, let buffer = CMSampleBufferGetImageBuffer(sample) else {
            throw NSError(domain: "readback", code: 2)
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let bpr = CVPixelBufferGetBytesPerRow(buffer)
        let i = y * bpr + x * 4
        return (r: base[i + 2], g: base[i + 1], b: base[i])   // BGRA
    }

    /// Reads the first frame's BGRA pixel at (x, y) from a plain exported video file
    /// (no video composition — overlays are already baked in).
    private func filePixel(_ url: URL, x: Int, y: Int) async throws -> (r: UInt8, g: UInt8, b: UInt8) {
        let asset = AVURLAsset(url: url)
        let track = try await asset.loadTracks(withMediaType: .video).first!
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        reader.startReading()
        guard let sample = output.copyNextSampleBuffer(),
              let buffer = CMSampleBufferGetImageBuffer(sample) else {
            throw NSError(domain: "filereadback", code: 1)
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let bpr = CVPixelBufferGetBytesPerRow(buffer)
        let i = y * bpr + x * 4
        return (r: base[i + 2], g: base[i + 1], b: base[i])   // BGRA
    }
}
