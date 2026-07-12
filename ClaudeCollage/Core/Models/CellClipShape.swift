//
//  CellClipShape.swift
//  ClaudeCollage
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
    /// - Parameter cornerRadius: applied only to `.rectangle`.
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
            return Self.closedPath(points, in: frame)
        }
    }

    private static func closedPath(_ points: [CGPoint], in frame: CGRect) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }

        func absolute(_ p: CGPoint) -> CGPoint {
            CGPoint(x: frame.minX + p.x * frame.width, y: frame.minY + p.y * frame.height)
        }

        path.move(to: absolute(first))
        for point in points.dropFirst() {
            path.addLine(to: absolute(point))
        }
        path.closeSubpath()
        return path
    }
}
