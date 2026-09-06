//
//  EditorStageGeometry.swift
//  Caroullage
//
//  The stage's aspect-fit maths, kept pure so it is testable without a window and
//  so both editors get the same answer for "how big is this document on screen".
//

import AVFoundation
import UIKit

public enum EditorStageGeometry {

    /// The largest rect with `canvasSize`'s aspect ratio that fits inside `bounds`
    /// after `insets`, centred. A degenerate canvas size falls back to 1:1 rather
    /// than producing a zero or NaN rect. Centring itself is delegated to
    /// `AVMakeRect(aspectRatio:insideRect:)` — the same aspect-fit primitive
    /// `CanvasView` already uses — so this only adds the inset handling and the
    /// fallback that `AVMakeRect` does not provide.
    public static func canvasRect(
        canvasSize: CGSize,
        in bounds: CGRect,
        insets: UIEdgeInsets
    ) -> CGRect {
        let available = bounds.inset(by: insets)
        guard available.width > 0, available.height > 0 else { return .zero }

        let effectiveSize = (canvasSize.width > 0 && canvasSize.height > 0)
            ? canvasSize
            : CGSize(width: 1, height: 1)
        return AVMakeRect(aspectRatio: effectiveSize, insideRect: available)
    }
}
