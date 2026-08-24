//
//  VideoCompositionMath.swift
//  Caroullage
//
//  Step 04 slice 3 — pure helpers the video composition builder leans on, kept
//  separate so they're trivially unit-testable without any AVFoundation asset:
//  the per-cell placement transform, the overall composition duration, and the
//  effective per-cell audio gain.
//

import CoreGraphics
import Foundation

public enum VideoCompositionMath {

    /// Affine transform that places a `source`-sized video into `cell` (absolute
    /// canvas pixels), scaled to *fit* inside the cell (min scale) and centred.
    ///
    /// Fit — not fill — is the v1 choice: it guarantees the scaled clip never
    /// overflows its cell, so adjacent cells can be composited on separate layers
    /// without one bleeding over another. A fill+crop variant (edge-to-edge cover)
    /// is a later-slice refinement once the live preview can validate the crop.
    public static func aspectFitTransform(source: CGSize, in cell: CGRect) -> CGAffineTransform {
        guard source.width > 0, source.height > 0 else { return .identity }
        let scale = min(cell.width / source.width, cell.height / source.height)
        let scaledW = source.width * scale
        let scaledH = source.height * scale
        let tx = cell.midX - scaledW / 2
        let ty = cell.midY - scaledH / 2
        return CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: tx, ty: ty)
    }

    /// Aspect-FILL: scale a source to COVER the cell (max scale) and centre it.
    /// Pair with `fillCropRect` as the layer crop rectangle so the overflow doesn't
    /// spill into neighbouring cells. This is the default for a collage cell —
    /// edge-to-edge like VSCO / SCRL — versus the letterboxing `aspectFitTransform`.
    public static func aspectFillTransform(source: CGSize, in cell: CGRect) -> CGAffineTransform {
        guard source.width > 0, source.height > 0 else { return .identity }
        let scale = max(cell.width / source.width, cell.height / source.height)
        let scaledW = source.width * scale
        let scaledH = source.height * scale
        return CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                 tx: cell.midX - scaledW / 2, ty: cell.midY - scaledH / 2)
    }

    /// The centred sub-rectangle of `source` (in source pixels) matching the cell's
    /// aspect ratio — the region kept when filling. Symmetric about the source
    /// centre, so it is invariant to the crop-rectangle's coordinate-origin
    /// convention. Used as the layer instruction's crop rectangle.
    public static func fillCropRect(source: CGSize, cellAspect: CGFloat) -> CGRect {
        guard source.width > 0, source.height > 0, cellAspect > 0 else {
            return CGRect(origin: .zero, size: source)
        }
        if source.width / source.height > cellAspect {
            let width = source.height * cellAspect          // wider than the cell → crop the sides
            return CGRect(x: (source.width - width) / 2, y: 0, width: width, height: source.height)
        } else {
            let height = source.width / cellAspect          // taller than the cell → crop top/bottom
            return CGRect(x: 0, y: (source.height - height) / 2, width: source.width, height: height)
        }
    }

    /// The source crop rectangle for a cell with per-cell **framing** (pan/zoom).
    /// Zoom (≥ 1) punches into the fill crop; pan (each axis clamped to −1…1) slides
    /// the crop within the source, staying fully inside it. At zoom 1 / pan 0 this is
    /// exactly `fillCropRect`, so framing is a superset of plain fill. Because it
    /// only moves/resizes the *source* crop — never the output rect — a framed cell
    /// still exactly fills its cell and never overflows a neighbour, at any zoom.
    public static func framedCropRect(
        source: CGSize, cellAspect: CGFloat,
        zoom: CGFloat = 1, panX: CGFloat = 0, panY: CGFloat = 0
    ) -> CGRect {
        let base = fillCropRect(source: source, cellAspect: cellAspect)
        let z = max(1, zoom)
        let width = base.width / z
        let height = base.height / z
        let maxOffsetX = (source.width - width) / 2
        let maxOffsetY = (source.height - height) / 2
        let centreX = source.width / 2 + min(1, max(-1, panX)) * maxOffsetX
        let centreY = source.height / 2 + min(1, max(-1, panY)) * maxOffsetY
        return CGRect(x: centreX - width / 2, y: centreY - height / 2, width: width, height: height)
    }

    /// The layer transform that maps a source `crop` (same aspect as `cell`) onto
    /// the cell exactly — the placement used with `framedCropRect` / `fillCropRect`.
    public static func cropFillTransform(crop: CGRect, in cell: CGRect) -> CGAffineTransform {
        guard crop.width > 0, crop.height > 0 else { return .identity }
        let scale = cell.width / crop.width   // crop aspect == cell aspect ⇒ == cell.height/crop.height
        return CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                 tx: cell.minX - scale * crop.minX, ty: cell.minY - scale * crop.minY)
    }

    /// The composition duration is the longest cell; shorter cells either loop to
    /// fill it or simply end early (leaving background).
    public static func compositionDuration(cellDurations: [Double]) -> Double {
        cellDurations.max() ?? 0
    }

    /// Maps a rect from canvas space into the render-output space, aspect-fit and
    /// centred. Used to scale a collage up to a platform's target resolution
    /// (1080p / 4K) at export: a uniform scale with no offset when the canvas and
    /// render aspects match, and a centred letterbox when they don't.
    public static func renderMappedRect(_ rect: CGRect, canvas: CGSize, render: CGSize) -> CGRect {
        guard canvas.width > 0, canvas.height > 0 else { return rect }
        let scale = min(render.width / canvas.width, render.height / canvas.height)
        let offsetX = (render.width - canvas.width * scale) / 2
        let offsetY = (render.height - canvas.height * scale) / 2
        return CGRect(x: rect.minX * scale + offsetX, y: rect.minY * scale + offsetY,
                      width: rect.width * scale, height: rect.height * scale)
    }

    /// Per-cell audio gain for the audio mix: muted → 0, otherwise the volume
    /// clamped into 0…1.
    public static func effectiveVolume(isMuted: Bool, volume: Double) -> Float {
        guard !isMuted else { return 0 }
        return Float(min(1, max(0, volume)))
    }

    // MARK: - Transitions

    /// The opacity a cell's intro transition starts from (ramping to 1). Only the
    /// crossfade fades in; slide/zoom stay fully opaque and animate the transform.
    public static func transitionStartOpacity(_ style: CellTransition.Style) -> Float {
        style == .crossfade ? 0 : 1
    }

    /// The transform a cell's intro transition starts from (ramping to `base`, its
    /// resting placement). Slides begin offset by a cell width; zoom begins at 0.9×
    /// scale about the cell centre.
    public static func transitionStartTransform(
        style: CellTransition.Style,
        base: CGAffineTransform,
        cell: CGRect
    ) -> CGAffineTransform {
        switch style {
        case .crossfade:
            return base
        case .slideLeft:  // enters from the right, sliding left into place
            return base.concatenating(CGAffineTransform(translationX: cell.width, y: 0))
        case .slideRight: // enters from the left, sliding right into place
            return base.concatenating(CGAffineTransform(translationX: -cell.width, y: 0))
        case .zoomIn:
            let scale: CGFloat = 0.9
            let scaleAboutCentre = CGAffineTransform(translationX: cell.midX, y: cell.midY)
                .scaledBy(x: scale, y: scale)
                .translatedBy(x: -cell.midX, y: -cell.midY)
            return base.concatenating(scaleAboutCentre)
        }
    }
}
