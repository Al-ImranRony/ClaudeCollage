//
//  CaptionPlacement.swift
//  Caroullage
//
//  Where a new caption lands. Both editors used to drop it on one fixed band
//  across the middle of the canvas — exactly where a template's own caption
//  usually sits (Caption Stack), so the new text landed on top of it and read
//  as a smudge. Pure geometry over normalized rects, so it is unit-testable.
//

import CoreGraphics

public enum CaptionPlacement {

    /// The preferred band first, then the same band stepped alternately below
    /// and above it, one band-and-a-bit at a time, as far as the canvas goes.
    public static func candidates(around preferred: CGRect) -> [CGRect] {
        guard preferred.height > 0 else { return [preferred] }
        let step = preferred.height * 1.15
        let maxY = 1 - preferred.height
        var result = [preferred]
        var offset: CGFloat = step
        while preferred.minY + offset <= maxY || preferred.minY - offset >= 0 {
            for y in [preferred.minY + offset, preferred.minY - offset] where y >= 0 && y <= maxY {
                result.append(CGRect(x: preferred.minX, y: y, width: preferred.width, height: preferred.height))
            }
            offset += step
        }
        return result
    }

    /// The first candidate that overlaps none of `existing`, or the first
    /// candidate when every one is taken (a crowded canvas: the default place
    /// is still the most predictable one).
    public static func firstFree(_ candidates: [CGRect], avoiding existing: [CGRect]) -> CGRect? {
        candidates.first { candidate in
            !existing.contains { $0.intersects(candidate) }
        } ?? candidates.first
    }
}
