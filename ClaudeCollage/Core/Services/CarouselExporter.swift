//
//  CarouselExporter.swift
//  ClaudeCollage
//
//  Step 03b slice 7 — exports a carousel as an image set: each frame written as a
//  zero-padded frame_NN.jpg, then archived into a .zip for saving to Files (Camera
//  Roll can't hold a numbered folder). The zip is produced by NSFileCoordinator's
//  `.forUploading` archive — the platform's own directory-to-zip, so there's no
//  third-party dependency.
//
//  Video-slideshow export lands with Step 04's VideoComposer (AVFoundation); until
//  then the editor offers image-set export only.
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

    /// Writes each frame as `frame_01.jpg`, `frame_02.jpg`, … into `directory`
    /// (created if needed) and returns the written file URLs in order.
    @discardableResult
    public func writeFrames(_ images: [CGImage], to directory: URL) throws -> [URL] {
        guard !images.isEmpty else { throw ExportError.noFrames }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var urls: [URL] = []
        for (i, image) in images.enumerated() {
            guard let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.92) else {
                throw ExportError.encodingFailed
            }
            let url = directory.appendingPathComponent(String(format: "frame_%02d.jpg", i + 1))
            try data.write(to: url)
            urls.append(url)
        }
        return urls
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
