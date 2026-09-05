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
    }

    /// Applies the presentation treatment. Kept separate from typesetting so `.pill`
    /// — which paints a background sized from the MEASURED text, not just the
    /// typeset attributes — can be a no-op here and handled by `draw` /
    /// `backgroundRect` instead. `.highlight` is different: `.backgroundColor` is a
    /// per-line NSAttributedString attribute, so applying it here is exactly what
    /// makes it render identically on the live canvas (a UILabel) and in both
    /// export paths, with no separate painting step needed anywhere.
    private static func applyStyle(
        _ style: TextStyle,
        fontScale: CGFloat,
        to attributes: inout [NSAttributedString.Key: Any]
    ) {
        let colour = UIColor(hex: style.colorHex)
        let width = CGFloat(style.width) * fontScale

        switch style.kind {
        case .plain, .pill:
            break

        case .highlight:
            attributes[.backgroundColor] = colour

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
        if let background = backgroundRect(for: overlay, in: absoluteFrame, fontScale: fontScale) {
            cg.saveGState()
            cg.setFillColor(UIColor(hex: overlay.style.colorHex).cgColor)
            UIBezierPath(roundedRect: background.rect, cornerRadius: background.cornerRadius).fill()
            cg.restoreGState()
        }
        attributed.draw(with: CGRect(x: absoluteFrame.minX, y: originY,
                                     width: absoluteFrame.width, height: drawnHeight),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil)
        cg.restoreGState()
    }

    /// The pill background rect for an overlay, in the same coordinate space as
    /// `absoluteFrame`, or nil when the style paints no background (every kind but
    /// `.pill` — `.highlight` is an attributed-string attribute now, see
    /// `applyStyle`). Sized from the MEASURED text, not the whole `absoluteFrame`,
    /// and positioned to match the overlay's alignment within it, so the pill hugs
    /// short text instead of spanning the entire text box. Shared by the Core
    /// Graphics export/thumbnail path (`draw`) and the live canvas's
    /// `TextOverlayView`, so the two can't disagree.
    public static func backgroundRect(
        for overlay: TextOverlay,
        in absoluteFrame: CGRect,
        fontScale: CGFloat
    ) -> (rect: CGRect, cornerRadius: CGFloat)? {
        guard overlay.style.kind == .pill, !overlay.text.isEmpty,
              absoluteFrame.width > 0, absoluteFrame.height > 0 else { return nil }

        let attributed = attributedString(for: overlay, fontScale: fontScale)
        let measured = attributed.boundingRect(
            with: CGSize(width: absoluteFrame.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let textWidth = min(ceil(measured.width), absoluteFrame.width)
        let textHeight = min(ceil(measured.height), absoluteFrame.height)
        let originY = absoluteFrame.minY + (absoluteFrame.height - textHeight) / 2
        let originX: CGFloat
        switch overlay.alignment {
        case .leading, .justified:
            originX = absoluteFrame.minX
        case .center:
            originX = absoluteFrame.minX + (absoluteFrame.width - textWidth) / 2
        case .trailing:
            originX = absoluteFrame.maxX - textWidth
        }
        let textRect = CGRect(x: originX, y: originY, width: textWidth, height: textHeight)

        let inset = CGFloat(overlay.style.width) * fontScale
        let outset = textRect.insetBy(dx: -inset, dy: -inset * StyleRatio.pillVerticalInset)
        // The outward inset can overflow `absoluteFrame` (a large style width, or a
        // text box with little room to spare); clamp rather than let the caller's
        // rectangular clip crop the rounded corners into a flat notch.
        let rect = outset.intersection(absoluteFrame)
        guard rect.width > 0, rect.height > 0 else { return nil }
        let radius = min(rect.height / 2, inset * StyleRatio.pillCornerInset)
        return (rect, max(0, radius))
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
