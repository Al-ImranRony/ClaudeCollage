//
//  VideoPersistenceTests.swift
//  ClaudeCollageTests
//
//  Step 04 slice 5c — a video collage round-trips through ProjectStore: the layout,
//  per-cell state (trim / loop / mute / volume / transition) and the background-music
//  track encode into the SwiftData record, the project shows up in the home gallery
//  tagged `.video`, and it reloads into a fresh view model.
//
//  The interesting part is the MEDIA. Unlike photos (already CGImages in memory),
//  a picked clip is an AVAsset whose URL points either into the Photos library or at
//  a temp-dir copy from `VideoSourcePicker` — both of which can vanish. So the store
//  copies each referenced clip into the project folder keyed by `videoID`, and
//  `testVideoFileSurvivesTheOriginalBeingDeleted` proves resume no longer depends on
//  the original file existing.
//

import XCTest
import AVFoundation
import CoreGraphics
import SwiftData
@testable import ClaudeCollage

@MainActor
final class VideoPersistenceTests: XCTestCase {

    private var scratch: [URL] = []

    // The async variant inherits the class's @MainActor isolation, so it can touch
    // `scratch` (the plain `tearDown()` override is nonisolated).
    override func tearDown() async throws {
        for url in scratch { try? FileManager.default.removeItem(at: url) }
        scratch = []
        try await super.tearDown()
    }

