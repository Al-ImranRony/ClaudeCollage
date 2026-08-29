//
//  CarouselStripLayout.swift
//  Caroullage
//
//  Step 06 — the geometry of the frame navigator.
//
//  The navigator used to be a 2-column grid with 16pt gutters, which was the same
//  for every carousel regardless of what the carousel was. That is wrong for the
//  format: the frames of a panoramic carousel are one photograph cut into pieces,
//  and a gutter draws a seam the exported post does not have. Even for a matched
//  carousel, a gap misrepresents how the post is read — as a continuous swipe.
//
//  So the strip is one canvas: panels edge to edge along the carousel's axis, a
//  hairline where they meet, and rounding only on the two outermost ends.
//

import CoreGraphics
import QuartzCore

extension SplitAxis {

    /// What the user calls this direction. Since Step 06 the axis is offered for
    /// every carousel type, not only panoramic, so it names how the post is read
    /// rather than only how a source photo is cut.
    var displayName: String {
        switch self {
        case .horizontal: return "Horizontal"
        case .vertical: return "Vertical"
        }
    }

    var symbolName: String {
        switch self {
        case .horizontal: return "rectangle.split.3x1"
        case .vertical: return "rectangle.split.1x2"
        }
    }
}

enum CarouselStripLayout {

    /// Width of the line drawn between neighbouring panels. Not a gap — the panels
    /// still touch; this only makes the join legible.
    static let seamWidth: CGFloat = 1

    /// The corner radius applied to the strip's outer ends.
    static let cornerRadius: CGFloat = 14

    /// Keeps a panel positive before the strip has been laid out. A zero-sized
    /// item makes `UICollectionViewFlowLayout` throw rather than degrade.
    private static let minimum: CGFloat = 1

    /// How much of the strip a single panel may occupy along the scroll axis.
    ///
    /// This is the number that makes the strip read as a strip. Sizing a panel to
    /// fill the cross axis and taking the other dimension from the aspect looks
    /// right on paper, and on a 4:5 canvas it produces a panel exactly as wide as
    /// the screen — one frame at a time, no visible neighbour, and nothing to say
    /// the frames are continuous. Capping the main axis leaves the next panel
    /// peeking in, which is the whole point of laying them out adjacently.
    private static let visibleFraction: CGFloat = 0.62

    /// The size of one frame panel.
    ///
    /// The panel fills the strip's cross axis and takes its other dimension from
    /// the canvas aspect, then shrinks — keeping the aspect, never letterboxing —
    /// until it is within both the container and the peek allowance above.
    static func panelSize(axis: SplitAxis, canvasSize: CGSize, container: CGSize) -> CGSize {
        let aspect = canvasSize.width > 0 && canvasSize.height > 0
            ? canvasSize.width / canvasSize.height
            : 1
        let maxWidth = max(container.width, minimum)
        let maxHeight = max(container.height, minimum)

        switch axis {
        case .horizontal:
            let widthLimit = maxWidth * visibleFraction
            var height = maxHeight
            var width = height * aspect
            if width > widthLimit {
                width = widthLimit
                height = width / aspect
            }
            return CGSize(width: width, height: height)

        case .vertical:
            let heightLimit = maxHeight * visibleFraction
            var width = maxWidth
            var height = width / aspect
            if height > heightLimit {
                height = heightLimit
                width = height * aspect
            }
            return CGSize(width: width, height: height)
        }
    }

    /// Which of a panel's corners are rounded, given where it sits in the strip.
    ///
    /// Only the ends. Rounding every panel would draw four corners at every seam,
    /// which is precisely the "these are separate cards" reading the strip exists
    /// to remove. A one-frame carousel is not a strip, so it rounds all four.
    static func roundedCorners(at index: Int, of count: Int, axis: SplitAxis) -> CACornerMask {
        let all: CACornerMask = [
            .layerMinXMinYCorner, .layerMaxXMinYCorner,
            .layerMinXMaxYCorner, .layerMaxXMaxYCorner,
        ]
        guard count > 1 else { return all }

        let isFirst = index == 0
        let isLast = index == count - 1

        switch axis {
        case .horizontal:
            if isFirst { return [.layerMinXMinYCorner, .layerMinXMaxYCorner] }
            if isLast { return [.layerMaxXMinYCorner, .layerMaxXMaxYCorner] }
        case .vertical:
            if isFirst { return [.layerMinXMinYCorner, .layerMaxXMinYCorner] }
            if isLast { return [.layerMinXMaxYCorner, .layerMaxXMaxYCorner] }
        }
        return []
    }
}
