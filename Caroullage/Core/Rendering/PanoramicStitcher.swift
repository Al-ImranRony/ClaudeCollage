//
//  PanoramicStitcher.swift
//  Caroullage
//
//  Step 03b slice 1 — the pure pixel engine behind panoramic carousels.
//
//  A panoramic carousel is one wide image cut into N equal frames that read as a
//  single continuous scroll when swiped on Instagram. The cut must be exact: any
//  dropped or duplicated column shows up as a visible jump at a frame boundary, so
//  every operation here works on real pixels with NO resampling.
//   • `split` uses `CGImage.cropping(to:)`, which returns sub-images sharing the
//     source's pixels — an exact, copy-free slice.
//   • `stitch` composites frames edge-to-edge into a fresh bitmap (identity draw,
//     same size in = same size out).
//   • `verifyEdgeAlignment` asserts the structural invariant of a clean split:
//     every frame is identically sized, so laid side-by-side they leave 0px gap and
//     0px overlap. (Adjacent slices are disjoint source columns, so a value-wise
//     "does column A equal column B" check is meaningless on a real photo — equal
//     dimensions is the property that actually guarantees seamlessness.)
//
//  v1 note: `split` assumes the source's split-axis length is divisible by the
//  frame count (the import path pre-crops the source to a multiple of N). When it
//  isn't, each frame takes `length / N` and up to N-1 trailing pixels are dropped;
//  callers author/prepare divisible sources for a truly seamless result.
//

import CoreGraphics

public enum SplitAxis: String, Codable, Sendable, CaseIterable {
    case horizontal
    case vertical
}

public struct PanoramicStitcher {

    public init() {}

    /// Cuts `image` into `frameCount` equal slices along `axis`, in reading order
    /// (frame 0 is the left / top slice). Returns `[]` for a non-positive count or a
    /// slice that would be zero-sized.
    public func split(image: CGImage, into frameCount: Int, axis: SplitAxis) -> [CGImage] {
        guard frameCount > 0 else { return [] }
        switch axis {
        case .horizontal:
            let frameWidth = image.width / frameCount
            guard frameWidth > 0 else { return [] }
            return (0..<frameCount).compactMap { i in
                image.cropping(to: CGRect(x: i * frameWidth, y: 0,
                                          width: frameWidth, height: image.height))
            }
        case .vertical:
            let frameHeight = image.height / frameCount
            guard frameHeight > 0 else { return [] }
            return (0..<frameCount).compactMap { i in
                image.cropping(to: CGRect(x: 0, y: i * frameHeight,
                                          width: image.width, height: frameHeight))
            }
        }
    }

    /// Composites `images` edge-to-edge along `axis` in array order into one image.
    /// The inverse of `split` for an equal, gap-free set. Returns `nil` if empty or
    /// the target bitmap can't be created.
    public func stitch(images: [CGImage], axis: SplitAxis) -> CGImage? {
        guard !images.isEmpty else { return nil }

        let totalWidth: Int
        let totalHeight: Int
        switch axis {
        case .horizontal:
            totalWidth = images.reduce(0) { $0 + $1.width }
            totalHeight = images.map(\.height).max() ?? 0
        case .vertical:
            totalWidth = images.map(\.width).max() ?? 0
            totalHeight = images.reduce(0) { $0 + $1.height }
        }
        guard totalWidth > 0, totalHeight > 0,
              let ctx = CGContext(
                data: nil, width: totalWidth, height: totalHeight, bitsPerComponent: 8,
                bytesPerRow: totalWidth * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        switch axis {
        case .horizontal:
            // Left-to-right; a full-height identity draw copies each slice verbatim.
            var x = 0
            for image in images {
                ctx.draw(image, in: CGRect(x: x, y: 0, width: image.width, height: totalHeight))
                x += image.width
            }
        case .vertical:
            // CG's origin is bottom-left, so frame 0 (the top slice) is drawn last in
            // y: place each slice with its top edge descending from the canvas top.
            var y = totalHeight
            for image in images {
                y -= image.height
                ctx.draw(image, in: CGRect(x: 0, y: y, width: totalWidth, height: image.height))
            }
        }
        return ctx.makeImage()
    }

    /// True when the frames form a clean equal split: at least one frame, and every
    /// frame identically sized (so side-by-side they leave 0px gap and 0px overlap).
    public func verifyEdgeAlignment(frames: [CGImage]) -> Bool {
        guard let first = frames.first else { return false }
        let w = first.width, h = first.height
        guard w > 0, h > 0 else { return false }
        return frames.allSatisfy { $0.width == w && $0.height == h }
    }
}
