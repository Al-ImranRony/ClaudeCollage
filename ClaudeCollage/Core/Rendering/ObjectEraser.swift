//
//  ObjectEraser.swift
//  ClaudeCollage
//
//  Step 05 batch B — the magic eraser's geometry and fill. Pure Core Graphics /
//  Core Image, so unlike the Vision-backed features this runs and is tested in
//  the simulator.
//
//  On the fill technique, stated plainly: Core Image has NO inpainting filter.
//  The brief suggests `CIPerspectiveCorrection`, which is a geometry correction
//  and cannot fill anything. Real content-aware fill means a diffusion or
//  patch-match model, which is far outside this step.
//
//  What this does instead is the honest, shippable approximation: sample the
//  surrounding pixels, blur them heavily with the edges clamped so colour bleeds
//  inward from the boundary, and composite that through the mask. On backgrounds
//  with smooth or repetitive texture — sky, wall, grass, sand, which is where
//  people actually reach for an eraser — it reads as a clean removal. Over busy
//  structure it reads as a smudge, so the UI must not promise magic.
//

import CoreGraphics
import CoreImage
import Foundation
import UIKit

/// One brush stroke: a path of points in normalized image space with a radius
/// that is also normalized (fraction of the image's smaller side), so a stroke
/// survives the image being displayed at any size.
///
/// Points use a TOP-LEFT origin, matching UIKit and the convention `AIService`
/// established for Vision rects. `mask(from:size:)` flips into Core Graphics'
/// bottom-left space when it draws — without that, every erase lands mirrored
/// vertically, and only an asymmetric stroke reveals it.
public struct EraserStroke: Equatable, Sendable {
    public let points: [CGPoint]
    public let radius: CGFloat

    public init(points: [CGPoint], radius: CGFloat) {
        self.points = points
        self.radius = radius
    }
}

public struct ObjectEraser: Sendable {

    public init() {}

    // MARK: - Mask building

    /// Renders strokes into a grayscale mask: white where the user painted.
    ///
    /// Returns nil for an empty set, so callers can distinguish "nothing painted"
    /// from "erase produced nothing" and show the right message.
    public func mask(from strokes: [EraserStroke], size: CGSize) -> CGImage? {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width > 0, height > 0 else { return nil }
        guard strokes.contains(where: { !$0.points.isEmpty }) else { return nil }

        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setStrokeColor(gray: 1, alpha: 1)
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        // Radius is a fraction of the smaller side so a stroke keeps its apparent
        // thickness on any aspect.
        let reference = CGFloat(min(width, height))
        for stroke in strokes where !stroke.points.isEmpty {
            let radiusPx = max(1, stroke.radius * reference)
            let path = CGMutablePath()
            // y is flipped here: strokes come from the UI in top-left space, the
            // context draws in bottom-left.
            let absolute = stroke.points.map {
                CGPoint(x: $0.x * CGFloat(width), y: (1 - $0.y) * CGFloat(height))
            }
            if absolute.count == 1 {
                // A tap, not a drag — still a dab of paint.
                let point = absolute[0]
                ctx.fillEllipse(in: CGRect(
                    x: point.x - radiusPx, y: point.y - radiusPx,
                    width: radiusPx * 2, height: radiusPx * 2))
                continue
            }
            path.addLines(between: absolute)
            ctx.setLineWidth(radiusPx * 2)
            ctx.addPath(path)
            ctx.strokePath()
        }
        return ctx.makeImage()
    }

    // MARK: - Erase

    /// Replaces the masked region with colour drawn inward from its surroundings.
    ///
    /// See the file header: an approximation, not true inpainting.
    public func erase(_ image: CGImage, mask: CGImage) -> CGImage? {
        let source = CIImage(cgImage: image)
        let extent = source.extent
        guard extent.width > 0, extent.height > 0 else { return nil }

        var maskImage = CIImage(cgImage: mask)
        let maskExtent = maskImage.extent
        guard maskExtent.width > 0, maskExtent.height > 0 else { return nil }
        maskImage = maskImage.transformed(by: CGAffineTransform(
            scaleX: extent.width / maskExtent.width,
            y: extent.height / maskExtent.height))
        // Softened so the patch meets the original without a visible cut line.
        maskImage = maskImage
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(min(extent.width, extent.height) * 0.004))
            .cropped(to: extent)

        // Punch the painted region out FIRST. Blurring the intact image would let
        // the object bleed into its own replacement — the fill has to be built
        // from valid pixels only.
        guard let punch = CIFilter(name: "CIBlendWithMask") else { return nil }
        punch.setValue(CIImage.empty(), forKey: kCIInputImageKey)
        punch.setValue(source, forKey: kCIInputBackgroundImageKey)
        punch.setValue(maskImage, forKey: kCIInputMaskImageKey)
        guard let holePunched = punch.outputImage else { return nil }

        // Push colour inward from the hole's edge: blur, then re-assert the known
        // pixels so each round only advances the frontier. A few rounds carry
        // colour far enough to close a brush-sized gap without smearing the whole
        // photo, which one enormous blur would do.
        let sigma = Double(min(extent.width, extent.height) * 0.05)
        var filled = holePunched
        for _ in 0 ..< Self.propagationRounds {
            filled = filled.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: extent)
            filled = holePunched.composited(over: filled)
        }

        guard let blend = CIFilter(name: "CIBlendWithMask") else { return nil }
        blend.setValue(filled, forKey: kCIInputImageKey)
        blend.setValue(source, forKey: kCIInputBackgroundImageKey)
        blend.setValue(maskImage, forKey: kCIInputMaskImageKey)
        guard let output = blend.outputImage else { return nil }

        return Self.context.createCGImage(output, from: extent)
    }

    /// Convenience: build the mask and erase in one step. Nil when nothing was
    /// painted.
    public func erase(_ image: CGImage, strokes: [EraserStroke]) -> CGImage? {
        let size = CGSize(width: image.width, height: image.height)
        guard let mask = mask(from: strokes, size: size) else { return nil }
        return erase(image, mask: mask)
    }

    /// How many blur-and-reassert rounds carry colour into the hole. Five closes a
    /// comfortably brush-sized gap; more mostly costs time.
    private static let propagationRounds = 5

    private static let context = CIContext(options: [.useSoftwareRenderer: false])
}
