//
//  VideoTimelineGeometry.swift
//  Caroullage
//
//  Maps composition seconds onto timeline points and back. Pure, so the mapping is
//  testable without a window and the timeline view stays a renderer of whatever it
//  is handed — the same split `EditorStageGeometry` uses for the canvas.
//

import CoreGraphics

public enum VideoTimelineGeometry {

    /// The x offset for `time`, in a track `width` points wide. A zero or negative
    /// duration maps everything to 0 rather than producing NaN.
    public static func x(forTime time: Double, duration: Double, width: CGFloat) -> CGFloat {
        guard duration > 0, width > 0 else { return 0 }
        let fraction = min(max(time / duration, 0), 1)
        return CGFloat(fraction) * width
    }

    /// The composition time at `x`, clamped into `0...duration`.
    public static func time(forX x: CGFloat, duration: Double, width: CGFloat) -> Double {
        guard duration > 0, width > 0 else { return 0 }
        let fraction = min(max(x / width, 0), 1)
        return Double(fraction) * duration
    }

    /// The rect a clip occupies in a lane, given its start and duration.
    public static func laneRect(
        start: Double,
        duration: Double,
        compositionDuration: Double,
        in bounds: CGRect
    ) -> CGRect {
        let minX = x(forTime: start, duration: compositionDuration, width: bounds.width)
        let maxX = x(forTime: start + duration, duration: compositionDuration, width: bounds.width)
        return CGRect(x: bounds.minX + minX, y: bounds.minY,
                      width: max(0, maxX - minX), height: bounds.height)
    }
}
