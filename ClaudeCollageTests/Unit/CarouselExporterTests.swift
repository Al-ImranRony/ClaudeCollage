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
}
