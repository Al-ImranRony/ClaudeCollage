//
//  Theme+SwiftUI.swift
//  ClaudeCollage
//
//  Step 05b Part B.
//
//  Half the app's sheets are SwiftUI, and `Theme` is a UIKit namespace, so those
//  sheets quietly kept reaching for `.headline` and `.secondary` — the single
//  biggest source of system-default drift in the codebase. Bridging the tokens
//  once removes the excuse.
//
//  These are deliberately thin wrappers rather than a parallel token set: there
//  is still exactly one definition of the app's colour and type, in `Theme`.
//

import SwiftUI

public extension Font {
    static var themeLargeTitle: Font { Font(Theme.Typography.largeTitle) }
    static var themeTitle: Font { Font(Theme.Typography.title) }
    static var themeTitle2: Font { Font(Theme.Typography.title2) }
    static var themeHeadline: Font { Font(Theme.Typography.headline) }
    static var themeBody: Font { Font(Theme.Typography.body) }
    static var themeCallout: Font { Font(Theme.Typography.callout) }
    static var themeSubheadline: Font { Font(Theme.Typography.subheadline) }
    static var themeCaption: Font { Font(Theme.Typography.caption) }
    static var themeButton: Font { Font(Theme.Typography.button) }
}

public extension Color {
    static var themeAccent: Color { Color(Theme.Color.accent) }
    static var themeAccentStrong: Color { Color(Theme.Color.accentStrong) }
    static var themeAccentSoft: Color { Color(Theme.Color.accentSoft) }
    static var themeBackground: Color { Color(Theme.Color.background) }
    static var themeSurface: Color { Color(Theme.Color.surface) }
    static var themeSurfaceRaised: Color { Color(Theme.Color.surfaceRaised) }
    static var themeTextPrimary: Color { Color(Theme.Color.textPrimary) }
    static var themeTextSecondary: Color { Color(Theme.Color.textSecondary) }
    static var themeTextOnAccent: Color { Color(Theme.Color.textOnAccent) }
    static var themeSeparator: Color { Color(Theme.Color.separator) }
    static var themeControlFill: Color { Color(Theme.Color.controlFill) }
}
