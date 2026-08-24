//
//  ImageExporter.swift
//  Caroullage
//
//  Step 04 slice 1 — encodes a fully-composited canvas render (CGImage) to shareable
//  image data (Section 2 of the universal export sheet). JPEG carries a quality knob
//  (0.5–1.0 in the UI); PNG is always lossless. Resolution can be full (native canvas
//  px), half, or an explicit custom size. Pure — the caller owns saving/sharing.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import UIKit

public struct ImageExporter {

    public enum Format: Equatable {
        case jpeg(quality: CGFloat)
        case png
    }

    public enum Resolution: Equatable {
        case full
        case half
        case custom(CGSize)

        func targetSize(for source: CGImage) -> CGSize {
            switch self {
            case .full:
                return CGSize(width: source.width, height: source.height)
            case .half:
                return CGSize(width: max(1, source.width / 2), height: max(1, source.height / 2))
            case .custom(let size):
                return CGSize(width: max(1, size.width.rounded()), height: max(1, size.height.rounded()))
            }
        }
    }

    public enum ExportError: Error, Equatable {
        case resizeFailed
        case encodingFailed
    }

    public init() {}

    /// Encodes `image` to the requested format and resolution, returning file data.
    public func encode(_ image: CGImage, format: Format, resolution: Resolution) throws -> Data {
        let target = resolution.targetSize(for: image)
        let scaled = try resize(image, to: target)

        let data = NSMutableData()
        let type: UTType = {
            switch format {
            case .jpeg: return .jpeg
            case .png: return .png
            }
        }()
        guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw ExportError.encodingFailed
        }
        var props: [CFString: Any] = [:]
        if case .jpeg(let quality) = format {
            props[kCGImageDestinationLossyCompressionQuality] = max(0, min(1, quality))
        }
        CGImageDestinationAddImage(dest, scaled, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ExportError.encodingFailed }
        return data as Data
    }

    /// Redraws `image` at `size`. When `size` already matches, returns it unchanged.
    private func resize(_ image: CGImage, to size: CGSize) throws -> CGImage {
        let w = Int(size.width), h = Int(size.height)
        if w == image.width && h == image.height { return image }
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ExportError.resizeFailed }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { throw ExportError.resizeFailed }
        return out
    }
}
