//
//  CollageBackground.swift
//  Caroullage
//
//  Step 01 — canvas background. Solid colour only for now; gradient and
//  texture backgrounds arrive with the template system in Step 03.
//

import Foundation

public enum CollageBackground: Equatable, Sendable, Codable {
    case solid(hex: String)

    public static let white = CollageBackground.solid(hex: "#FFFFFF")
    public static let black = CollageBackground.solid(hex: "#000000")

    /// The swatch palette offered in the Step 01 background picker.
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

    public var hex: String {
        switch self {
        case let .solid(hex): return hex
        }
    }
}
