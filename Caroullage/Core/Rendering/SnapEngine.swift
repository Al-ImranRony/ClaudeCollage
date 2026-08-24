//
//  SnapEngine.swift
//  Caroullage
//
//  Step 03a slice 7 — alignment snapping for draggable canvas elements (stickers).
//  Pure geometry over the NORMALIZED (0…1) canvas, so it's trivially unit-testable
//  and identical whatever the canvas pixel size. Given an element's centre, it
//  snaps each axis to the nearest guide (canvas centre + the rule-of-thirds lines)
//  when within a small threshold, and reports which guides engaged so the canvas
//  can draw them.
//

import CoreGraphics

public struct SnapResult: Equatable {
    /// The (possibly adjusted) centre, still normalized.
    public var center: CGPoint
    /// Normalized x positions of the vertical guide lines that engaged.
    public var verticalGuides: [CGFloat]
    /// Normalized y positions of the horizontal guide lines that engaged.
    public var horizontalGuides: [CGFloat]

    public var didSnap: Bool { !verticalGuides.isEmpty || !horizontalGuides.isEmpty }
}

public enum SnapEngine {

    /// Snap targets on each axis: the two rule-of-thirds lines and the centre.
    public static let candidates: [CGFloat] = [1.0 / 3.0, 0.5, 2.0 / 3.0]

    /// Snaps `center` to the nearest guide on each axis within `threshold`
    /// (normalized units). Axes are independent, so an element can snap to the
    /// vertical centre while staying free horizontally.
    public static func snap(center: CGPoint, threshold: CGFloat = 0.018) -> SnapResult {
        var result = SnapResult(center: center, verticalGuides: [], horizontalGuides: [])
        if let x = nearest(to: center.x, within: threshold) {
            result.center.x = x
            result.verticalGuides = [x]
        }
        if let y = nearest(to: center.y, within: threshold) {
            result.center.y = y
            result.horizontalGuides = [y]
        }
        return result
    }

    /// The closest candidate to `value`, or `nil` if none is within `threshold`.
    static func nearest(to value: CGFloat, within threshold: CGFloat) -> CGFloat? {
        guard let best = candidates.min(by: { abs($0 - value) < abs($1 - value) }),
              abs(best - value) <= threshold else { return nil }
        return best
    }
}
