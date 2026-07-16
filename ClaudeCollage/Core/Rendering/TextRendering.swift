//
//  TextRendering.swift
//  ClaudeCollage
//
//  Step 03a slice 5 — the SINGLE source of truth for turning a `TextOverlay` into
//  pixels. Both the live editor canvas (a UILabel per overlay, GPU-composited) and
//  the one-shot export/thumbnail compositor (`CollageRenderer`, Core Graphics) go
//  through here, so what the user sees on the canvas is exactly what exports.
//
//  `fontScale` maps the overlay's reference-canvas point sizes onto the caller's
//  target canvas: `targetCanvas.height / referenceCanvas.height`. It is 1 for a
//  full-resolution export (target == reference), < 1 for a downscaled thumbnail,
//  and `onScreenPoints / referencePixels` for the live canvas.
//

import UIKit

public enum TextRendering {

    /// The normalized (0…1) overlay frame resolved to absolute pixels in a canvas.
    public static func frame(for overlay: TextOverlay, in canvasPx: CGSize) -> CGRect {
        CGRect(
            x: overlay.frame.origin.x * canvasPx.width,
            y: overlay.frame.origin.y * canvasPx.height,
            width: overlay.frame.size.width * canvasPx.width,
            height: overlay.frame.size.height * canvasPx.height
        )
    }

    /// Resolves the overlay's named font at a concrete point size, layering the
    /// bold/italic toggles on as symbolic traits. Falls back to a rounded system
    /// font when the named face is unavailable, so text never renders blank.
    public static func font(for overlay: TextOverlay, fontScale: CGFloat) -> UIFont {
        let size = max(1, CGFloat(overlay.fontSize) * fontScale)
        let base = UIFont(name: overlay.fontName, size: size)
            ?? roundedSystemFont(size: size)

        var traits = base.fontDescriptor.symbolicTraits
        if overlay.isBold { traits.insert(.traitBold) }
        if overlay.isItalic { traits.insert(.traitItalic) }
        guard traits != base.fontDescriptor.symbolicTraits,
              let descriptor = base.fontDescriptor.withSymbolicTraits(traits) else {
            return base
        }
        return UIFont(descriptor: descriptor, size: size)
    }

    /// The attributed string the overlay draws, styled identically for preview and
    /// export. `fontScale` scales the point-based `fontSize` / `letterSpacing`.
    public static func attributedString(for overlay: TextOverlay, fontScale: CGFloat) -> NSAttributedString {
        let font = font(for: overlay, fontScale: fontScale)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = nsAlignment(overlay.alignment)
        paragraph.lineHeightMultiple = CGFloat(max(0.5, overlay.lineHeight))
        paragraph.lineBreakMode = .byWordWrapping

        let color = UIColor(hex: overlay.colorHex)
            .withAlphaComponent(CGFloat(min(max(overlay.opacity, 0), 1)))

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
            .kern: CGFloat(overlay.letterSpacing) * fontScale,
        ]
        if overlay.isUnderlined {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return NSAttributedString(string: overlay.text, attributes: attributes)
    }

    /// Draws the overlay into a Core Graphics context (export / thumbnail path),
    /// vertically centred within `absoluteFrame` and clipped to it — matching how a
    /// UILabel centres and clips its text on the live canvas.
    public static func draw(
        _ overlay: TextOverlay,
        in absoluteFrame: CGRect,
        fontScale: CGFloat,
        context cg: CGContext
    ) {
        guard !overlay.text.isEmpty, absoluteFrame.width > 0, absoluteFrame.height > 0 else { return }
        let attributed = attributedString(for: overlay, fontScale: fontScale)

        let measured = attributed.boundingRect(
            with: CGSize(width: absoluteFrame.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).height
        let drawnHeight = min(ceil(measured), absoluteFrame.height)
        let originY = absoluteFrame.minY + (absoluteFrame.height - drawnHeight) / 2

        cg.saveGState()
        cg.clip(to: absoluteFrame)
        attributed.draw(with: CGRect(x: absoluteFrame.minX, y: originY,
                                     width: absoluteFrame.width, height: drawnHeight),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil)
        cg.restoreGState()
    }

    // MARK: - Helpers

    private static func roundedSystemFont(size: CGFloat) -> UIFont {
        let system = UIFont.systemFont(ofSize: size, weight: .semibold)
        guard let descriptor = system.fontDescriptor.withDesign(.rounded) else { return system }
        return UIFont(descriptor: descriptor, size: size)
    }

    private static func nsAlignment(_ alignment: TextOverlay.Alignment) -> NSTextAlignment {
        switch alignment {
        case .leading: return .left
        case .center: return .center
        case .trailing: return .right
        case .justified: return .justified
        }
    }
}
