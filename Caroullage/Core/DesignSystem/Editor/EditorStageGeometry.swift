//
//  EditorStageGeometry.swift
//  Caroullage
//
//  The stage's aspect-fit maths, kept pure so it is testable without a window and
//  so both editors get the same answer for "how big is this document on screen".
//

import CoreGraphics
import UIKit

public enum EditorStageGeometry {

    /// The largest rect with `canvasSize`'s aspect ratio that fits inside `bounds`
    /// after `insets`, centred. A degenerate canvas size falls back to 1:1 rather
    /// than producing a zero or NaN rect.
    public static func canvasRect(
        canvasSize: CGSize,
        in bounds: CGRect,
        insets: UIEdgeInsets
    ) -> CGRect {
        let available = bounds.inset(by: insets)
        guard available.width > 0, available.height > 0 else { return .zero }

        let aspect: CGFloat
        if canvasSize.width > 0, canvasSize.height > 0 {
            aspect = canvasSize.width / canvasSize.height
        } else {
            aspect = 1
        }

        // Width-limited when the document is wider than the space it is given.
        var size = CGSize(width: available.width, height: available.width / aspect)
        if size.height > available.height {
            size = CGSize(width: available.height * aspect, height: available.height)
        }

        return CGRect(
            x: available.midX - size.width / 2,
            y: available.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
