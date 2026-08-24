//
//  PolygonTemplate.swift
//  Caroullage
//
//  Step 02 — non-rectangular collage layouts. The polygon counterpart to
//  `GridTemplate`: each case yields a set of normalized cells, where every cell
//  is a bounding rect (in the unit square) plus a `CellClipShape` describing its
//  boundary within that rect. `CollageLayoutEngine.polygonLayout(...)` scales
//  these to canvas pixels.
//
//  Two families:
//   • Tiling layouts (diagonals, triangle fans) — cells partition the canvas with
//     no gaps and no overlap.
//   • Overlay layouts (circles, arrows) — one or more shape cells sit on top of a
//     background-fill cell; later cells render above earlier ones. The visible
//     background between shapes is the intended collage look, not a seam.
//

import CoreGraphics

/// Shorthand for a normalized unit-square point.
private func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

/// One cell of a polygon template, normalized to the unit square.
public struct PolyCell: Equatable, Sendable {
    /// Bounding box of the cell in the 0…1 unit square.
    public let rect: CGRect
    /// Boundary within `rect`, normalized 0…1.
    public let clip: CellClipShape

    public init(rect: CGRect, clip: CellClipShape) {
        self.rect = rect
        self.clip = clip
    }
}

public enum PolygonTemplate: String, Codable, Sendable, CaseIterable {
    case diagonalLeft
    case diagonalRight
    case triangleTop
    case triangleCenter
    case hexagonGrid
    case circleCenter
    case doubleCircle
    case arrowLeft
    case arrowRight

    public var cellCount: Int { normalizedCells.count }

    public var displayName: String {
        switch self {
        case .diagonalLeft: return "Diag ↘"
        case .diagonalRight: return "Diag ↙"
        case .triangleTop: return "Peak"
        case .triangleCenter: return "Fan"
        case .hexagonGrid: return "Hive"
        case .circleCenter: return "Halo"
        case .doubleCircle: return "Duo"
        case .arrowLeft: return "Arrow ◀"
        case .arrowRight: return "Arrow ▶"
        }
    }

    /// SF Symbol name shown on the shape picker thumbnail.
    public var symbolName: String {
        switch self {
        case .diagonalLeft, .diagonalRight: return "line.diagonal"
        case .triangleTop: return "triangle"
        case .triangleCenter: return "triangle.righthalf.filled"
        case .hexagonGrid: return "hexagon"
        case .circleCenter: return "circle.circle"
        case .doubleCircle: return "circle.grid.2x1"
        case .arrowLeft: return "arrowtriangle.left"
        case .arrowRight: return "arrowtriangle.right"
        }
    }

    private static let unitSquare = CGRect(x: 0, y: 0, width: 1, height: 1)

