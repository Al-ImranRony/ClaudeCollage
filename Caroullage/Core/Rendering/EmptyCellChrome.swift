//
//  EmptyCellChrome.swift
//  Caroullage
//
//  Step 06 (visual) — what an empty photo zone looks like.
//
//  A bare "+" glyph floating in a flat well left the collage grid reading as one
//  undifferentiated block: you could not see, at a glance, how many zones a
//  template had or where one ended and the next began. Empty zones now wear two
//  pieces of chrome — a soft outline tracing the zone's real boundary, and a
//  filled circular "+" chip at its centre.
//
//  All of the geometry lives here because this chrome is drawn twice: as views /
//  layers on the live canvas (GPU) and through Core Graphics for exports and
//  template thumbnails. Two implementations of the same look drift; one set of
//  numbers cannot.
//

import UIKit

enum EmptyCellChrome {

    // MARK: - Geometry

    /// Where a zone's "+" chip sits, and how big it is.
    ///
    /// The centre is the shape's own middle, not its bounding box's. On a diagonal
    /// split both triangles share one bounding box, so bounding-box centres put
    /// both chips in the same spot — one zone silently loses its affordance.
    ///
    /// The diameter is proportional to the room the chip actually has at that
    /// point (half the short side for a rectangle, the distance to the nearest
    /// edge for a polygon) and then capped against the canvas: a full-bleed
    /// single-cell layout would otherwise get a chip the size of a dinner plate.
    /// The cap is what makes the chip read as roughly one fixed affordance across
    /// every zone of a template, which is the behaviour the reference apps have.
    static func chipPlacement(
        shape: CellClipShape, frame: CGRect, canvasShortSide: CGFloat
    ) -> (center: CGPoint, diameter: CGFloat) {
        let boundsCenter = CGPoint(x: frame.midX, y: frame.midY)
        guard frame.width > 0, frame.height > 0 else { return (boundsCenter, 0) }

        let center: CGPoint
        let clearance: CGFloat
        switch shape {
        case .rectangle, .ellipse:
            center = boundsCenter
            clearance = min(frame.width, frame.height) / 2
        case let .polygon(points), let .custom(points):
            let absolute = points.map {
                CGPoint(x: frame.minX + $0.x * frame.width, y: frame.minY + $0.y * frame.height)
            }
            guard let centroid = Self.centroid(of: absolute) else {
                return (boundsCenter, min(frame.width, frame.height) * 0.42)
            }
            center = centroid
            clearance = Self.distanceToNearestEdge(from: centroid, of: absolute)
        }

        let diameter = min(clearance * 2 * 0.42, max(canvasShortSide, 1) * 0.13)
        return (center, max(0, diameter))
    }

    /// Diameter of the "+" chip for a plain rectangular zone.
    static func chipDiameter(cellSize: CGSize, canvasShortSide: CGFloat) -> CGFloat {
        chipPlacement(
            shape: .rectangle,
            frame: CGRect(origin: .zero, size: cellSize),
            canvasShortSide: canvasShortSide
        ).diameter
    }

    /// Area-weighted centroid, which is the visual middle of a polygon. The plain
    /// average of the vertices is not: it drifts towards whichever side happens to
    /// carry more of them.
    private static func centroid(of points: [CGPoint]) -> CGPoint? {
        guard points.count >= 3 else { return points.first }
        var area: CGFloat = 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        for (index, point) in points.enumerated() {
            let next = points[(index + 1) % points.count]
            let cross = point.x * next.y - next.x * point.y
            area += cross
            x += (point.x + next.x) * cross
            y += (point.y + next.y) * cross
        }
        area /= 2
        guard abs(area) > 1e-9 else {
            // Degenerate (collinear) — the vertex average is the best available.
            let count = CGFloat(points.count)
            return CGPoint(x: points.reduce(0) { $0 + $1.x } / count,
                           y: points.reduce(0) { $0 + $1.y } / count)
        }
        return CGPoint(x: x / (6 * area), y: y / (6 * area))
    }

    /// How much room a point has before it runs into the shape's boundary.
    private static func distanceToNearestEdge(from point: CGPoint, of points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else { return 0 }
        var nearest = CGFloat.greatestFiniteMagnitude
        for (index, start) in points.enumerated() {
            let end = points[(index + 1) % points.count]
            nearest = min(nearest, distance(from: point, toSegment: (start, end)))
        }
        return nearest
    }

    private static func distance(from point: CGPoint, toSegment segment: (CGPoint, CGPoint)) -> CGFloat {
        let (start, end) = segment
        let delta = CGPoint(x: end.x - start.x, y: end.y - start.y)
        let lengthSquared = delta.x * delta.x + delta.y * delta.y
        guard lengthSquared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let t = min(1, max(0, ((point.x - start.x) * delta.x + (point.y - start.y) * delta.y) / lengthSquared))
        let closest = CGPoint(x: start.x + delta.x * t, y: start.y + delta.y * t)
        return hypot(point.x - closest.x, point.y - closest.y)
    }

