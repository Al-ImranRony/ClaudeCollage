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
}
