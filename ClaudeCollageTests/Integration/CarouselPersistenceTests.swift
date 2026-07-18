//
//  CarouselPersistenceTests.swift
//  ClaudeCollageTests
//
//  Step 03b slice 8 — a carousel round-trips through ProjectStore: frames + type +
//  per-frame state encode to the SwiftData record (photos on disk keyed by image
//  id), appear in the home gallery as a carousel, and reload into a fresh view
//  model. Grid projects must NOT resume as carousels.
//

import XCTest
import CoreGraphics
import SwiftData
@testable import ClaudeCollage

@MainActor
final class CarouselPersistenceTests: XCTestCase {

    private func makeStore() throws -> ProjectStore {
        let schema = Schema([CollageProject.self, CollageCell.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ProjectStore(container: container)
    }

    private func makeImage(_ side: Int = 32) -> CGImage {
        let bytesPerRow = side * 4
        var pixels = [UInt8](repeating: 180, count: bytesPerRow * side)
        let ctx = CGContext(
            data: &pixels, width: side, height: side, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    func testCarouselFramesAndTypeRoundTrip() throws {
        let store = try makeStore()
        var frames = (0..<3).map { CarouselFrame(index: $0, state: GridEditorState()) }
        frames[1].state.background = .black
        let vm = CarouselEditorViewModel(
            frames: frames, canvasSize: CGSize(width: 1080, height: 1350), carouselType: .scrollThrough)

        store.saveCarousel(vm)

        let loaded = try XCTUnwrap(store.loadCarouselViewModel(id: vm.projectID))
        XCTAssertEqual(loaded.frameCount, 3)
        XCTAssertEqual(loaded.carouselType, .scrollThrough)
        XCTAssertEqual(loaded.frames[1].state.background, .black, "per-frame edits survive the round-trip")
    }

    func testCarouselAppearsInSummariesTaggedCarousel() throws {
        let store = try makeStore()
        let vm = CarouselEditorViewModel(
            frames: (0..<2).map { CarouselFrame(index: $0, state: GridEditorState()) },
            canvasSize: CGSize(width: 1080, height: 1080), carouselType: .matched)

        store.saveCarousel(vm)

        let summaries = store.listSummaries()
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries.first?.id, vm.projectID)
        XCTAssertEqual(summaries.first?.mode, .carousel)
    }

    func testGridProjectDoesNotResumeAsCarousel() throws {
        let store = try makeStore()
        let gridVM = GridEditorViewModel(
            canvasSize: CGSize(width: 1080, height: 1080), state: GridEditorState())
        store.save(gridVM)
        XCTAssertNil(store.loadCarouselViewModel(id: gridVM.projectID),
                     "a grid project must not load as a carousel")
    }

    func testCarouselPhotosRoundTripFromDisk() throws {
        let store = try makeStore()
        let imageID = UUID()
        let state = GridEditorState(
            layout: .template(TemplateLayout(
                templateID: "pano", name: "Pano", aspectRatio: "1:1",
                cells: [TemplateLayoutCell(frame: CGRect(x: 0, y: 0, width: 1, height: 1))])),
            cells: [EditorCellState(imageID: imageID)])
        let vm = CarouselEditorViewModel(
            frames: [CarouselFrame(index: 0, state: state)], images: [imageID: makeImage()],
            canvasSize: CGSize(width: 1080, height: 1080), carouselType: .panoramic)

        store.saveCarousel(vm)
        defer { store.delete(id: vm.projectID) }

        let loaded = try XCTUnwrap(store.loadCarouselViewModel(id: vm.projectID))
        XCTAssertEqual(loaded.frames[0].state.cells.first?.imageID, imageID)
        XCTAssertNotNil(loaded.imagesSnapshot()[imageID], "the frame's photo reloads from disk")
    }
}