    /// Half-extent of the "+" arms as a fraction of the chip diameter. Small
    /// enough that the disc keeps a clear ring of padding around the glyph — a
    /// "+" that reaches for the edge reads as a close button, not an add one.
    private static let plusExtentRatio: CGFloat = 0.22

    /// Stroke width of the "+" arms for a given chip.
    static func plusLineWidth(chipDiameter: CGFloat) -> CGFloat {
        max(1, chipDiameter * 0.078)
    }

    /// The "+" cross as a path centred in `center`, with round caps in mind.
    static func plusPath(center: CGPoint, chipDiameter: CGFloat) -> CGPath {
        let arm = chipDiameter * plusExtentRatio
        let path = CGMutablePath()
        path.move(to: CGPoint(x: center.x - arm, y: center.y))
        path.addLine(to: CGPoint(x: center.x + arm, y: center.y))
        path.move(to: CGPoint(x: center.x, y: center.y - arm))
        path.addLine(to: CGPoint(x: center.x, y: center.y + arm))
        return path
    }

    /// Width of the zone outline. Scaled off the canvas rather than the cell so
    /// every zone in a template is traced with the same weight — an outline that
    /// thickened with the cell would make the big zone look selected.
    ///
    /// A hairline: ~1.2pt on a phone-sized canvas, matching the 1pt border the
    /// video editor's slots have always carried. The heavier line this started at
    /// drew attention to itself instead of to the zone, and two adjacent zones
    /// put two of them side by side across every seam in the grid.
    static func outlineWidth(canvasShortSide: CGFloat) -> CGFloat {
        max(1, canvasShortSide * 0.0035)
    }

    /// The zone outline, traced just inside the cell's own boundary.
    ///
    /// Inset by half the stroke so the whole line lands inside the cell: a stroke
    /// straddling the edge is half-eaten by the cell's clip (live canvas) or bleeds
    /// into the border gap (export). `.rectangle` / `.ellipse` are defined by their
    /// frame, so the frame is what shrinks; vertex shapes offset each edge along its
    /// own normal via `CellClipShape.inset(by:in:)`.
    static func outlinePath(
        shape: CellClipShape, frame: CGRect, cornerRadius: CGFloat, lineWidth: CGFloat
    ) -> CGPath {
        let inset = lineWidth / 2
        let radius = max(0, cornerRadius - inset)
        guard frame.width > lineWidth, frame.height > lineWidth else {
            return shape.path(in: frame, cornerRadius: cornerRadius)
        }
        switch shape {
        case .rectangle, .ellipse:
            return shape.path(in: frame.insetBy(dx: inset, dy: inset), cornerRadius: radius)
        case .polygon, .custom:
            return shape.inset(by: inset, in: frame).path(in: frame, cornerRadius: radius)
        }
    }

    // MARK: - Core Graphics drawing (export + template thumbnails)

    /// Paints the well, its outline and the "+" chip into `context`.
    ///
    /// The caller has already clipped to the cell's shape, so the fill can be a
    /// plain rect fill.
    static func draw(
        in frame: CGRect,
        shape: CellClipShape,
        cornerRadius: CGFloat,
        canvasShortSide: CGFloat,
        context cg: CGContext
    ) {
        Theme.Color.cellWell.setFill()
        cg.fill(frame)

        let lineWidth = outlineWidth(canvasShortSide: canvasShortSide)
        cg.saveGState()
        cg.setStrokeColor(Theme.Color.cellWellOutline.cgColor)
        cg.setLineWidth(lineWidth)
        cg.addPath(outlinePath(
            shape: shape, frame: frame, cornerRadius: cornerRadius, lineWidth: lineWidth))
        cg.strokePath()
        cg.restoreGState()

        let (center, diameter) = chipPlacement(
            shape: shape, frame: frame, canvasShortSide: canvasShortSide)
        guard diameter > 0 else { return }
        let chip = CGRect(
            x: center.x - diameter / 2, y: center.y - diameter / 2,
            width: diameter, height: diameter)

        cg.saveGState()
        Theme.Color.cellWellChip.setFill()
        cg.fillEllipse(in: chip)
        cg.setStrokeColor(Theme.Color.cellWellChipInk.cgColor)
        cg.setLineWidth(plusLineWidth(chipDiameter: diameter))
        cg.setLineCap(.round)
        cg.addPath(plusPath(center: center, chipDiameter: diameter))
        cg.strokePath()
        cg.restoreGState()
    }
}
