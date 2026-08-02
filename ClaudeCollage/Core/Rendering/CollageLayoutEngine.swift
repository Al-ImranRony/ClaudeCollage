//
//  CollageLayoutEngine.swift
//  ClaudeCollage
//
//  Step 01 — pure geometry for rectangular grid collages.
//  No UIKit, no SwiftUI: given a grid template + canvas size (+ border),
//  returns the absolute-pixel frame of every cell. Trivially unit-testable.
//
//  Polygon shapes and `clipPath` arrive in Step 02.
//

import Foundation
import CoreGraphics

/// The eight rectangular grid layouts shipped in Step 01.
///
/// Each case exposes a set of *normalized* cell rects (origin + size in the
/// 0.0...1.0 unit square). `CollageLayoutEngine` scales these to the canvas
/// and applies the border inset.
public enum GridTemplate: String, Codable, Sendable, CaseIterable {
    case oneCell
    case twoUpHorizontal
    case twoUpVertical
    case threeLeft
    case threeRight
    case fourSquare
    case sixGrid
    case nineGrid

    /// Number of photo cells this layout contains.
    public var cellCount: Int { normalizedCells.count }

    /// Human-facing short name for the layout picker.
    public var displayName: String {
        switch self {
        case .oneCell: return "Single"
        case .twoUpHorizontal: return "2 · Side"
        case .twoUpVertical: return "2 · Stack"
        case .threeLeft: return "3 · Left"
        case .threeRight: return "3 · Right"
        case .fourSquare: return "4 · Grid"
        case .sixGrid: return "6 · Grid"
        case .nineGrid: return "9 · Grid"
        }
    }

    /// Cell rects in the unit square, laid out top-left to bottom-right.
    /// These always exactly tile the unit square (they sum to area 1.0).
    public var normalizedCells: [CGRect] {
        switch self {
        case .oneCell:
            return [CGRect(x: 0, y: 0, width: 1, height: 1)]

        case .twoUpHorizontal:
            return [
                CGRect(x: 0.0, y: 0, width: 0.5, height: 1),
                CGRect(x: 0.5, y: 0, width: 0.5, height: 1),
            ]

        case .twoUpVertical:
            return [
                CGRect(x: 0, y: 0.0, width: 1, height: 0.5),
                CGRect(x: 0, y: 0.5, width: 1, height: 0.5),
            ]

        case .threeLeft:
            // One tall cell on the left, two stacked on the right.
            return [
                CGRect(x: 0.0, y: 0.0, width: 0.5, height: 1.0),
                CGRect(x: 0.5, y: 0.0, width: 0.5, height: 0.5),
                CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
            ]

        case .threeRight:
            // Two stacked on the left, one tall cell on the right.
            return [
                CGRect(x: 0.0, y: 0.0, width: 0.5, height: 0.5),
                CGRect(x: 0.0, y: 0.5, width: 0.5, height: 0.5),
                CGRect(x: 0.5, y: 0.0, width: 0.5, height: 1.0),
            ]

        case .fourSquare:
            return Self.uniformGrid(columns: 2, rows: 2)

        case .sixGrid:
            return Self.uniformGrid(columns: 2, rows: 3)

        case .nineGrid:
            return Self.uniformGrid(columns: 3, rows: 3)
        }
    }

    /// Row-major uniform grid of `columns × rows` equal cells in the unit square.
    private static func uniformGrid(columns: Int, rows: Int) -> [CGRect] {
        let cellWidth = 1.0 / Double(columns)
        let cellHeight = 1.0 / Double(rows)
        var rects: [CGRect] = []
        rects.reserveCapacity(columns * rows)
        for row in 0 ..< rows {
            for column in 0 ..< columns {
                rects.append(
                    CGRect(
                        x: Double(column) * cellWidth,
                        y: Double(row) * cellHeight,
                        width: cellWidth,
                        height: cellHeight
                    )
                )
            }
        }
        return rects
    }
}

