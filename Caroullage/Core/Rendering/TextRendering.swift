//
//  TextRendering.swift
//  Caroullage
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
        applyStyle(overlay.style, fontScale: fontScale, to: &attributes)
        return NSAttributedString(string: overlay.text, attributes: attributes)
    }

    // `TextStyle` carries ONE `width` for every treatment, so the treatments that
    // need a second dimension derive it here by a fixed ratio. Naming them makes the
    // coupling legible: a `.shadow` cannot be art-directed as "soft blur, short
    // offset" versus "sharp blur, long offset" — every shadow rides one curve. If a
    // designer ever needs those independently, the fix is a second field on
    // `TextStyle`, not a new literal in this file.
    private enum StyleRatio {
        /// Shadow offset as a fraction of `width`; the blur uses `width` directly.
        static let shadowOffset: CGFloat = 0.35
        /// A glow is a blur with no offset, softer than a drop shadow of the same width.
        static let glowBlur: CGFloat = 1.6
        /// Pill: generous horizontal inset, tighter vertical, near-capsule corners.
        static let pillVerticalInset: CGFloat = 0.6
        static let pillCornerInset: CGFloat = 2
        /// Highlight: hugs the text, marker-pen corners.
        static let highlightHorizontalInset: CGFloat = 0.5
        static let highlightVerticalInset: CGFloat = 0.25
        static let highlightCorner: CGFloat = 0.3
    }

    /// Applies the presentation treatment. Kept separate from typesetting so the
    /// pill / highlight kinds — which paint behind the text rather than changing it
    /// — can be no-ops here and handled in `draw`.
    private static func applyStyle(
        _ style: TextStyle,
        fontScale: CGFloat,
        to attributes: inout [NSAttributedString.Key: Any]
    ) {
        let colour = UIColor(hex: style.colorHex)
        let width = CGFloat(style.width) * fontScale

        switch style.kind {
        case .plain, .pill, .highlight:
            break

        case .stroke:
            // NEGATIVE means stroke AND fill. A positive value hollows the glyph out.
            attributes[.strokeColor] = colour
            attributes[.strokeWidth] = -width

        case .shadow:
            let shadow = NSShadow()
            shadow.shadowColor = colour.withAlphaComponent(0.55)
            shadow.shadowBlurRadius = max(1, width)
            shadow.shadowOffset = CGSize(width: 0, height: max(1, width * StyleRatio.shadowOffset))
            attributes[.shadow] = shadow

        case .glow:
            let shadow = NSShadow()
            shadow.shadowColor = colour
            shadow.shadowBlurRadius = max(1, width * StyleRatio.glowBlur)
            shadow.shadowOffset = .zero
            attributes[.shadow] = shadow
        }
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
        drawBackground(for: overlay.style,
                       textRect: CGRect(x: absoluteFrame.minX, y: originY,
                                        width: absoluteFrame.width, height: drawnHeight),
                       fontScale: fontScale,
                       context: cg)
        attributed.draw(with: CGRect(x: absoluteFrame.minX, y: originY,
                                     width: absoluteFrame.width, height: drawnHeight),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil)
        cg.restoreGState()
    }

    /// Paints the solid backgrounds that sit BEHIND the glyphs. `.pill` is a rounded
    /// rectangle around the whole block; `.highlight` hugs the text with square-ish
    /// corners, marker-pen style.
    private static func drawBackground(
        for style: TextStyle,
        textRect: CGRect,
        fontScale: CGFloat,
        context cg: CGContext
    ) {
        let inset = CGFloat(style.width) * fontScale
        let rect: CGRect
        let radius: CGFloat

        switch style.kind {
        case .pill:
            rect = textRect.insetBy(dx: -inset, dy: -inset * StyleRatio.pillVerticalInset)
            radius = min(rect.height / 2, inset * StyleRatio.pillCornerInset)
        case .highlight:
            rect = textRect.insetBy(dx: -inset * StyleRatio.highlightHorizontalInset, dy: -inset * StyleRatio.highlightVerticalInset)
            radius = inset * StyleRatio.highlightCorner
        case .plain, .shadow, .stroke, .glow:
            return
        }

        guard rect.width > 0, rect.height > 0 else { return }
        cg.saveGState()
        cg.setFillColor(UIColor(hex: style.colorHex).cgColor)
        UIBezierPath(roundedRect: rect, cornerRadius: max(0, radius)).fill()
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
