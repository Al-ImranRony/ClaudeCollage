//
//  Theme+SwiftUI.swift
//  Caroullage
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
    static var themeAccentSecondary: Color { Color(Theme.Color.accentSecondary) }
    static var themeAccentFar: Color { Color(Theme.Color.accentFar) }
    static var themeAccentSoft: Color { Color(Theme.Color.accentSoft) }
    static var themeBackground: Color { Color(Theme.Color.background) }
    static var themeSurface: Color { Color(Theme.Color.surface) }
    static var themeSurfaceRaised: Color { Color(Theme.Color.surfaceRaised) }
    static var themeTextPrimary: Color { Color(Theme.Color.textPrimary) }
    static var themeTextSecondary: Color { Color(Theme.Color.textSecondary) }
    static var themeTextOnAccent: Color { Color(Theme.Color.textOnAccent) }
    static var themeSeparator: Color { Color(Theme.Color.separator) }
    static var themeControlFill: Color { Color(Theme.Color.controlFill) }
    static var themeCritical: Color { Color(Theme.Color.critical) }
    static var themeSuccess: Color { Color(Theme.Color.success) }
    static var themeWarning: Color { Color(Theme.Color.warning) }
}

public extension LinearGradient {

    /// The brand gradient — the same two tokens `Theme.Color.brandGradient(for:)`
    /// paints in UIKit.
    ///
    /// It exists because the SwiftUI side had no brand gradient at all, so the
    /// surfaces that wanted one invented it. Onboarding's hero and CTA ran
    /// `accent → accentStrong`, which was a quiet same-family darkening while
    /// the brand was orange and became a jump from the chromatic spark to the
    /// ink the moment it was not. One definition, in `Theme`, is the whole
    /// point of this file.
    ///
    /// No trait collection, unlike the UIKit twin: a SwiftUI `Color` wrapping a
    /// dynamic `UIColor` resolves itself, so there is nothing to hand it.
    ///
    /// The direction defaults to the UIKit gradient's top-leading →
    /// bottom-trailing; a wide, short surface reads better with the horizontal
    /// pair, which is why it is a parameter and not a constant.
    static func themeBrand(
        startPoint: UnitPoint = .topLeading,
        endPoint: UnitPoint = .bottomTrailing
    ) -> LinearGradient {
        LinearGradient(
            colors: [.themeAccentStrong, .themeAccentSecondary],
            startPoint: startPoint,
            endPoint: endPoint
        )
    }

    /// The chromatic ramp — `accent` → `accentFar`, the same pair the app icon
    /// paints its collage cells with.
    ///
    /// A deliberate exception to "ink is chrome", and the only one: onboarding
    /// is the app before there is any content in it, so there is nothing for
    /// ink to be restrained *against* and a monochrome first run reads austere
    /// rather than assured. Everywhere past onboarding, `themeBrand` is the
    /// gradient — the ink takes over exactly when the photographs arrive.
    ///
    /// Both stops carry `textOnAccent`; see `Theme.Color.accentFar` for why the
    /// ramp reverses direction between appearances.
    static func themeSpark(
        startPoint: UnitPoint = .topLeading,
        endPoint: UnitPoint = .bottomTrailing
    ) -> LinearGradient {
        LinearGradient(
            colors: [.themeAccent, .themeAccentFar],
            startPoint: startPoint,
            endPoint: endPoint
        )
    }
}