/// The resolved, absolute-pixel geometry of a single cell.
///
/// `clipShape` describes the cell boundary parametrically (`.rectangle` for grid
/// cells, a polygon/ellipse for shape cells). The concrete `CGPath` is generated
/// on demand from `(clipShape, frame)`, so this value type stays `Equatable` /
/// `Sendable` / `Codable` without wrapping a non-`Sendable` `CGPath`.
public struct CellFrame: Equatable, Sendable, Identifiable {
    public let id: String
    public let frame: CGRect
    public let shape: CellShape
    public let clipShape: CellClipShape

    public init(
        id: String,
        frame: CGRect,
        shape: CellShape = .rectangle,
        clipShape: CellClipShape = .rectangle
    ) {
        self.id = id
        self.frame = frame
        self.shape = shape
        self.clipShape = clipShape
    }
}

/// A collage layout — either a rectangular grid or a polygon/shape layout.
/// This is the single source of truth the editor state stores; future steps
/// (templates, carousel) extend the family here.
public enum CollageLayout: Equatable, Sendable, Codable {
    case grid(GridTemplate)
    case polygon(PolygonTemplate)
    case template(TemplateLayout)

    public var cellCount: Int {
        switch self {
        case let .grid(template): return template.cellCount
        case let .polygon(template): return template.cellCount
        case let .template(template): return template.cells.count
        }
    }

    public var displayName: String {
        switch self {
        case let .grid(template): return template.displayName
        case let .polygon(template): return template.displayName
        case let .template(template): return template.name
        }
    }

    /// True for polygon/shape layouts (which render edge-to-edge, ignoring the
    /// rectangular border inset that only makes sense for grids).
    public var isPolygon: Bool {
        if case .polygon = self { return true }
        return false
    }

    public var gridTemplate: GridTemplate? {
        if case let .grid(template) = self { return template }
        return nil
    }

    public var polygonTemplate: PolygonTemplate? {
        if case let .polygon(template) = self { return template }
        return nil
    }

    public var templateLayout: TemplateLayout? {
        if case let .template(template) = self { return template }
        return nil
    }

    /// False for `.template` layouts, whose geometry comes from the template
    /// itself — there is no Grid/Shapes alternative to offer, so the editor
    /// hides its whole Layout section rather than highlighting a layout the
    /// document does not actually use.
    public var offersLayoutAlternatives: Bool {
        if case .template = self { return false }
        return true
    }

    /// Stable identifier for persistence (`CollageProject.templateID`).
    public var persistID: String {
        switch self {
        case let .grid(template): return "grid.\(template.rawValue)"
        case let .polygon(template): return "polygon.\(template.rawValue)"
        case let .template(template): return "template.\(template.templateID)"
        }
    }
}

/// Pure geometry engine. Stateless — every method is a deterministic function
/// of its inputs, which makes it the ideal first unit-testing target (Step 01).
public struct CollageLayoutEngine: Sendable {

    public init() {}

    /// Resolves a grid template into absolute-pixel cell frames.
    ///
    /// - Parameters:
    ///   - template: which of the eight grid layouts to compute.
    ///   - canvasSize: the target canvas in pixels.
    ///   - borderWidth: gap between cells, in points. Each cell is inset by
    ///     `borderWidth / 2` on every edge, so the visible gap between two
    ///     adjacent cells equals `borderWidth`, and the outer margin equals
    ///     `borderWidth / 2`. A cell whose size would go negative is clamped
    ///     to zero (never negative).
    public func layout(
        for template: GridTemplate,
        canvasSize: CGSize,
        borderWidth: CGFloat = 0
    ) -> [CellFrame] {
        let inset = max(0, borderWidth) / 2

        return template.normalizedCells.enumerated().map { index, normalized in
            let scaled = CGRect(
                x: normalized.minX * canvasSize.width,
                y: normalized.minY * canvasSize.height,
                width: normalized.width * canvasSize.width,
                height: normalized.height * canvasSize.height
            )
            let insetRect = scaled.insetBy(dx: inset, dy: inset)
            // Clamp so a border wider than the cell never yields a negative frame.
            let clamped = CGRect(
                x: insetRect.origin.x,
                y: insetRect.origin.y,
                width: max(0, insetRect.width),
                height: max(0, insetRect.height)
            )
            return CellFrame(
                id: "\(template.rawValue)-\(index)",
                frame: clamped,
                shape: .rectangle,
                clipShape: .rectangle
            )
        }
    }

