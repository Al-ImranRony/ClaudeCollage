//
//  StickerRendering.swift
//  ClaudeCollage
//
//  Step 03a slice 6 — the SINGLE source of truth for turning a `StickerOverlay`
//  into pixels, exactly like `TextRendering` does for text. Both the live editor
//  canvas (a `StickerOverlayView` / UIImageView, GPU-composited) and the one-shot
//  Core Graphics export/thumbnail path go through here, so what the user drags on
//  the canvas is pixel-for-pixel what exports.
//
//  Stickers are SF Symbol glyphs tinted to the overlay's colour. Symbols are
//  resolution-independent, so a sticker stays crisp at any canvas scale (a plain
//  bundled PNG would blur when enlarged) — see the slice-6 notes for this
//  deviation from the plan's "256×256 PNG" wording; the pack-manifest architecture
//  it describes is preserved.
//

import UIKit

public enum StickerRendering {

    /// The normalized sticker resolved to its absolute square box in a canvas.
    /// The side is a fraction of the canvas WIDTH, centred on the normalized point.
    public static func frame(for overlay: StickerOverlay, in canvasPx: CGSize) -> CGRect {
        let side = max(1, CGFloat(overlay.sizeNorm) * canvasPx.width)
        let center = CGPoint(x: CGFloat(overlay.centerX) * canvasPx.width,
                             y: CGFloat(overlay.centerY) * canvasPx.height)
        return CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
    }

    /// The tinted symbol image for a sticker at a concrete pixel side. Falls back
    /// to a filled star when the named symbol is unavailable, so a sticker never
    /// renders blank.
    public static func image(for overlay: StickerOverlay, sidePx: CGFloat) -> UIImage? {
        let config = UIImage.SymbolConfiguration(pointSize: max(1, sidePx * 0.82), weight: .semibold)
        let base = UIImage(systemName: overlay.symbolName, withConfiguration: config)
            ?? UIImage(systemName: "star.fill", withConfiguration: config)
        let color = UIColor(hex: overlay.colorHex)
            .withAlphaComponent(CGFloat(min(max(overlay.opacity, 0), 1)))
        return base?.withTintColor(color, renderingMode: .alwaysOriginal)
    }

    /// Draws the sticker into a Core Graphics context (export / thumbnail path),
    /// aspect-fit and rotated within its box — matching how the live UIImageView
    /// (scaleAspectFit + a rotation transform) shows it.
    public static func draw(_ overlay: StickerOverlay, in canvasPx: CGSize, context cg: CGContext) {
        let box = frame(for: overlay, in: canvasPx)
        guard box.width > 0, let image = image(for: overlay, sidePx: box.width) else { return }

        let fitted = aspectFitSize(image.size, in: box.size)
        cg.saveGState()
        cg.translateBy(x: box.midX, y: box.midY)
        cg.rotate(by: CGFloat(overlay.rotation))
        image.draw(in: CGRect(x: -fitted.width / 2, y: -fitted.height / 2,
                              width: fitted.width, height: fitted.height))
        cg.restoreGState()
    }

    // MARK: - Helpers

    private static func aspectFitSize(_ size: CGSize, in box: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return box }
        let scale = min(box.width / size.width, box.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}