    private func makeStore() throws -> ProjectStore {
        let schema = Schema([CollageProject.self, CollageCell.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ProjectStore(container: container)
    }

    private func makeViewModel(layout: CollageLayout = .grid(.twoUpVertical)) -> VideoEditorViewModel {
        VideoEditorViewModel(canvasSize: CGSize(width: 1080, height: 1350), layout: layout)
    }

    private func tempURL(ext: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VidPersist-\(UUID().uuidString).\(ext)")
        scratch.append(url)
        return url
    }

    private func solidImage(_ side: Int) -> CGImage {
        let bytesPerRow = side * 4
        var pixels = [UInt8](repeating: 140, count: bytesPerRow * side)
        let ctx = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8,
                            bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    /// A real on-disk movie, standing in for a picked clip.
    private func makeVideoFile(seconds: Double = 1) async throws -> URL {
        let url = tempURL(ext: "mp4")
        try await VideoComposer().renderSlideshow(
            frames: [solidImage(160)], size: CGSize(width: 160, height: 160),
            secondsPerFrame: seconds, to: url)
        return url
    }

    // MARK: - State round-trip

    func testCellControlsAndLayoutRoundTrip() async throws {
        let store = try makeStore()
        let vm = makeViewModel(layout: .grid(.fourSquare))
        let videoURL = try await makeVideoFile()
        let id = UUID()
        vm.setVideo(assetID: id, asset: AVURLAsset(url: videoURL), forCellAt: 1)
        vm.setTrim(VideoTrim(start: 0.2, end: 0.8), forCellAt: 1)
        vm.setLooping(true, forCellAt: 1)
        vm.setMuted(true, forCellAt: 1)
        vm.setVolume(0.35, forCellAt: 1)
        vm.setTransition(CellTransition(style: .zoomIn, duration: 0.4), forCellAt: 1)

        store.saveVideo(vm)

        await store.awaitPendingMediaWrites()
        defer { store.delete(id: vm.projectID) }

        let loaded = try XCTUnwrap(store.loadVideoViewModel(id: vm.projectID))
        XCTAssertEqual(loaded.cellCount, 4, "the layout survives")
        XCTAssertEqual(loaded.cells[1].videoID, id)
        XCTAssertEqual(loaded.cells[1].trim, VideoTrim(start: 0.2, end: 0.8))
        XCTAssertTrue(loaded.cells[1].isLooping)
        XCTAssertTrue(loaded.cells[1].isMuted)
        XCTAssertEqual(loaded.cells[1].volume, 0.35, accuracy: 1e-9)
        XCTAssertEqual(loaded.cells[1].transition?.style, .zoomIn)
    }

    func testBackgroundMusicRoundTrips() async throws {
        let store = try makeStore()
        let vm = makeViewModel()
        let videoURL = try await makeVideoFile()
        vm.setVideo(assetID: UUID(), asset: AVURLAsset(url: videoURL), forCellAt: 0)

        let musicID = UUID()
        let musicURL = try await makeVideoFile()   // any real media file will do
        vm.setMusic(assetID: musicID, asset: AVURLAsset(url: musicURL), volume: 0.45)

        store.saveVideo(vm)

        await store.awaitPendingMediaWrites()
        defer { store.delete(id: vm.projectID) }

        let loaded = try XCTUnwrap(store.loadVideoViewModel(id: vm.projectID))
        XCTAssertEqual(loaded.music?.musicID, musicID)
        XCTAssertEqual(loaded.music?.volume ?? -1, 0.45, accuracy: 1e-9)
        XCTAssertNotNil(loaded.backgroundMusic(), "the music asset reloads from disk")
    }

    // MARK: - Gallery + routing

    func testVideoAppearsInSummariesTaggedVideo() async throws {
        let store = try makeStore()
        let vm = makeViewModel()
        let videoURL = try await makeVideoFile()
        vm.setVideo(assetID: UUID(), asset: AVURLAsset(url: videoURL), forCellAt: 0)

        store.saveVideo(vm)

        await store.awaitPendingMediaWrites()
        defer { store.delete(id: vm.projectID) }

        let summaries = store.listSummaries()
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries.first?.id, vm.projectID)
        XCTAssertEqual(summaries.first?.mode, .video)
    }

    func testGridProjectDoesNotResumeAsVideo() throws {
        let store = try makeStore()
        let gridVM = GridEditorViewModel(canvasSize: CGSize(width: 1080, height: 1080),
                                         state: GridEditorState())
        store.save(gridVM)
        XCTAssertNil(store.loadVideoViewModel(id: gridVM.projectID),
                     "a grid project must not load as a video collage")
    }

    func testVideoProjectDoesNotResumeAsCarousel() async throws {
        let store = try makeStore()
        let vm = makeViewModel()
        let videoURL = try await makeVideoFile()
        vm.setVideo(assetID: UUID(), asset: AVURLAsset(url: videoURL), forCellAt: 0)
        store.saveVideo(vm)
        await store.awaitPendingMediaWrites()
        defer { store.delete(id: vm.projectID) }

        XCTAssertNil(store.loadCarouselViewModel(id: vm.projectID),
                     "a video project must not load as a carousel")
    }

    // MARK: - Durable media (the whole point)

    func testVideoFileSurvivesTheOriginalBeingDeleted() async throws {
        let store = try makeStore()
        let vm = makeViewModel()
        let originalURL = try await makeVideoFile()
        let id = UUID()
        vm.setVideo(assetID: id, asset: AVURLAsset(url: originalURL), forCellAt: 0)

        store.saveVideo(vm)

        await store.awaitPendingMediaWrites()
        defer { store.delete(id: vm.projectID) }

        // Simulate the picker's temp copy being reaped / the Photos asset going away.
        try FileManager.default.removeItem(at: originalURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))

        let loaded = try XCTUnwrap(store.loadVideoViewModel(id: vm.projectID))
        let asset = try XCTUnwrap(loaded.asset(for: id) as? AVURLAsset)
        XCTAssertTrue(FileManager.default.fileExists(atPath: asset.url.path),
                      "the clip was copied into the project, so resume still works")
        XCTAssertNotEqual(asset.url, originalURL, "resume must not point at the original")
        XCTAssertEqual(loaded.compositionCells().count, 1,
                       "the restored asset feeds the composition again")
    }

    func testDeleteRemovesCopiedVideoFiles() async throws {
        let store = try makeStore()
        let vm = makeViewModel()
        let id = UUID()
        let originalURL = try await makeVideoFile()
        vm.setVideo(assetID: id, asset: AVURLAsset(url: originalURL), forCellAt: 0)
        store.saveVideo(vm)
        await store.awaitPendingMediaWrites()

        let loaded = try XCTUnwrap(store.loadVideoViewModel(id: vm.projectID))
        let copiedURL = try XCTUnwrap((loaded.asset(for: id) as? AVURLAsset)?.url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copiedURL.path))

        store.delete(id: vm.projectID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: copiedURL.path),
                       "deleting the project reclaims its copied clips")
    }

    func testEmptyVideoProjectStillSavesAndReloads() throws {
        let store = try makeStore()
        let vm = makeViewModel(layout: .grid(.threeLeft))
        store.saveVideo(vm)   // no media, so nothing to await
        defer { store.delete(id: vm.projectID) }

        let loaded = try XCTUnwrap(store.loadVideoViewModel(id: vm.projectID))
        XCTAssertEqual(loaded.cellCount, 3, "an empty collage still resumes with its layout")
        XCTAssertEqual(loaded.filledCellCount, 0)
    }
}
