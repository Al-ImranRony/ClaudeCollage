//
//  SafeZone.swift
//  ClaudeCollage
//
//  Step 03b slice 6 (refined for QA) — safe-zone presets for the carousel preview.
//  Each platform overlays chrome (status bar, caption box, action rail) that can
//  hide part of a frame; the preview dims + labels those regions so the user keeps
//  important content clear of them. Preview-only — never composited into an export.
//
//  Two design points:
//   • Regions are authored in 9:16 SCREEN space (Story/Reels/TikTok are full-screen
//     9:16 surfaces). A non-9:16 frame shows letterboxed + centered there, so
//     `coveredZones(forFrameAspect:)` projects each zone onto the frame's real aspect
//     and drops chrome that lands in the letterbox — the bands then sit where the UI
//     truly is for every aspect.
//   • Each zone carries a LABEL ("Caption", "Actions", …) so the dimmed area reads as
//     an intentional platform-UI region, not a stray rectangle.
//

import CoreGraphics

/// One region a platform's UI covers, plus what sits there.
public struct SafeZoneRegion: Equatable, Sendable {
    public let rect: CGRect          // normalized (0…1)
    public let label: String

    public init(rect: CGRect, label: String) {
        self.rect = rect
        self.label = label
    }
}

public enum SafeZonePreset: String, CaseIterable, Sendable {
    case none
    case instagramStory
    case instagramReels
    case tiktok
    case generic

    /// The reference surface these presets describe: a 9:16 phone screen.
    private static let screenAspect: CGFloat = 9.0 / 16.0

    public var displayName: String {
        switch self {
        case .none:            return "Off"
        case .instagramStory:  return "IG Story"
        case .instagramReels:  return "IG Reels"
        case .tiktok:          return "TikTok"
        case .generic:         return "Generic"
        }
    }

    /// The UI zones this platform overlays, in 9:16 screen-normalized space. Values
    /// follow each app's published full-screen safe areas (1080×1920 reference).
    public var screenZones: [SafeZoneRegion] {
        switch self {
        case .none:
            return []
        case .instagramStory:
            // ~250px top (profile + close) and ~250px bottom (reply bar) on 1920.
            return [
                SafeZoneRegion(rect: CGRect(x: 0, y: 0, width: 1, height: 0.13), label: "Profile"),
                SafeZoneRegion(rect: CGRect(x: 0, y: 0.87, width: 1, height: 0.13), label: "Reply bar"),
            ]
        case .instagramReels:
            // ~220px right action rail; ~420px bottom (caption + audio + CTA). The
            // caption band stops at the rail so the two tile into a clean L.
            return [
                SafeZoneRegion(rect: CGRect(x: 0.80, y: 0.42, width: 0.20, height: 0.46), label: "Actions"),
                SafeZoneRegion(rect: CGRect(x: 0, y: 0.78, width: 0.80, height: 0.22), label: "Caption"),
            ]
        case .tiktok:
            // ~120px right rail (taller icon stack); ~483px bottom (username + caption).
            return [
                SafeZoneRegion(rect: CGRect(x: 0.85, y: 0.38, width: 0.15, height: 0.50), label: "Actions"),
                SafeZoneRegion(rect: CGRect(x: 0, y: 0.75, width: 0.85, height: 0.25), label: "Caption"),
            ]
        case .generic:
            // Conservative top + bottom bars covering most short-form platforms.
            return [
                SafeZoneRegion(rect: CGRect(x: 0, y: 0, width: 1, height: 0.10), label: "Top UI"),
                SafeZoneRegion(rect: CGRect(x: 0, y: 0.87, width: 1, height: 0.13), label: "Bottom UI"),
            ]
        }
    }

    /// The screen zones projected onto a frame of the given aspect (width / height) as
    /// it appears aspect-fit + centered on the 9:16 screen. Zones fully in the
    /// letterbox are dropped; partly-covered zones are clipped to the frame.
    public func coveredZones(forFrameAspect aspect: CGFloat) -> [SafeZoneRegion] {
        let zones = screenZones
        guard aspect > 0, !zones.isEmpty else { return zones }
        return zones.compactMap { zone in
            guard let rect = Self.project(zone.rect, ontoFrameAspect: aspect) else { return nil }
            return SafeZoneRegion(rect: rect, label: zone.label)
        }
    }

    /// Convenience — just the projected rectangles (used by geometry tests).
    public func coveredRegions(forFrameAspect aspect: CGFloat) -> [CGRect] {
        coveredZones(forFrameAspect: aspect).map(\.rect)
    }

    /// Maps a screen-space rect onto a frame of `aspect`, or nil if it lands wholly in
    /// the letterbox/pillarbox.
    private static func project(_ region: CGRect, ontoFrameAspect aspect: CGFloat) -> CGRect? {
        if aspect >= screenAspect {
            // Frame wider than screen → fit by width, vertical letterbox.
            let frameHeight = screenAspect / aspect
            let top = (1 - frameHeight) / 2
            let y0 = max(region.minY, top)
            let y1 = min(region.maxY, top + frameHeight)
            guard y1 > y0 else { return nil }
            return CGRect(x: region.minX, y: (y0 - top) / frameHeight,
                          width: region.width, height: (y1 - y0) / frameHeight)
        } else {
            // Frame taller than screen → fit by height, horizontal pillarbox.
            let frameWidth = aspect / screenAspect
            let left = (1 - frameWidth) / 2
            let x0 = max(region.minX, left)
            let x1 = min(region.maxX, left + frameWidth)
            guard x1 > x0 else { return nil }
            return CGRect(x: (x0 - left) / frameWidth, y: region.minY,
                          width: (x1 - x0) / frameWidth, height: region.height)
        }
    }
}
