//
//  CanvasAccessibility.swift
//  Caroullage
//
//  Step 06 phase 6.5. Every label, hint and action title the canvas speaks,
//  as pure functions of model state. One file so the three overlay views say
//  the same kind of thing the same way, and so the words are testable without
//  a view.
//
//  Positions are 1-based and spoken ("2 of 4"): a rotor through four identical
//  "Photo cell" elements would give the user no position otherwise.
//

import Foundation

public enum CanvasAccessibility {

    // MARK: Cells

    public static func cellLabel(index: Int, count: Int, hasImage: Bool) -> String {
        hasImage
            ? String(localized: "Photo cell \(index + 1) of \(count)")
            : String(localized: "Empty cell \(index + 1) of \(count)")
    }

    public static func cellHint(hasImage: Bool) -> String {
        hasImage
            ? String(localized: "Double-tap to edit.")
            : String(localized: "Double-tap to choose a photo.")
    }

    public static var swapAction: String { String(localized: "Swap with another cell") }

    // MARK: Text zones

    public static func textLabel(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? String(localized: "Empty text")
            : String(localized: "Text: “\(trimmed)”")
    }

    public static var textHint: String { String(localized: "Double-tap to edit the text.") }

    // MARK: Stickers

    public static func stickerLabel(name: String, isPersonal: Bool) -> String {
        isPersonal
            ? String(localized: "Personal sticker")
            : String(localized: "Sticker: \(name)")
    }

    public static var stickerHint: String { String(localized: "Double-tap to select.") }

    /// A spoken name from a catalog id — "basic.heart" → "Heart",
    /// "celebration.party_popper" → "Party popper". The catalog's own names
    /// are exactly this shape, and deriving it keeps the view out of the
    /// catalog service.
    public static func stickerName(fromID id: String) -> String {
        let last = id.split(separator: ".").last.map(String.init) ?? id
        let spaced = last.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        guard let first = spaced.first else { return spaced }
        return first.uppercased() + spaced.dropFirst()
    }

    // MARK: Shared actions

    public static var deleteAction: String { String(localized: "Delete") }
    public static var largerAction: String { String(localized: "Larger") }
    public static var smallerAction: String { String(localized: "Smaller") }
    public static var rotateLeftAction: String { String(localized: "Rotate left") }
    public static var rotateRightAction: String { String(localized: "Rotate right") }
    public static var moveUpAction: String { String(localized: "Move up") }
    public static var moveDownAction: String { String(localized: "Move down") }
    public static var moveLeftAction: String { String(localized: "Move left") }
    public static var moveRightAction: String { String(localized: "Move right") }

    // MARK: Rotors

    public static var cellsRotor: String { String(localized: "Cells") }
    public static var framesRotor: String { String(localized: "Frames") }

    // MARK: Video cells

    public static func videoCellLabel(index: Int, count: Int, isFilled: Bool) -> String {
        isFilled
            ? String(localized: "Video cell \(index + 1) of \(count)")
            : String(localized: "Empty video cell \(index + 1) of \(count)")
    }

    public static func videoCellHint(isFilled: Bool) -> String {
        isFilled
            ? String(localized: "Double-tap to edit the clip.")
            : String(localized: "Double-tap to choose a video.")
    }
}
