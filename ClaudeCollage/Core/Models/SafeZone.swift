//
//  SafeZone.swift
//  ClaudeCollage
//
//  Step 03b slice 6 (refined slice 8 QA) — safe-zone presets for the carousel
//  preview. Each platform overlays chrome (status bar, caption box, action rail)
//  that can hide part of a frame; the preview dims those regions so the user keeps
//  important content clear of them. Preview-only — never composited into an export.
//
//  Why the regions are defined in SCREEN space, not frame space: Story / Reels /
//  TikTok are full-screen 9:16 surfaces. A non-9:16 carousel frame is shown
//  letterboxed + centered on that screen, so the chrome sits at fixed *screen*
//  positions — "the top 9% of the frame" is only right for a 9:16 frame. So each
//  preset lists its regions in 9:16 screen-normalized space, and
//  `coveredRegions(forFrameAspect:)` projects them onto the actual frame, dropping
//  any chrome that lands in the letterbox (outside the image). Result: the bands sit
//  where the platform UI truly is for every aspect, and wider feed frames correctly
//  show less (or none) of the full-screen chrome.
//

import CoreGraphics

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

    /// Regions the platform UI covers, in **9:16 screen-normalized** space (0…1).
    /// Values follow each app's published full-screen safe areas.
    public var screenRegions: [CGRect] {
        switch self {
        case .none:
            return []
        case .instagramStory:
            // Profile + close row up top; "Send message" reply bar along the bottom.
            return [
                CGRect(x: 0, y: 0, width: 1, height: 0.11),
                CGRect(x: 0, y: 0.87, width: 1, height: 0.13),
            ]
        case .instagramReels:
            // Right action rail (like / comment / share / audio) + a bottom band for
            // the caption, handle, and audio ticker.
            return [
                CGRect(x: 0.84, y: 0.40, width: 0.16, height: 0.48),
                CGRect(x: 0, y: 0.82, width: 0.84, height: 0.18),
            ]
        case .tiktok:
            // Similar to Reels but a taller right rail and a slightly taller caption.
            return [
                CGRect(x: 0.86, y: 0.34, width: 0.14, height: 0.52),
                CGRect(x: 0, y: 0.80, width: 0.86, height: 0.20),
            ]
        case .generic:
            // Conservative top + bottom bars covering most short-form platforms.
            return [
                CGRect(x: 0, y: 0, width: 1, height: 0.09),
                CGRect(x: 0, y: 0.90, width: 1, height: 0.10),
            ]
        }
    }

    /// The screen regions projected onto a frame of the given aspect (width / height),
    /// as it appears aspect-fit + centered on the 9:16 screen. Regions that fall in the
    /// letterbox (outside the frame) are dropped; partly-covered regions are clipped.
    public func coveredRegions(forFrameAspect aspect: CGFloat) -> [CGRect] {
        let regions = screenRegions
        guard aspect > 0, !regions.isEmpty else { return regions }

        if aspect >= Self.screenAspect {
            // Frame is wider than the screen → fit by width, vertical letterbox.
            let frameHeight = Self.screenAspect / aspect          // fraction of screen height
            let top = (1 - frameHeight) / 2
            return regions.compactMap { region in
                let y0 = max(region.minY, top)
                let y1 = min(region.maxY, top + frameHeight)
                guard y1 > y0 else { return nil }                 // entirely in the letterbox
                return CGRect(x: region.minX, y: (y0 - top) / frameHeight,
                              width: region.width, height: (y1 - y0) / frameHeight)
            }
        } else {
            // Frame is taller than the screen → fit by height, horizontal pillarbox.
            let frameWidth = aspect / Self.screenAspect           // fraction of screen width
            let left = (1 - frameWidth) / 2
            return regions.compactMap { region in
                let x0 = max(region.minX, left)
                let x1 = min(region.maxX, left + frameWidth)
                guard x1 > x0 else { return nil }
                return CGRect(x: (x0 - left) / frameWidth, y: region.minY,
                              width: (x1 - x0) / frameWidth, height: region.height)
            }
        }
    }
}
