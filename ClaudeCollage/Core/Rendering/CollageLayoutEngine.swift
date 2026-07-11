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
/// `shape` is always `.rectangle` in Step 01. `clipPath` (for polygon cells)
/// is introduced in Step 02, so it is intentionally absent here to keep the
/// value type `Equatable`/`Sendable` without wrapping a non-`Sendable` `CGPath`.
public struct CellFrame: Equatable, Sendable, Identifiable {
    public let id: String
    public let frame: CGRect
    public let shape: CellShape

    public init(id: String, frame: CGRect, shape: CellShape = .rectangle) {
        self.id = id
        self.frame = frame
        self.shape = shape
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
                shape: .rectangle
            )
        }
    }
}
