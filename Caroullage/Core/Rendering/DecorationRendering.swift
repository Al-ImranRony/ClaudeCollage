//
//  DecorationRendering.swift
//  Caroullage
//
//  Paints a template's `CanvasDecoration`s. The one painter both the live
//  canvas (rasterized into a layer once per change) and `CollageRenderer`
//  (export and gallery previews) call, so the instant-print card in the editor
//  is the card in the file — the same contract `BackgroundRendering` keeps.
//

import UIKit

enum DecorationRendering {

    /// Draws `decorations`, in order, into a context whose user space is
    /// `canvasSize` (origin zero). Resolution-independent: the geometry is
    /// normalized, so the caller only has to size the context.
    static func draw(_ decorations: [CanvasDecoration], canvasSize: CGSize, in context: CGContext) {
        guard !decorations.isEmpty, canvasSize.width > 0, canvasSize.height > 0 else { return }
        let shortSide = min(canvasSize.width, canvasSize.height)

        for decoration in decorations {
            let rect = CGRect(
                x: decoration.frame.minX * canvasSize.width,
                y: decoration.frame.minY * canvasSize.height,
                width: decoration.frame.width * canvasSize.width,
                height: decoration.frame.height * canvasSize.height)
            guard rect.width > 0, rect.height > 0 else { continue }

            let path = self.path(for: decoration, in: rect, shortSide: shortSide)
            context.saveGState()
            if let shadow = shadowGeometry(strength: decoration.shadow, shortSide: shortSide) {
                context.setShadow(offset: shadow.offset, blur: shadow.blur,
                                  color: UIColor.black.withAlphaComponent(shadow.opacity).cgColor)
            }
            context.addPath(path)
            context.setFillColor(UIColor(hex: decoration.colorHex).cgColor)
            context.fillPath()
            context.restoreGState()
        }
    }

    /// The decorations rasterized at `scale` pixels per canvas point, on a clear
    /// ground — what the live canvas puts in its decoration layer. Nil when there
    /// is nothing to draw, so a plain collage carries no extra bitmap.
    static func image(_ decorations: [CanvasDecoration], canvasSize: CGSize, scale: CGFloat) -> CGImage? {
        guard !decorations.isEmpty, canvasSize.width > 0, canvasSize.height > 0, scale > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: canvasSize, format: format).image { context in
            draw(decorations, canvasSize: canvasSize, in: context.cgContext)
        }.cgImage
    }

    static func path(for decoration: CanvasDecoration, in rect: CGRect, shortSide: CGFloat) -> CGPath {
        switch decoration.shape {
        case .ellipse:
            return CGPath(ellipseIn: rect, transform: nil)
        case .rectangle:
            let radius = min(CGFloat(decoration.cornerRadius) * shortSide,
                             min(rect.width, rect.height) / 2)
            guard radius > 0 else { return CGPath(rect: rect, transform: nil) }
            return UIBezierPath(roundedRect: rect, cornerRadius: radius).cgPath
        }
    }

    /// A softer, lower shadow than a cell's: a print lying on a table rather than
    /// a card floating over it. Relative to the short side, like the geometry.
    private static func shadowGeometry(
        strength: Double, shortSide: CGFloat
    ) -> (offset: CGSize, blur: CGFloat, opacity: CGFloat)? {
        guard strength > 0.001 else { return nil }
        let s = CGFloat(min(strength, 1))
        return (offset: CGSize(width: 0, height: shortSide * 0.006 * s),
                blur: shortSide * (0.01 + 0.025 * s),
                opacity: 0.12 + 0.28 * s)
    }
}
