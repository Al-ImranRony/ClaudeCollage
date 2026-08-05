//
//  SubjectCompositor.swift
//  ClaudeCollage
//
//  Step 05 batch A — turns a segmentation mask into a liftable subject.
//
//  Pure Core Graphics / Core Image: no Vision, so unlike the segmentation itself
//  this runs and is tested in the simulator. Vision produces the mask; everything
//  that makes it *useful* — punching alpha, trimming to the subject, feathering
//  the edge — happens here.
//

import CoreGraphics
import CoreImage
import Foundation

public struct SubjectCompositor: Sendable {

    public init() {}

    /// Applies a grayscale `mask` to `image`, returning RGBA where the mask is
    /// black becomes fully transparent.
    ///
    /// The mask is resampled to the image's pixel size — Vision returns it at
    /// whatever resolution the model worked at, which is rarely the original.
    public func applyMask(_ mask: CGImage, to image: CGImage) -> CGImage? {
        let source = CIImage(cgImage: image)
        let extent = source.extent
        guard extent.width > 0, extent.height > 0 else { return nil }

        var maskImage = CIImage(cgImage: mask)
        let maskExtent = maskImage.extent
        guard maskExtent.width > 0, maskExtent.height > 0 else { return nil }
        maskImage = maskImage.transformed(by: CGAffineTransform(
            scaleX: extent.width / maskExtent.width,
            y: extent.height / maskExtent.height
        ))

        // Blend against a fully transparent background so the mask's black
        // regions become alpha 0 rather than black pixels.
        guard let filter = CIFilter(name: "CIBlendWithMask") else { return nil }
        filter.setValue(source, forKey: kCIInputImageKey)
        filter.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)
        filter.setValue(maskImage, forKey: kCIInputMaskImageKey)
        guard let output = filter.outputImage else { return nil }

        return Self.context.createCGImage(
            output, from: extent, format: .RGBA8, colorSpace: source.colorSpace)
    }

    /// Trims fully transparent margins, so a lifted subject arrives sized to
    /// itself rather than to the photo it came out of.
    ///
    /// Returns `nil` when nothing is opaque enough to keep — which is what a
    /// mask that found nothing looks like by the time it reaches here.
    public func cropToOpaqueBounds(_ image: CGImage, alphaThreshold: UInt8 = 8) -> CGImage? {
        guard let bounds = opaqueBounds(of: image, alphaThreshold: alphaThreshold) else {
            return nil
        }
        return image.cropping(to: bounds)
    }

    /// Tight bounding box of pixels whose alpha exceeds the threshold, in image
    /// pixel coordinates (origin top-left, matching `CGImage`).
    public func opaqueBounds(of image: CGImage, alphaThreshold: UInt8 = 8) -> CGRect? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        // Redraw into a known layout; the incoming image's format is whatever
        // Core Image produced and reading it directly is not portable.
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0 ..< height {
            let row = y * width * 4
            for x in 0 ..< width where pixels[row + x * 4 + 3] > alphaThreshold {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }

        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// One shared context — creating a `CIContext` per call is expensive, and
    /// this mirrors how `ImageFilterProcessor` already handles it.
    private static let context = CIContext(options: [.useSoftwareRenderer: false])
}
