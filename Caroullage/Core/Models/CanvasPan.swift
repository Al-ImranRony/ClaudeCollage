//
//  CanvasPan.swift
//  Caroullage
//
//  A camera move across a video collage laid out on a strip LONGER than the
//  frame — the travel "filmstrip" look, where clips of different widths sit side
//  by side and the view glides along them for the length of the video.
//
//  The strip is `extent` frames long along `axis`. Everything on it — cells,
//  captions, stickers — is laid out in STRIP space by the ordinary layout
//  engine and renderers; the only new thing is the offset the frame is viewed
//  at, which moves linearly from the strip's start to its end across the whole
//  composition. One function (`cameraOffset`) decides that offset, and the
//  composition builder, the export's overlay pass and the live canvas all call it.
//

import CoreGraphics
import Foundation

public struct CanvasPan: Codable, Equatable, Sendable {

    public enum Axis: String, Codable, Sendable, CaseIterable {
        /// The strip runs left → right; the camera travels right.
        case horizontal
        /// The strip runs top → bottom; the camera travels down.
        case vertical
    }

    public static let extentRange: ClosedRange<Double> = 1 ... 4

    public var axis: Axis
    /// How many frames long the strip is. 1 means no movement; clamped to
    /// `extentRange` so a corrupt value cannot build a 10,000-pixel canvas.
    public var extent: Double

    public init(axis: Axis = .horizontal, extent: Double = 2.5) {
        self.axis = axis
        self.extent = Self.clampExtent(extent)
    }

    /// The strip's size in the same units as `canvas` (the frame).
    public func stripSize(for canvas: CGSize) -> CGSize {
        switch axis {
        case .horizontal: CGSize(width: canvas.width * extent, height: canvas.height)
        case .vertical: CGSize(width: canvas.width, height: canvas.height * extent)
        }
    }

    /// Where the frame's top-left sits on the strip at `progress` (0 = the
    /// strip's start, 1 = its end), in the units of `canvas`. Linear: the
    /// references glide at a constant speed, and an ease would read as the
    /// footage itself slowing down.
    public func cameraOffset(progress: Double, canvas: CGSize) -> CGPoint {
        let p = CGFloat(min(1, max(0, progress.isFinite ? progress : 0)))
        let travel = CGFloat(extent - 1) * p
        switch axis {
        case .horizontal: return CGPoint(x: canvas.width * travel, y: 0)
        case .vertical: return CGPoint(x: 0, y: canvas.height * travel)
        }
    }

    /// The camera offset at a composition time, for a composition `duration`
    /// seconds long. A zero-length composition holds the start.
    public func cameraOffset(at time: Double, duration: Double, canvas: CGSize) -> CGPoint {
        cameraOffset(progress: duration > 0 ? time / duration : 0, canvas: canvas)
    }

    private static func clampExtent(_ value: Double) -> Double {
        guard value.isFinite else { return extentRange.lowerBound }
        return min(extentRange.upperBound, max(extentRange.lowerBound, value))
    }

    private enum CodingKeys: String, CodingKey { case axis, extent }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decodeIfPresent(String.self, forKey: .axis)
        self.axis = raw.flatMap(Axis.init(rawValue:)) ?? .horizontal
        self.extent = Self.clampExtent(try c.decodeIfPresent(Double.self, forKey: .extent) ?? 2.5)
    }
}
