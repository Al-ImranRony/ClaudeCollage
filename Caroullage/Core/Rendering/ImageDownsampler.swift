//
//  ImageDownsampler.swift
//  Caroullage
//
//  Step 01 (perf) — memory-efficient image downsampling via ImageIO.
//
//  Photos from the picker are 12–48 MP. Decoding them full-size into RAM (a
//  12 MP image is ~48 MB decoded) and holding one per cell blows past the
//  200 MB budget. `CGImageSourceCreateThumbnailAtIndex` decodes straight to a
//  bounded size without ever materializing the full-resolution bitmap, so a
//  9-cell collage stays well within budget.
//

import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

enum ImageDownsampler {

    /// Max dimension (px) for on-canvas / export images. A 1080²  export never
    /// samples a cell wider than the canvas, so ~1280 px keeps full visual
    /// quality while capping a decoded RGBA bitmap at ~6.5 MB.
    static let displayMaxDimension: CGFloat = 1280

    /// Downsamples image `data` so its longest edge is at most `maxDimension` px.
    static func downsample(data: Data, maxDimension: CGFloat = displayMaxDimension) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        return downsample(source: source, maxDimension: maxDimension)
    }

    /// Downsamples an image at `url` (used when resuming a saved project).
    static func downsample(url: URL, maxDimension: CGFloat = displayMaxDimension) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        return downsample(source: source, maxDimension: maxDimension)
    }

    private static func downsample(source: CGImageSource, maxDimension: CGFloat) -> CGImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // bakes in EXIF orientation
            kCGImageSourceShouldCacheImmediately: true,          // decode now, on this thread
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
}
