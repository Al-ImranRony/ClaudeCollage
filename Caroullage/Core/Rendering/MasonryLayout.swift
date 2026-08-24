//
//  MasonryLayout.swift
//  Caroullage
//
//  Step 05b Part C.
//
//  The gallery used to crop every project into the same square tile, so a 9:16
//  carousel and a 1:1 grid arrived looking identical and the user could not tell
//  their own work apart at a glance. Cards now keep their real proportions and
//  the columns are balanced instead.
//
//  This is deliberately a pure function over aspect ratios rather than a
//  `UICollectionViewLayout` subclass: column placement is the part that can be
//  wrong, and this way it is arithmetic that can be tested without a simulator.
//  `NSCollectionLayoutGroup.custom` consumes the frames.
//

import CoreGraphics

public enum MasonryLayout {

    public struct Result: Equatable {
        public let frames: [CGRect]
        public let totalHeight: CGFloat
    }

    /// The flattest and tallest a card may get, as a multiple of its width.
    ///
    /// Without these a panorama becomes a sliver and a tall crop becomes a card
    /// taller than the screen, and in both cases the grid stops being scannable.
    /// Clamping crops the thumbnail rather than the layout, which is the right
    /// way round: the layout is the thing the user reads.
    public static let minHeightRatio: CGFloat = 0.68
    public static let maxHeightRatio: CGFloat = 1.55

    /// Places each card in whichever column is currently shortest.
    ///
    /// - Parameters:
    ///   - aspectRatios: width ÷ height per item, in display order. A
    ///     non-positive or non-finite value is treated as square — that is what
    ///     a project with no thumbnail yet looks like.
    ///   - captionHeight: fixed room under each thumbnail for name and date, so
    ///     captions line up even though the thumbnails do not.
    public static func frames(
        aspectRatios: [CGFloat],
        columns: Int,
        containerWidth: CGFloat,
        spacing: CGFloat,
        captionHeight: CGFloat
    ) -> Result {
        guard !aspectRatios.isEmpty, columns > 0, containerWidth > 0 else {
            return Result(frames: [], totalHeight: 0)
        }

        let totalSpacing = spacing * CGFloat(columns - 1)
        let columnWidth = (containerWidth - totalSpacing) / CGFloat(columns)
        guard columnWidth > 0 else { return Result(frames: [], totalHeight: 0) }

        var columnHeights = [CGFloat](repeating: 0, count: columns)
        var frames: [CGRect] = []
        frames.reserveCapacity(aspectRatios.count)

        for ratio in aspectRatios {
            let column = shortestColumn(of: columnHeights)
            let thumbnailHeight = columnWidth * heightMultiplier(for: ratio)
            let height = thumbnailHeight + captionHeight

            let x = (columnWidth + spacing) * CGFloat(column)
            let y = columnHeights[column]
            frames.append(CGRect(x: x, y: y, width: columnWidth, height: height))

            columnHeights[column] = y + height + spacing
        }

        // Each column carries a trailing gap that is not part of the content.
        let totalHeight = (columnHeights.max() ?? 0) - spacing
        return Result(frames: frames, totalHeight: max(0, totalHeight))
    }

    /// Ties go to the leftmost column, so a fresh grid of equal cards fills
    /// left-to-right the way a plain grid would.
    private static func shortestColumn(of heights: [CGFloat]) -> Int {
        var best = 0
        for (index, height) in heights.enumerated() where height < heights[best] - 0.0001 {
            best = index
        }
        return best
    }

    private static func heightMultiplier(for aspectRatio: CGFloat) -> CGFloat {
        guard aspectRatio.isFinite, aspectRatio > 0 else { return 1 }
        return min(max(1 / aspectRatio, minHeightRatio), maxHeightRatio)
    }
}
