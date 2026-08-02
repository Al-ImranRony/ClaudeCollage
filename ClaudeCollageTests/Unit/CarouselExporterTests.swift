//
//  CarouselExporterTests.swift
//  ClaudeCollageTests
//
//  Step 03b slice 7 — the carousel image-set exporter: each frame written as a
//  zero-padded frame_NN.jpg, then zipped (via NSFileCoordinator's forUploading
//  archive — no third-party zip dependency) for saving to Files.
//

import XCTest
import CoreGraphics
import UIKit
@testable import ClaudeCollage

final class CarouselExporterTests: XCTestCase {

    private func makeImage(_ side: Int = 40) -> CGImage {
        let bytesPerRow = side * 4
        var pixels = [UInt8](repeating: 200, count: bytesPerRow * side)
        let ctx = CGContext(
            data: &pixels, width: side, height: side, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CarouselExporterTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testWriteFramesProducesZeroPaddedNumberedJPEGs() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let urls = try CarouselExporter().writeFrames([makeImage(), makeImage(), makeImage()], to: dir)

        XCTAssertEqual(urls.map(\.lastPathComponent), ["frame_01.jpg", "frame_02.jpg", "frame_03.jpg"])
        for url in urls {
            let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
            XCTAssertGreaterThan(size, 0, "each frame JPEG has content")
        }
    }

    func testExportImageSetProducesANonEmptyZip() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let zipURL = try CarouselExporter().exportImageSet(
            images: [makeImage(), makeImage()], baseName: "Carousel", into: dir)

        XCTAssertEqual(zipURL.pathExtension, "zip")
        XCTAssertTrue(FileManager.default.fileExists(atPath: zipURL.path))
        let size = try FileManager.default.attributesOfItem(atPath: zipURL.path)[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 0, "the archive is non-empty")
    }

    func testExportWithNoFramesThrows() {
        XCTAssertThrowsError(try CarouselExporter().exportImageSet(
            images: [], baseName: "Empty", into: FileManager.default.temporaryDirectory))
    }

    // MARK: - Shareable frames (Step 04.5)

    func testShareableFramesAreLooseNumberedImagesNotAnArchive() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let urls = try CarouselExporter().writeShareableFrames(
            [makeImage(), makeImage(), makeImage()], baseName: "Carousel", into: dir)

        XCTAssertEqual(urls.map(\.lastPathComponent),
                       ["Carousel_01.jpg", "Carousel_02.jpg", "Carousel_03.jpg"])
        for url in urls {
            XCTAssertEqual(url.pathExtension, "jpg", "sharing must offer images, not an archive")
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }
    }

    func testShareableFramesPreserveCarouselOrder() throws {
        // Order is the contract: a carousel posted out of sequence is wrong, and the
        // share sheet passes these URLs straight through.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let urls = try CarouselExporter().writeShareableFrames(
            (0 ..< 6).map { _ in makeImage() }, baseName: "Carousel", into: dir)

        let indices = urls.map { url -> Int in
            Int(url.deletingPathExtension().lastPathComponent.split(separator: "_").last ?? "") ?? -1
        }
        XCTAssertEqual(indices, Array(1 ... 6))
    }

    func testShareableFramesWithNoFramesThrows() {
        XCTAssertThrowsError(try CarouselExporter().writeShareableFrames(
            [], baseName: "Empty", into: FileManager.default.temporaryDirectory))
    }

    func testShareableFramesReplaceAStaleExport() throws {
        // The temp directory is reused across exports; a shorter carousel must not
        // leave the previous run's extra frames behind to be shared by mistake.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let exporter = CarouselExporter()
        _ = try exporter.writeShareableFrames(
            (0 ..< 5).map { _ in makeImage() }, baseName: "Carousel", into: dir)
        let second = try exporter.writeShareableFrames(
            [makeImage(), makeImage()], baseName: "Carousel", into: dir)

        XCTAssertEqual(second.count, 2)
        let contents = try FileManager.default.contentsOfDirectory(
            atPath: dir.appendingPathComponent("Carousel").path)
        XCTAssertEqual(contents.sorted(), ["Carousel_01.jpg", "Carousel_02.jpg"],
                       "stale frames from the previous export must be cleared")
    }
}