    /// Resolves any `CollageLayout` (grid or polygon) into absolute-pixel cells.
    public func layout(
        for layout: CollageLayout,
        canvasSize: CGSize,
        borderWidth: CGFloat = 0
    ) -> [CellFrame] {
        switch layout {
        case let .grid(template):
            return self.layout(for: template, canvasSize: canvasSize, borderWidth: borderWidth)
        case let .polygon(template):
            return polygonLayout(for: template, canvasSize: canvasSize, borderWidth: borderWidth)
        case let .template(template):
            return templateLayout(for: template, canvasSize: canvasSize, borderWidth: borderWidth)
        }
    }

    /// Resolves a standard template's photo cells into absolute-pixel frames.
    ///
    /// Templates are authored edge-to-edge; the user's border slider provides the
    /// gap. Rectangular and elliptical cells inset their frame, vertex-defined
    /// cells shrink their boundary about its centroid — the same split as
    /// `polygonLayout`.
    public func templateLayout(
        for template: TemplateLayout,
        canvasSize: CGSize,
        borderWidth: CGFloat = 0
    ) -> [CellFrame] {
        let inset = max(0, borderWidth) / 2

        return template.cells.enumerated().map { index, cell in
            let scaled = CGRect(
                x: cell.frame.minX * canvasSize.width,
                y: cell.frame.minY * canvasSize.height,
                width: cell.frame.width * canvasSize.width,
                height: cell.frame.height * canvasSize.height
            )
            let insetsFrame = cell.clip.isRectangle || cell.clip == .ellipse
            let insetRect = insetsFrame ? scaled.insetBy(dx: inset, dy: inset) : scaled
            let clamped = CGRect(
                x: insetRect.origin.x,
                y: insetRect.origin.y,
                width: max(0, insetRect.width),
                height: max(0, insetRect.height)
            )
            return CellFrame(
                id: "\(template.templateID)-\(index)",
                frame: clamped,
                shape: shapeTag(for: cell.clip),
                clipShape: cell.clip.inset(by: inset, in: scaled)
            )
        }
    }

    /// Resolves a polygon template into absolute-pixel cell frames + clip shapes.
    ///
    /// Each cell's `frame` is its bounding box in canvas pixels; `clipShape`
    /// carries the boundary, still normalized within that box, ready to become a
    /// `CGPath` at render time.
    ///
    /// - Parameter borderWidth: same convention as the grid path — each cell
    ///   pulls in by `borderWidth / 2`, so the gap between two adjacent cells is
    ///   `borderWidth`. Vertex shapes shrink their boundary about their centroid
    ///   rather than their bounding box, since insetting the box of a triangle
    ///   would move its edges by unequal amounts; ellipses inset the box, which
    ///   for them is equivalent.
    public func polygonLayout(
        for template: PolygonTemplate,
        canvasSize: CGSize,
        borderWidth: CGFloat = 0
    ) -> [CellFrame] {
        let inset = max(0, borderWidth) / 2

        return template.normalizedCells.enumerated().map { index, cell in
            let frame = CGRect(
                x: cell.rect.minX * canvasSize.width,
                y: cell.rect.minY * canvasSize.height,
                width: cell.rect.width * canvasSize.width,
                height: cell.rect.height * canvasSize.height
            )
            // Ellipses are defined by the frame, so they inset it; vertex shapes
            // keep the frame (the image still fills it) and shrink the boundary.
            let insetFrame: CGRect
            if case .ellipse = cell.clip {
                let shrunk = frame.insetBy(dx: inset, dy: inset)
                insetFrame = CGRect(x: shrunk.origin.x, y: shrunk.origin.y,
                                    width: max(0, shrunk.width), height: max(0, shrunk.height))
            } else {
                insetFrame = frame
            }
            return CellFrame(
                id: "\(template.rawValue)-\(index)",
                frame: insetFrame,
                shape: shapeTag(for: cell.clip),
                clipShape: cell.clip.inset(by: inset, in: frame)
            )
        }
    }

    private func shapeTag(for clip: CellClipShape) -> CellShape {
        switch clip {
        case .rectangle: return .rectangle
        case .ellipse: return .circle
        case .polygon: return .triangle
        case .custom: return .custom
        }
    }
}
