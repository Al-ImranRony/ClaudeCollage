//
//  CellClipShape.swift
//  Caroullage
//
//  Step 02 — the parametric description of a cell's boundary.
//
//  Rather than storing a non-`Sendable` `CGPath` on the (value-typed, `Codable`,
//  `Sendable`) `CellFrame`, a cell carries this lightweight descriptor and the
//  actual `CGPath` is generated on demand from `(shape, frame)`. This keeps the
//  whole layout pipeline pure and unit-testable, and lets shapes serialize into
//  template JSON and undo snapshots for free.
//
//  Points are normalized 0.0…1.0 within the cell's bounding `frame`, so the same
//  descriptor scales to any canvas size.
//

import CoreGraphics

public enum CellClipShape: Equatable, Sendable, Codable {

    /// A plain (optionally rounded) rectangle filling the cell frame. The fast
    /// path — cells with this shape need no mask layer in the live canvas.
    case rectangle

    /// An ellipse inscribed in the cell frame (a circle when the frame is square).
    case ellipse

    /// A closed straight-edged polygon defined by normalized vertices.
    case polygon(points: [CGPoint])

    /// A user-drawn boundary (premium bezier editor). Rendered as a closed
    /// polyline in v1; curve smoothing can be layered on later without changing
    /// the stored representation.
    case custom(points: [CGPoint])

    /// Whether this is the rectangle fast path (no CAShapeLayer mask required).
    public var isRectangle: Bool {
        if case .rectangle = self { return true }
        return false
    }

    /// The absolute `CGPath` for this shape inside `frame`.
    ///
    /// - Parameter cornerRadius: rounds `.rectangle` corners, and rounds the
    ///   vertices of `.polygon` / `.custom` by replacing each one with a
    ///   quadratic curve. Ignored by `.ellipse`, which has no corners.
    public func path(in frame: CGRect, cornerRadius: CGFloat = 0) -> CGPath {
        switch self {
        case .rectangle:
            return CGPath(
                roundedRect: frame,
                cornerWidth: min(cornerRadius, frame.width / 2),
                cornerHeight: min(cornerRadius, frame.height / 2),
                transform: nil
            )
        case .ellipse:
            return CGPath(ellipseIn: frame, transform: nil)
        case let .polygon(points), let .custom(points):
            return cornerRadius > 0
                ? Self.roundedClosedPath(points, in: frame, cornerRadius: cornerRadius)
                : Self.closedPath(points, in: frame)
        }
    }

    /// Returns this shape shrunk by `inset` points inside `frame`, which is how a
    /// non-rectangular cell takes a border.
    ///
    /// `.rectangle` and `.ellipse` return `self` unchanged: both are defined by
    /// the frame itself, so the layout engine insets their frame instead. Vertex
    /// shapes cannot do that — shrinking the bounding box of a triangle moves its
    /// edges by different amounts — so each edge is offset inward along its own
    /// normal and the new vertices are the intersections of adjacent offset edges.
    ///
    /// Scaling the points about the centroid would be simpler but is not a true
    /// inset: it moves each vertex proportionally to its distance from the centre,
    /// so on a 4:1 frame a 10pt border comes out 10pt on one axis and 2.4pt on the
    /// other. Edge offsetting gives the same gap everywhere, which is what a
    /// border is supposed to mean.
    public func inset(by inset: CGFloat, in frame: CGRect) -> CellClipShape {
        guard inset > 0, frame.width > 0, frame.height > 0 else { return self }

        switch self {
        case .rectangle, .ellipse:
            return self
        case let .polygon(points):
            return .polygon(points: Self.insetPoints(points, by: inset, in: frame))
        case let .custom(points):
            return .custom(points: Self.insetPoints(points, by: inset, in: frame))
        }
    }

    // MARK: - Geometry helpers

