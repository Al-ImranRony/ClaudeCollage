//
//  CollageBackground.swift
//  Caroullage
//
//  The canvas background: what shows behind the cells and through the gaps.
//
//  Persistence: synthesized `Codable` for an enum keys each case by name
//  (`{"solid":{"hex":"#FFFFFF"}}`), so adding cases leaves every saved solid
//  background decoding exactly as before. Never rename a case or a label — the
//  names ARE the stored format.
//
//  Drawing lives in `BackgroundRendering`, shared by the live canvas and the
//  export compositor so the preview and the file cannot disagree.
//

import Foundation

/// A repeating geometric motif, drawn as vector tiles (so it stays sharp at
/// export resolution) in two colours.
public enum BackgroundPattern: String, Codable, Sendable, CaseIterable {
    case dots, grid, stripes, gingham, checker, waves, hearts
}

public enum CollageBackground: Equatable, Sendable, Codable {
    case solid(hex: String)
    /// A linear gradient across the whole canvas. `angle` is in degrees: 0 runs
    /// top → bottom, 90 runs left → right.
    case gradient(colors: [String], angle: Double)
    /// `ink` draws the motif over a `paper` fill.
    case pattern(BackgroundPattern, ink: String, paper: String)
    /// The collage's first photo, scaled to fill and blurred, darkened by `dim`
    /// (0…1). The photo is resolved at render time, so swapping that photo
    /// re-dresses the background with it.
    case photoBlur(dim: Double)

    public static let white = CollageBackground.solid(hex: "#FFFFFF")
    public static let black = CollageBackground.solid(hex: "#000000")

    /// The solid swatches offered in the background picker.
    public static let palette: [CollageBackground] = [
        .solid(hex: "#FFFFFF"),
        .solid(hex: "#000000"),
        .solid(hex: "#F2F2F7"),
        .solid(hex: "#1C1C1E"),
        .solid(hex: "#FFE5EC"),
        .solid(hex: "#E5F1FF"),
        .solid(hex: "#E8F5E9"),
        .solid(hex: "#FFF8E1"),
        .solid(hex: "#EDE7F6"),
        .solid(hex: "#FBE9E7"),
    ]

    /// One colour that stands for the background — its fill where it has one,
    /// else the colour it mostly reads as. Used where a single colour is needed:
    /// the canvas fill under a drawn background, and judging whether new text
    /// should default to dark or light ink.
    public var hex: String {
        switch self {
        case let .solid(hex): return hex
        case let .gradient(colors, _): return colors.first ?? "#FFFFFF"
        case let .pattern(_, _, paper): return paper
        case .photoBlur: return "#3A3A3C"
        }
    }

    public var isSolid: Bool {
        if case .solid = self { return true }
        return false
    }

    public var isPhotoBlur: Bool {
        if case .photoBlur = self { return true }
        return false
    }
}

/// One entry in the background picker: the background and whether it is a
/// Premium unlock.
public struct BackgroundOption: Equatable, Sendable {
    public let background: CollageBackground
    public let name: String
    public let isPremium: Bool

    /// Blur first: it is built from the user's own photo, so it is the one that
    /// always suits the collage. Both blur options are free — it is the hook.
    public static let blurs: [BackgroundOption] = [
        BackgroundOption(background: .photoBlur(dim: 0), name: String(localized: "Blur"), isPremium: false),
        BackgroundOption(background: .photoBlur(dim: 0.35), name: String(localized: "Blur Dark"), isPremium: false),
    ]

    /// 12 gradients; the first three are free.
    public static let gradients: [BackgroundOption] = [
        g(["#FFDEE9", "#B5FFFC"], 0, "Cotton", free: true),
        g(["#FBC2EB", "#A6C1EE"], 45, "Lilac", free: true),
        g(["#FDFCFB", "#E2D1C3"], 0, "Linen", free: true),
        g(["#FF9A8B", "#FF6A88", "#FF99AC"], 45, "Sunset"),
        g(["#A1C4FD", "#C2E9FB"], 0, "Sky"),
        g(["#D4FC79", "#96E6A1"], 45, "Lime"),
        g(["#F6D365", "#FDA085"], 0, "Peach"),
        g(["#84FAB0", "#8FD3F4"], 90, "Lagoon"),
        g(["#E0C3FC", "#8EC5FC"], 135, "Dream"),
        g(["#30CFD0", "#330867"], 0, "Deep Sea"),
        g(["#434343", "#000000"], 0, "Graphite"),
        g(["#0F2027", "#203A43", "#2C5364"], 45, "Midnight"),
    ]

    /// 8 patterns; polka dots are free.
    public static let patterns: [BackgroundOption] = [
        p(.dots, "#F4A7B9", "#FFF5F7", "Polka", free: true),
        p(.grid, "#C9D6E8", "#FFFFFF", "Graph"),
        p(.stripes, "#FFD7A8", "#FFF8EE", "Stripes"),
        p(.gingham, "#E57373", "#FFFFFF", "Gingham"),
        p(.checker, "#1C1C1E", "#F2F2F7", "Checker"),
        p(.waves, "#90CAF9", "#F3F9FF", "Waves"),
        p(.hearts, "#FF6F91", "#FFE5EC", "Hearts"),
        p(.dots, "#FFFFFF", "#1C1C1E", "Night Dots"),
    ]

    private static func g(_ colors: [String], _ angle: Double, _ name: String.LocalizationValue,
                          free: Bool = false) -> BackgroundOption {
        BackgroundOption(background: .gradient(colors: colors, angle: angle),
                         name: String(localized: name), isPremium: !free)
    }

    private static func p(_ kind: BackgroundPattern, _ ink: String, _ paper: String,
                          _ name: String.LocalizationValue, free: Bool = false) -> BackgroundOption {
        BackgroundOption(background: .pattern(kind, ink: ink, paper: paper),
                         name: String(localized: name), isPremium: !free)
    }
}
