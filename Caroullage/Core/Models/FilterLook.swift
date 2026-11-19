//
//  FilterLook.swift
//  Caroullage
//
//  The named filter looks the collage editor offers, grouped into themed packs.
//
//  A look is DATA, not a pipeline: a recipe of the same `CellFilters` values the
//  Adjust sliders drive, plus at most one of Core Image's built-in photo
//  effects. `ImageFilterProcessor` runs the recipe, then blends it over the
//  original at the cell's `lookIntensity`, then applies the user's own
//  adjustments on top — so a look is a starting point, never a lock-in.
//
//  The Essentials looks reuse `CameraFilter.settings` rather than restating
//  them, so a photo shot through "Golden" and a cell filtered "Golden" stay one
//  code path and come out identical.
//
//  Premium split: 10 of 29 looks are free — every Essentials look, plus one
//  each in Film, Portrait and Mood so those packs can be tried before they are
//  sold. B&W has no free look of its own because Essentials' Mono already is one.
//

import Foundation

/// A Core Image built-in photo effect a look may start from.
public enum PhotoEffect: String, Sendable, Equatable, CaseIterable {
    case chrome, fade, instant, mono, noir, process, tonal, transfer

    /// The `CIFilter` name, e.g. `CIPhotoEffectChrome`.
    public var filterName: String { "CIPhotoEffect" + rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// A themed group of looks — the section a look is listed under.
public enum FilterPack: String, Sendable, CaseIterable {
    case essentials, film, portrait, mood, blackAndWhite

    public var title: String {
        switch self {
        case .essentials: return String(localized: "Essentials")
        case .film: return String(localized: "Film")
        case .portrait: return String(localized: "Portrait")
        case .mood: return String(localized: "Mood")
        case .blackAndWhite: return String(localized: "B&W")
        }
    }
}

public struct FilterLook: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let pack: FilterPack
    public let isPremium: Bool
    /// Applied first, when present.
    public let effect: PhotoEffect?
    /// Applied after `effect`. Only the manual fields are read; a recipe never
    /// carries a `lookID` of its own.
    public let adjust: CellFilters

    init(_ id: String, _ name: String, _ pack: FilterPack, premium: Bool,
         effect: PhotoEffect? = nil, _ adjust: CellFilters = CellFilters()) {
        self.id = id
        self.name = name
        self.pack = pack
        self.isPremium = premium
        self.effect = effect
        self.adjust = adjust.manualOnly
    }

    /// Looks up a look by its persisted id. Unknown ids (a look retired in a
    /// later version) resolve to nil, and the cell then renders without it.
    public static func look(id: String) -> FilterLook? { byID[id] }

    private static let byID: [String: FilterLook] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// Strip order: packs in `FilterPack` order, looks in authoring order.
    public static let all: [FilterLook] = [
        // Essentials — free. The first five are the camera's looks.
        FilterLook("golden", String(localized: "Golden"), .essentials, premium: false, CameraFilter.golden.settings),
        FilterLook("fade", String(localized: "Fade"), .essentials, premium: false, CameraFilter.fade.settings),
        FilterLook("cool", String(localized: "Cool"), .essentials, premium: false, CameraFilter.cool.settings),
        FilterLook("vivid", String(localized: "Vivid"), .essentials, premium: false, CameraFilter.vivid.settings),
        FilterLook("mono", String(localized: "Mono"), .essentials, premium: false, CameraFilter.mono.settings),
        FilterLook("bright", String(localized: "Bright"), .essentials, premium: false,
                   CellFilters(brightness: 0.06, contrast: 0.96, saturation: 1.05, highlights: 0.2, shadows: 0.2)),
        FilterLook("crisp", String(localized: "Crisp"), .essentials, premium: false,
                   CellFilters(contrast: 1.12, saturation: 1.08, sharpness: 0.45, highlights: -0.15)),

        // Film
        FilterLook("roll400", String(localized: "Roll 400"), .film, premium: false,
                   CellFilters(contrast: 0.95, saturation: 0.9, warmth: 0.3, fade: 0.25, grain: 0.25)),
        FilterLook("matte", String(localized: "Matte"), .film, premium: true,
                   CellFilters(contrast: 0.9, saturation: 0.92, shadows: 0.2, fade: 0.35)),
        FilterLook("expired", String(localized: "Expired"), .film, premium: true, effect: .instant,
                   CellFilters(saturation: 0.85, warmth: 0.5, fade: 0.3, grain: 0.35)),
        FilterLook("chrome", String(localized: "Chrome"), .film, premium: true, effect: .chrome,
                   CellFilters(contrast: 1.05)),
        FilterLook("transfer", String(localized: "Transfer"), .film, premium: true, effect: .transfer),
        FilterLook("process", String(localized: "Process"), .film, premium: true, effect: .process),
        FilterLook("super8", String(localized: "Super 8"), .film, premium: true,
                   CellFilters(saturation: 0.85, warmth: 0.35, fade: 0.2, vignette: 0.5, grain: 0.5)),

        // Portrait
        FilterLook("glow", String(localized: "Glow"), .portrait, premium: false,
                   CellFilters(brightness: 0.05, contrast: 0.92, warmth: 0.15, highlights: 0.3)),
        FilterLook("peach", String(localized: "Peach"), .portrait, premium: true,
                   CellFilters(saturation: 1.05, warmth: 0.3, shadows: 0.15, fade: 0.1)),
        FilterLook("soft", String(localized: "Soft"), .portrait, premium: true,
                   CellFilters(contrast: 0.85, highlights: -0.2, shadows: 0.25, fade: 0.15)),
        FilterLook("bronze", String(localized: "Bronze"), .portrait, premium: true,
                   CellFilters(contrast: 1.1, saturation: 1.15, warmth: 0.5, vignette: 0.25)),
        FilterLook("porcelain", String(localized: "Porcelain"), .portrait, premium: true,
                   CellFilters(brightness: 0.06, saturation: 0.8, warmth: -0.15, highlights: 0.2)),

        // Mood
        FilterLook("dusk", String(localized: "Dusk"), .mood, premium: false,
                   CellFilters(contrast: 1.15, saturation: 0.9, warmth: -0.25, shadows: -0.3, vignette: 0.4)),
        FilterLook("teal", String(localized: "Teal"), .mood, premium: true,
                   CellFilters(saturation: 1.1, warmth: -0.35, highlights: 0.15, shadows: -0.15)),
        FilterLook("moody", String(localized: "Moody"), .mood, premium: true,
                   CellFilters(contrast: 1.2, saturation: 0.75, shadows: -0.35, vignette: 0.45)),
        FilterLook("ember", String(localized: "Ember"), .mood, premium: true,
                   CellFilters(contrast: 1.15, saturation: 1.2, warmth: 0.7, vignette: 0.35)),
        FilterLook("haze", String(localized: "Haze"), .mood, premium: true,
                   CellFilters(brightness: 0.05, contrast: 0.85, saturation: 0.9, fade: 0.4)),

        // Black & white
        FilterLook("noir", String(localized: "Noir"), .blackAndWhite, premium: true, effect: .noir),
        FilterLook("tonal", String(localized: "Tonal"), .blackAndWhite, premium: true, effect: .tonal),
        FilterLook("silver", String(localized: "Silver"), .blackAndWhite, premium: true,
                   CellFilters(contrast: 1.1, saturation: 0, highlights: 0.2, grain: 0.2)),
        FilterLook("grit", String(localized: "Grit"), .blackAndWhite, premium: true,
                   CellFilters(contrast: 1.35, saturation: 0, vignette: 0.4, grain: 0.45)),
        FilterLook("ash", String(localized: "Ash"), .blackAndWhite, premium: true,
                   CellFilters(contrast: 0.9, saturation: 0, fade: 0.3)),
    ]
}