    private static func absolute(_ p: CGPoint, in frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX + p.x * frame.width, y: frame.minY + p.y * frame.height)
    }

    private static func normalized(_ p: CGPoint, in frame: CGRect) -> CGPoint {
        CGPoint(x: (p.x - frame.minX) / frame.width, y: (p.y - frame.minY) / frame.height)
    }

    /// Signed area (shoelace). The sign encodes winding order, which decides
    /// which perpendicular of an edge points into the shape.
    private static func signedArea(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 3 else { return 0 }
        var total: CGFloat = 0
        for (index, point) in points.enumerated() {
            let next = points[(index + 1) % points.count]
            total += point.x * next.y - next.x * point.y
        }
        return total / 2
    }

    /// Moves every edge inward by `inset` and rebuilds the vertices as the
    /// intersections of adjacent offset edges. Works in absolute space — doing it
    /// in normalized space would skew the gap on a non-square frame.
    private static func insetPoints(
        _ points: [CGPoint], by inset: CGFloat, in frame: CGRect
    ) -> [CGPoint] {
        guard points.count >= 3 else { return points }

        let absolutePoints = points.map { absolute($0, in: frame) }
        let originalArea = signedArea(absolutePoints)
        guard originalArea != 0 else { return points }
        let winding: CGFloat = originalArea > 0 ? 1 : -1
        let count = absolutePoints.count

        /// Inward-offset copy of the edge `a → b`, as a point plus a direction.
        func offsetEdge(_ a: CGPoint, _ b: CGPoint) -> (point: CGPoint, direction: CGPoint)? {
            let delta = CGPoint(x: b.x - a.x, y: b.y - a.y)
            let length = hypot(delta.x, delta.y)
            guard length > 0 else { return nil }
            let direction = CGPoint(x: delta.x / length, y: delta.y / length)
            let normal = CGPoint(x: -direction.y * winding, y: direction.x * winding)
            return (CGPoint(x: a.x + normal.x * inset, y: a.y + normal.y * inset), direction)
        }

        var result: [CGPoint] = []
        result.reserveCapacity(count)

        for index in 0 ..< count {
            let previous = absolutePoints[(index + count - 1) % count]
            let current = absolutePoints[index]
            let next = absolutePoints[(index + 1) % count]

            guard let incoming = offsetEdge(previous, current),
                  let outgoing = offsetEdge(current, next) else {
                result.append(current)
                continue
            }

            let cross = incoming.direction.x * outgoing.direction.y
                - incoming.direction.y * outgoing.direction.x
            if abs(cross) < 1e-9 {
                // Collinear edges never intersect; the offset point is already
                // the correct vertex.
                result.append(CGPoint(
                    x: incoming.point.x + incoming.direction.x * hypot(current.x - previous.x,
                                                                      current.y - previous.y),
                    y: incoming.point.y + incoming.direction.y * hypot(current.x - previous.x,
                                                                      current.y - previous.y)
                ))
                continue
            }

            let gap = CGPoint(x: outgoing.point.x - incoming.point.x,
                              y: outgoing.point.y - incoming.point.y)
            let t = (gap.x * outgoing.direction.y - gap.y * outgoing.direction.x) / cross
            result.append(CGPoint(
                x: incoming.point.x + incoming.direction.x * t,
                y: incoming.point.y + incoming.direction.y * t
            ))
        }

        // An inset wider than the shape pushes the offset edges past each other,
        // where they re-intersect into a bogus polygon. Note that polygon is not
        // reliably mirrored — for a triangle it comes back with the *same* winding
        // and a far larger area — so a sign check alone misses it. A genuine inset
        // strictly reduces area, which is the dependable test.
        let insetArea = signedArea(result)
        if insetArea == 0
            || (insetArea > 0) != (originalArea > 0)
            || abs(insetArea) >= abs(originalArea) {
            let centre = CGPoint(
                x: absolutePoints.reduce(0) { $0 + $1.x } / CGFloat(count),
                y: absolutePoints.reduce(0) { $0 + $1.y } / CGFloat(count)
            )
            return Array(repeating: normalized(centre, in: frame), count: count)
        }

        return result.map { normalized($0, in: frame) }
    }

    private static func closedPath(_ points: [CGPoint], in frame: CGRect) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }

        path.move(to: absolute(first, in: frame))
        for point in points.dropFirst() {
            path.addLine(to: absolute(point, in: frame))
        }
        path.closeSubpath()
        return path
    }

    /// Closed polygon with each vertex replaced by a quadratic curve of radius
    /// `cornerRadius`, using the vertex itself as the control point.
    ///
    /// Per-vertex radius is capped at half the shorter adjacent edge so two
    /// neighbouring corners can never consume the same edge and cross over.
    private static func roundedClosedPath(
        _ points: [CGPoint], in frame: CGRect, cornerRadius: CGFloat
    ) -> CGPath {
        guard points.count >= 3 else { return closedPath(points, in: frame) }

        let absolutePoints = points.map { absolute($0, in: frame) }
        let path = CGMutablePath()
        var started = false

        for (index, vertex) in absolutePoints.enumerated() {
            let previous = absolutePoints[(index + absolutePoints.count - 1) % absolutePoints.count]
            let next = absolutePoints[(index + 1) % absolutePoints.count]

            let toPrevious = CGPoint(x: previous.x - vertex.x, y: previous.y - vertex.y)
            let toNext = CGPoint(x: next.x - vertex.x, y: next.y - vertex.y)
            let previousLength = hypot(toPrevious.x, toPrevious.y)
            let nextLength = hypot(toNext.x, toNext.y)

            // A repeated point has no direction to round along — emit it as-is.
            guard previousLength > 0, nextLength > 0 else {
                if started { path.addLine(to: vertex) } else { path.move(to: vertex); started = true }
                continue
            }

            let radius = min(cornerRadius, min(previousLength, nextLength) / 2)
            let start = CGPoint(
                x: vertex.x + toPrevious.x / previousLength * radius,
                y: vertex.y + toPrevious.y / previousLength * radius
            )
            let end = CGPoint(
                x: vertex.x + toNext.x / nextLength * radius,
                y: vertex.y + toNext.y / nextLength * radius
            )

            if started {
                path.addLine(to: start)
            } else {
                path.move(to: start)
                started = true
            }
            path.addQuadCurve(to: end, control: vertex)
        }

        path.closeSubpath()
        return path
    }
}
