//
//  CanvasPreset.swift
//  ClaudeCollage
//
//  Step 03a — the canvas sizes a user picks before choosing a template. Templates
//  are authored with a normalized `canvasAspectRatio` string ("1:1", "9:16", …);
//  this maps that string to concrete export pixels and drives the gallery's size
//  selector + aspect-ratio filtering.
//
//  Sizing rule: the SHORTER side is normalized to 1080 px (Instagram's baseline),
//  the longer side scales proportionally. So "1:1" → 1080×1080, "4:5" → 1080×1350,
//  "9:16" → 1080×1920, "16:9" → 1920×1080. Freeform carries an explicit size.
//

import CoreGraphics
import Foundation

public enum CanvasPreset: Sendable, Equatable, CaseIterable {
    case square          // 1:1   — Instagram post
    case portrait        // 4:5   — Instagram portrait
    case story           // 9:16  — Stories / Reels / TikTok
    case landscape       // 16:9  — YouTube / X

    /// The canonical aspect string as authored in template JSON.
    public var aspectRatio: String {
        switch self {
        case .square: return "1:1"
        case .portrait: return "4:5"
        case .story: return "9:16"
        case .landscape: return "16:9"
        }
    }

    public var displayName: String {
        switch self {
        case .square: return "Square"
        case .portrait: return "Portrait"
        case .story: return "Story"
        case .landscape: return "Landscape"
        }
    }

    public var size: CGSize { CanvasSize.size(forAspectRatio: aspectRatio) }

    public init?(aspectRatio: String) {
        guard let match = CanvasPreset.allCases.first(where: {
            CanvasSize.normalize($0.aspectRatio) == CanvasSize.normalize(aspectRatio)
        }) else { return nil }
        self = match
    }
}

/// Pure aspect-ratio → pixel-size math, kept free of `CanvasPreset` so the parser
/// and freeform paths can use it directly on arbitrary "w:h" strings.
public enum CanvasSize {

    /// The baseline short-side length, in export pixels.
    public static let baseline: CGFloat = 1080

    /// Maps an aspect string ("w:h") to a concrete pixel size with the shorter
    /// side pinned to `baseline`. Malformed strings fall back to a 1080² square,
    /// so this never produces a zero/negative canvas.
    public static func size(forAspectRatio ratio: String) -> CGSize {
        guard let (w, h) = parse(ratio), w > 0, h > 0 else {
            return CGSize(width: baseline, height: baseline)
        }
        let factor = baseline / CGFloat(min(w, h))
        return CGSize(
            width: (CGFloat(w) * factor).rounded(),
            height: (CGFloat(h) * factor).rounded()
        )
    }

    /// Parses "w:h" (also tolerates "w/h" and whitespace) into a numeric pair.
    static func parse(_ ratio: String) -> (Double, Double)? {
        let parts = ratio
            .split(whereSeparator: { $0 == ":" || $0 == "/" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              let w = Double(parts[0]), let h = Double(parts[1]) else { return nil }
        return (w, h)
    }

    /// The reduced "w:h" aspect for a concrete pixel size (e.g. 1080×1920 → "9:16"),
    /// so it compares equal to a preset's authored ratio via `matchesCanvas`.
    public static func aspectString(for size: CGSize) -> String {
        let w = Int(size.width.rounded()), h = Int(size.height.rounded())
        guard w > 0, h > 0 else { return "1:1" }
        let g = gcd(w, h)
        return "\(w / g):\(h / g)"
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }

    /// A canonical "w:h" form for comparison (e.g. "1.0 : 1" → "1:1").
    static func normalize(_ ratio: String) -> String {
        guard let (w, h) = parse(ratio) else { return ratio }
        func trim(_ v: Double) -> String {
            v == v.rounded() ? String(Int(v)) : String(v)
        }
        return "\(trim(w)):\(trim(h))"
    }
}
