//
//  VideoCompositionMath.swift
//  ClaudeCollage
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

    /// The composition duration is the longest cell; shorter cells either loop to
    /// fill it or simply end early (leaving background).
    public static func compositionDuration(cellDurations: [Double]) -> Double {
        cellDurations.max() ?? 0
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
