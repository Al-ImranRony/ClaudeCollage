//
//  SafeZone.swift
//  ClaudeCollage
//
//  Step 03b slice 6 — safe-zone presets for the carousel preview. Each platform
//  overlays chrome (status bar, caption box, action rail) that can hide part of a
//  frame; these presets dim those regions in the preview so the user keeps important
//  content clear of them. Regions are normalized (0…1) in canvas space and are
//  PREVIEW-ONLY — never composited into an export.
//

import CoreGraphics

public enum SafeZonePreset: String, CaseIterable, Sendable {
    case none
    case instagramStory
    case instagramReels
    case tiktok
    case generic

    public var displayName: String {
        switch self {
        case .none:            return "Off"
        case .instagramStory:  return "IG Story"
        case .instagramReels:  return "IG Reels"
        case .tiktok:          return "TikTok"
        case .generic:         return "Generic"
        }
    }

    /// Normalized rects (canvas space) the platform UI is likely to cover. Dimmed in
    /// the preview; empty for `.none`.
    public var coveredRegions: [CGRect] {
        switch self {
        case .none:
            return []
        case .instagramStory:
            // Profile row up top; reply/react bar along the bottom.
            return [
                CGRect(x: 0, y: 0, width: 1, height: 0.09),
                CGRect(x: 0, y: 0.88, width: 1, height: 0.12),
            ]
        case .instagramReels:
            // Right-hand action rail + caption band at the bottom.
            return [
                CGRect(x: 0.84, y: 0.42, width: 0.16, height: 0.44),
                CGRect(x: 0, y: 0.80, width: 0.84, height: 0.20),
            ]
        case .tiktok:
            // Similar to Reels, with a slightly taller action rail.
            return [
                CGRect(x: 0.85, y: 0.34, width: 0.15, height: 0.52),
                CGRect(x: 0, y: 0.82, width: 0.85, height: 0.18),
            ]
        case .generic:
            // Conservative thin top + bottom bands.
            return [
                CGRect(x: 0, y: 0, width: 1, height: 0.06),
                CGRect(x: 0, y: 0.90, width: 1, height: 0.10),
            ]
        }
    }
}
