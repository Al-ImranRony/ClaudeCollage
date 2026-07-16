//
//  UIColor+Hex.swift
//  ClaudeCollage
//
//  Step 01 — parse/emit "#RRGGBB" / "#RRGGBBAA" hex strings.
//

import UIKit

public extension UIColor {

    /// Creates a colour from a `#RRGGBB` or `#RRGGBBAA` hex string.
    /// Falls back to white for malformed input so rendering never traps.
    convenience init(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }

        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value) else {
            self.init(white: 1, alpha: 1)
            return
        }

        let red, green, blue, alpha: CGFloat
        switch cleaned.count {
        case 6:
            red = CGFloat((value & 0xFF0000) >> 16) / 255
            green = CGFloat((value & 0x00FF00) >> 8) / 255
            blue = CGFloat(value & 0x0000FF) / 255
            alpha = 1
        case 8:
            red = CGFloat((value & 0xFF00_0000) >> 24) / 255
            green = CGFloat((value & 0x00FF_0000) >> 16) / 255
            blue = CGFloat((value & 0x0000_FF00) >> 8) / 255
            alpha = CGFloat(value & 0x0000_00FF) / 255
        default:
            self.init(white: 1, alpha: 1)
            return
        }
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// Convenience bridge from the model background type.
    convenience init(background: CollageBackground) {
        self.init(hex: background.hex)
    }

    /// Emits an uppercase `#RRGGBB` string (alpha dropped — opacity is stored
    /// separately on `TextOverlay`). Used to persist a colour picked in the UI.
    var hexStringRGB: String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return "#000000" }
        func channel(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", channel(red), channel(green), channel(blue))
    }
}
