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
    // The same scale as `Theme.Typography` — rounded design, the same weights,
    // the system text style each token is built on — expressed natively rather
    // than as `Font(UIFont)`. A `Font` wrapped around a `UIFont` carries no
    // text style: SwiftUI treats it as fixed, so it neither follows a Dynamic
    // Type change nor tells the accessibility audit that it could (phase 6.5).
    static var themeLargeTitle: Font { .system(.largeTitle, design: .rounded, weight: .bold) }
    static var themeTitle: Font { .system(.title, design: .rounded, weight: .bold) }
    static var themeTitle2: Font { .system(.title2, design: .rounded, weight: .semibold) }
    static var themeHeadline: Font { .system(.headline, design: .rounded, weight: .semibold) }
    static var themeBody: Font { .system(.body, design: .rounded, weight: .regular) }
    static var themeCallout: Font { .system(.callout, design: .rounded, weight: .medium) }
    static var themeSubheadline: Font { .system(.subheadline, design: .rounded, weight: .medium) }
    /// `Typography.caption` is 13pt, which is the system's footnote, not its
    /// 12pt caption1.
    static var themeCaption: Font { .system(.footnote, design: .rounded, weight: .medium) }
    static var themeButton: Font { .system(.headline, design: .rounded, weight: .semibold) }
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
    /// The deliberate exception to "ink is chrome", and the only one. It is
    /// drawn around what a screen is *for*, not where it sits in the flow: the
    /// marketing surfaces — onboarding and the paywall — are the app talking
    /// about itself, with no content of their own, so there is nothing for ink
    /// to be restrained against and monochrome reads austere rather than
    /// assured. The paywall is on this side of the line even though the Pro
    /// badge can open it mid-session, because it is selling either way.
    ///
    /// Every surface where the user is actually working on something takes
    /// `themeBrand` — the ink starts exactly where the photographs do.
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

// MARK: - Dynamic Type bridges (phase 6.5)

public extension Font {
    /// A rounded semantic style with a weight — the SwiftUI-native way to say
    /// "callout, bold" and still scale with Dynamic Type. `Font(UIFont)` does
    /// not take `.weight()`, so the weighted variants come through here.
    static func themeRounded(_ style: Font.TextStyle, weight: Font.Weight) -> Font {
        .system(style, design: .rounded, weight: weight)
    }

    /// A display size — the paywall's price, onboarding's hero numeral — that
    /// still follows Dynamic Type. `@ScaledMetric` is the SwiftUI way to say
    /// "this size, relative to large title"; a bare `.system(size:)` never grows.
    /// Usage: `@ScaledMetric(relativeTo: .largeTitle) private var heroSize = 64`
    /// then `.font(.themeDisplay(heroSize))`.
    static func themeDisplay(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Hit targets

public extension View {
    /// Grows a text-only control's label to at least `Theme.Layout.minimumHitTarget`
    /// on both axes and makes the whole of it tappable. A caption-sized "Skip"
    /// or "Terms" keeps its size and gains a finger-sized target.
    func hitTargetPadded() -> some View {
        frame(minWidth: Theme.Layout.minimumHitTarget, minHeight: Theme.Layout.minimumHitTarget)
            .contentShape(Rectangle())
    }
}
