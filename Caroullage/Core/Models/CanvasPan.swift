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

    /// How fast the camera glides.
    public enum Glide: String, CaseIterable, Sendable {
        /// One pass, start to end, over the whole video — so the speed follows
        /// the clips' length. The default, and every pan saved before glides.
        case wholeVideo
        case slow, medium, fast

        /// Frames per second, or nil for `wholeVideo`. `fast` is the pace of the
        /// travel reference (~0.56 frames/s).
        public var speed: Double? {
            switch self {
            case .wholeVideo: nil
            case .slow: 0.2
            case .medium: 0.35
            case .fast: 0.55
            }
        }

        public var displayName: String {
            switch self {
            // "Once": one pass across the video. Short enough to sit in a
            // four-segment control without truncating.
            case .wholeVideo: String(localized: "Once")
            case .slow: String(localized: "Slow")
            case .medium: String(localized: "Medium")
            case .fast: String(localized: "Fast")
            }
        }
    }

    public var axis: Axis
    /// How many frames long the strip is. 1 means no movement; clamped to
    /// `extentRange` so a corrupt value cannot build a 10,000-pixel canvas.
    public var extent: Double
    /// Frames per second when gliding at a fixed pace, sweeping back and forth
    /// along the strip; nil = one pass over the whole video. Clamped positive.
    public var speed: Double?

    public init(axis: Axis = .horizontal, extent: Double = 2.5, speed: Double? = nil) {
        self.axis = axis
        self.extent = Self.clampExtent(extent)
        self.speed = Self.clampSpeed(speed)
    }

    /// The preset this pan's speed corresponds to (a hand-edited speed reads as
    /// the nearest preset).
    public var glide: Glide {
        guard let speed else { return .wholeVideo }
        return Glide.allCases.filter { $0.speed != nil }
            .min { abs(($0.speed ?? 0) - speed) < abs(($1.speed ?? 0) - speed) } ?? .wholeVideo
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
    ///
    /// With a fixed `speed` the camera sweeps start → end → start at that pace
    /// for as long as the video runs, so a long clip keeps the glide lively
    /// instead of crawling one pass across it.
    public func cameraOffset(at time: Double, duration: Double, canvas: CGSize) -> CGPoint {
        cameraOffset(progress: progress(at: time, duration: duration), canvas: canvas)
    }

    /// 0…1 along the strip at `time`.
    public func progress(at time: Double, duration: Double) -> Double {
        guard let leg = legDuration else { return duration > 0 ? time / duration : 0 }
        let phase = max(0, time).truncatingRemainder(dividingBy: 2 * leg)
        return phase <= leg ? phase / leg : 2 - phase / leg
    }

    /// Seconds for one start-to-end pass at `speed`; nil when gliding over the
    /// whole video or when there is nothing to travel.
    public var legDuration: Double? {
        guard let speed, speed > 0, extent > 1 else { return nil }
        return (extent - 1) / speed
    }

    /// Where the camera reverses within `[0, duration]` — the points a linear
    /// ramp between keyframes has to be split at.
    public func turningPoints(duration: Double) -> [Double] {
        guard let leg = legDuration, duration > 0 else { return [] }
        return stride(from: leg, to: duration, by: leg).map { $0 }
    }

    private static func clampExtent(_ value: Double) -> Double {
        guard value.isFinite else { return extentRange.lowerBound }
        return min(extentRange.upperBound, max(extentRange.lowerBound, value))
    }

    private static func clampSpeed(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return min(4, value)
    }

    private enum CodingKeys: String, CodingKey { case axis, extent, speed }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decodeIfPresent(String.self, forKey: .axis)
        self.axis = raw.flatMap(Axis.init(rawValue:)) ?? .horizontal
        self.extent = Self.clampExtent(try c.decodeIfPresent(Double.self, forKey: .extent) ?? 2.5)
        self.speed = Self.clampSpeed(try c.decodeIfPresent(Double.self, forKey: .speed))
    }
}