    public var normalizedCells: [PolyCell] {
        switch self {
        case .diagonalLeft:
            // Split by the line top-left → bottom-right into two triangles.
            return [
                PolyCell(rect: Self.unitSquare, clip: .polygon(points: [p(0, 0), p(1, 0), p(1, 1)])),
                PolyCell(rect: Self.unitSquare, clip: .polygon(points: [p(0, 0), p(1, 1), p(0, 1)])),
            ]

        case .diagonalRight:
            // Split by the line top-right → bottom-left.
            return [
                PolyCell(rect: Self.unitSquare, clip: .polygon(points: [p(0, 0), p(1, 0), p(0, 1)])),
                PolyCell(rect: Self.unitSquare, clip: .polygon(points: [p(1, 0), p(1, 1), p(0, 1)])),
            ]

        case .triangleTop:
            // A centred top triangle over a pentagon fill — tiles exactly.
            return [
                PolyCell(rect: Self.unitSquare, clip: .polygon(points: [p(0, 0), p(1, 0), p(0.5, 0.5)])),
                PolyCell(
                    rect: Self.unitSquare,
                    clip: .polygon(points: [p(0, 0), p(0.5, 0.5), p(1, 0), p(1, 1), p(0, 1)])
                ),
            ]

        case .triangleCenter:
            // Four triangles fanning from the centre to each edge — tiles exactly.
            let c = p(0.5, 0.5)
            return [
                PolyCell(rect: Self.unitSquare, clip: .polygon(points: [p(0, 0), p(1, 0), c])),
                PolyCell(rect: Self.unitSquare, clip: .polygon(points: [p(1, 0), p(1, 1), c])),
                PolyCell(rect: Self.unitSquare, clip: .polygon(points: [p(1, 1), p(0, 1), c])),
                PolyCell(rect: Self.unitSquare, clip: .polygon(points: [p(0, 1), p(0, 0), c])),
            ]

        case .hexagonGrid:
            return Self.honeycomb()

        case .circleCenter:
            // Four quadrant photos with a fifth circular photo overlapping centre.
            let q = 0.5
            return [
                PolyCell(rect: CGRect(x: 0, y: 0, width: q, height: q), clip: .rectangle),
                PolyCell(rect: CGRect(x: q, y: 0, width: q, height: q), clip: .rectangle),
                PolyCell(rect: CGRect(x: 0, y: q, width: q, height: q), clip: .rectangle),
                PolyCell(rect: CGRect(x: q, y: q, width: q, height: q), clip: .rectangle),
                PolyCell(rect: CGRect(x: 0.26, y: 0.26, width: 0.48, height: 0.48), clip: .ellipse),
            ]

        case .doubleCircle:
            // A background photo with two circular photos side by side on top.
            let r = 0.22
            return [
                PolyCell(rect: Self.unitSquare, clip: .rectangle),
                PolyCell(rect: CGRect(x: 0.30 - r, y: 0.5 - r, width: 2 * r, height: 2 * r), clip: .ellipse),
                PolyCell(rect: CGRect(x: 0.70 - r, y: 0.5 - r, width: 2 * r, height: 2 * r), clip: .ellipse),
            ]

        case .arrowLeft:
            return [
                PolyCell(rect: Self.unitSquare, clip: .rectangle),
                PolyCell(rect: Self.unitSquare, clip: .polygon(points: Self.arrow(pointingLeft: true))),
            ]

        case .arrowRight:
            return [
                PolyCell(rect: Self.unitSquare, clip: .rectangle),
                PolyCell(rect: Self.unitSquare, clip: .polygon(points: Self.arrow(pointingLeft: false))),
            ]
        }
    }

    // MARK: - Geometry helpers

    /// A left- or right-pointing arrow, normalized to the unit square.
    private static func arrow(pointingLeft: Bool) -> [CGPoint] {
        // Right-pointing arrow; mirrored horizontally when `pointingLeft`.
        let pts: [CGPoint] = [
            CGPoint(x: 0.15, y: 0.35), CGPoint(x: 0.55, y: 0.35),
            CGPoint(x: 0.55, y: 0.15), CGPoint(x: 0.90, y: 0.50),
            CGPoint(x: 0.55, y: 0.85), CGPoint(x: 0.55, y: 0.65),
            CGPoint(x: 0.15, y: 0.65),
        ]
        return pointingLeft ? pts.map { CGPoint(x: 1 - $0.x, y: $0.y) } : pts
    }

    /// Seven pointy-top hexagons — one centre plus a ring of six — sized so
    /// neighbours meet edge-to-edge (the classic honeycomb collage look).
    private static func honeycomb() -> [PolyCell] {
        let radius: CGFloat = 0.17            // circumradius (centre → vertex)
        let ringDistance = radius * 1.732     // √3·R: honeycomb neighbour spacing
        let center = CGPoint(x: 0.5, y: 0.5)

        var centers = [center]
        for k in 0 ..< 6 {
            let angle = CGFloat.pi / 180 * (30 + 60 * CGFloat(k))
            centers.append(CGPoint(
                x: center.x + ringDistance * cos(angle),
                y: center.y + ringDistance * sin(angle)
            ))
        }

        return centers.map { c in
            let bbox = CGRect(x: c.x - radius, y: c.y - radius, width: 2 * radius, height: 2 * radius)
            // Hexagon vertices normalized within its own bounding box.
            var verts: [CGPoint] = []
            for k in 0 ..< 6 {
                let angle = CGFloat.pi / 180 * (90 + 60 * CGFloat(k)) // pointy-top
                let vx = 0.5 + 0.5 * cos(angle)
                let vy = 0.5 + 0.5 * sin(angle)
                verts.append(CGPoint(x: vx, y: vy))
            }
            return PolyCell(rect: bbox, clip: .polygon(points: verts))
        }
    }
}
