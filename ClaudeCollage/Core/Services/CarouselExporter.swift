//
//  CarouselExporter.swift
//  ClaudeCollage
//
//  Step 03b slice 7 — exports a carousel as an image set: each frame written as a
//  zero-padded, numbered .jpg. Two deliveries share that one writer:
//
//  • `writeShareableFrames` returns the loose images, which is what the share sheet
//    hands to AirDrop / Messages / the photo apps a carousel is posted from.
//  • `exportImageSet` archives them into a .zip for Files (the Camera Roll can't
//    hold a numbered folder), via NSFileCoordinator's `.forUploading` archive —
//    the platform's own directory-to-zip, so there's no third-party dependency.
//
//  Step 04.5: sharing used to go through the zip only, which nothing downstream
//  could unpack. Frame ORDER is the contract in both paths — a carousel is only
//  meaningful in sequence.
//

import CoreGraphics
import Foundation
import UIKit

public struct CarouselExporter {

    public enum ExportError: Error, Equatable {
        case noFrames
        case encodingFailed
    }

    public init() {}

    /// Writes each frame as `<prefix>_01.jpg`, `<prefix>_02.jpg`, … into
    /// `directory` (created if needed) and returns the written file URLs in
    /// carousel order.
    ///
    /// The order of the returned array is the contract: a carousel is only
    /// meaningful in sequence, and both the share sheet and the Photos save rely
    /// on this being the running order.
    @discardableResult
    public func writeFrames(
        _ images: [CGImage], to directory: URL, prefix: String = "frame"
    ) throws -> [URL] {
        guard !images.isEmpty else { throw ExportError.noFrames }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var urls: [URL] = []
        for (i, image) in images.enumerated() {
            guard let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.92) else {
                throw ExportError.encodingFailed
            }
            let url = directory.appendingPathComponent(String(format: "%@_%02d.jpg", prefix, i + 1))
            try data.write(to: url)
            urls.append(url)
        }
        return urls
    }

    /// Writes the frames as individually shareable JPEGs in a fresh directory and
    /// returns them in order, ready to hand straight to a share sheet.
    ///
    /// This is the counterpart to `exportImageSet`: same files, no archive around
    /// them. A zip is the right artifact for Files, but it is useless to the apps
    /// people actually post carousels to, which expect the images themselves.
    public func writeShareableFrames(
        _ images: [CGImage], baseName: String, into directory: URL
    ) throws -> [URL] {
        guard !images.isEmpty else { throw ExportError.noFrames }
        let framesDir = directory.appendingPathComponent(baseName, isDirectory: true)
        try? FileManager.default.removeItem(at: framesDir)
        return try writeFrames(images, to: framesDir, prefix: baseName)
    }

    /// Renders the frames to `<baseName>/frame_NN.jpg` under `directory`, then zips
    /// that folder to `<baseName>.zip` (same directory) and returns the archive URL.
    @discardableResult
    public func exportImageSet(images: [CGImage], baseName: String, into directory: URL) throws -> URL {
        guard !images.isEmpty else { throw ExportError.noFrames }
        let framesDir = directory.appendingPathComponent(baseName, isDirectory: true)
        try? FileManager.default.removeItem(at: framesDir)
        _ = try writeFrames(images, to: framesDir)

        let zipURL = directory.appendingPathComponent("\(baseName).zip")
        try? FileManager.default.removeItem(at: zipURL)
        try zip(folder: framesDir, to: zipURL)
        return zipURL
    }

    /// Archives `folder` to `destination` using NSFileCoordinator's forUploading
    /// option (which hands back a temporary zip of the coordinated directory).
    public func zip(folder: URL, to destination: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var thrownError: Error?
        coordinator.coordinate(readingItemAt: folder, options: [.forUploading],
                               error: &coordinationError) { zipURL in
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: zipURL, to: destination)
            } catch {
                thrownError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let thrownError { throw thrownError }
    }
}
