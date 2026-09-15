//
//  WatermarkRenderer.swift
//  Caroullage
//
//  Step 06 phase 6.8. The free tier's "Made with Caroullage", baked into the
//  exported file and nowhere else — the canvas never shows it, so what the user
//  edits is their collage and what the file carries is the price of the free
//  tier. Premium and a spent credit export without it; the decision is
//  `ExportOptions.clampedForEntitlement`'s, not this file's.
//
//  Geometry is a fraction of the canvas, not of the device: a 1080px and a
//  2160px export of the same collage carry the same mark at the same place.
//  White lettering with a soft dark shadow reads on any photo. The line is a
//  brand mark, not UI copy, so it is not localized — like a logo.
//
//  Two entry points, one drawing: `stamp` for a finished still (image exports,
//  carousel frames, the slideshow's source frames) and `overlayImage` for the
//  video pipeline, which composites a transparent canvas-sized image onto every
//  frame at write time the way it already does the text/sticker overlay.
//

import UIKit

public enum WatermarkRenderer {

    public static let text = "Made with Caroullage"

    /// The lettering's height as a fraction of the canvas height (the brief's 4%).
    public static let heightFraction: CGFloat = 0.04

    /// Distance from the right and bottom edges: the mark's own height.
    public static func inset(for canvasHeight: CGFloat) -> CGFloat {
        canvasHeight * heightFraction
    }

    /// Where the mark lands in a canvas of this size (bottom-right, inset by its
    /// own height). Height is exact; width follows the text.
    public static func frame(in canvasPx: CGSize) -> CGRect {
        let height = canvasPx.height * heightFraction
        let width = attributedText(height: height).size().width
        let inset = inset(for: canvasPx.height)
        return CGRect(x: canvasPx.width - inset - width, y: canvasPx.height - inset - height,
                      width: width, height: height)
    }

    /// `image` with the mark drawn onto its bottom-right corner. Same size,
    /// same colour space treatment as the overlay renderer (sRGB, scale 1).
    public static func stamp(_ image: CGImage) -> CGImage {
        let size = CGSize(width: image.width, height: image.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let stamped = UIGraphicsImageRenderer(size: size, format: format).image { context in
            // UIImage.draw handles the CG→UIKit flip; the text then draws in
            // UIKit's top-down space like every overlay in the app.
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
            draw(in: size, context: context.cgContext)
        }
        return stamped.cgImage ?? image
    }

    /// A transparent canvas-sized image carrying only the mark, for the video
    /// exporter to composite onto each frame.
    public static func overlayImage(canvasPx: CGSize) -> CGImage? {
        guard canvasPx.width > 0, canvasPx.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: canvasPx, format: format).image { context in
            draw(in: canvasPx, context: context.cgContext)
        }.cgImage
    }

    // MARK: - Drawing

    private static func draw(in canvasPx: CGSize, context: CGContext) {
        let rect = frame(in: canvasPx)
        let height = rect.height
        context.saveGState()
        // A 50% black shadow, offset and blurred in proportion to the lettering,
        // so the white reads over a bright photo as well as a dark one.
        context.setShadow(offset: CGSize(width: 0, height: height * 0.08),
                          blur: height * 0.25,
                          color: UIColor.black.withAlphaComponent(0.5).cgColor)
        attributedText(height: height).draw(in: rect)
        context.restoreGState()
    }

    /// The line at a font whose line height is `height`. The rounded system
    /// face the app's chrome uses; semibold so the strokes survive JPEG.
    private static func attributedText(height: CGFloat) -> NSAttributedString {
        let base = UIFont.systemFont(ofSize: height / 1.2, weight: .semibold)
        let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: base.pointSize) } ?? base
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: UIColor.white,
        ])
    }
}
