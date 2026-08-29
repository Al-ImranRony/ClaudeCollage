//
//  Theme.swift
//  Caroullage
//
//  The design foundation. A single source of truth for colour, typography,
//  spacing, corner radius, elevation and motion so that every screen — the ones
//  built now and the polygon/template/video editors that come next — inherits a
//  consistent, App-Store-grade look instead of raw system defaults.
//
//  All tokens are exposed as *computed* static properties. Under Swift 6 strict
//  concurrency, stored static `UIColor`/`UIFont` constants are flagged as
//  non-Sendable shared state; computing a fresh value on each access sidesteps
//  that while keeping call sites terse (`Theme.Color.accent`). The cost is a
//  cheap object allocation, negligible for UI code.
//

import UIKit

/// Namespace for the app's design tokens.
public enum Theme {

    // MARK: - Colour

    /// Semantic colour tokens. Every colour is dynamic (light/dark aware) so the
    /// whole app themes correctly without per-call-site `traitCollection` checks.
    public enum Color {

        // Brand — Claude orange. The single most important token: this is the
        // app's identity, used brilliantly wherever an accent fits.
        ///
/// Primary, from the owner's palette (2026-08-26).
        ///
        /// The palette says #E67E22; the light value here is #E0761C, which is
        /// the same orange about two percent darker. #E67E22 lands at 2.85:1
        /// against the palette's white background — under the 3:1 that a fill's
        /// own edge and any large text on it must clear — and the palette moved
        /// the background from off-white to pure white, which is what pushed it
        /// under. The nudge is imperceptible side by side and it keeps the
        /// token honest about the job it does. `ThemeContrastTests` is what
        /// caught it, the same way it caught the previous orange.
        ///
        /// The dark value lifts it so it reads as the same colour on a dark
        /// ground instead of sinking into it.
        public static var accent: UIColor {
            dynamic(light: 0xE0761C, dark: 0xF0913F)
        }

        /// Primary Pressed, per the palette: #C96A16.
        public static var accentPressed: UIColor {
            dynamic(light: 0xC96A16, dark: 0xD97B22)
        }

        /// The accent corrected for contrast, and the only accent that may
        /// carry or be carried by body-sized text.
        ///
        /// The identity orange is too light to be legible as ink: white on
        /// `accent` is 3.2:1 and `accent` on `background` is 3.0:1 — both fine
        /// for large text and for non-text UI, both short of the 4.5:1 that
        /// body text needs. So `accent` stays the identity (fills, gradients,
        /// selection, display type) and this token does the reading work:
        /// accent-coloured labels and glyphs on app surfaces, and the fill
        /// under `textOnAccent`.
        ///
        /// It darkens in light mode and lightens in dark mode, which is why one
        /// token can serve both roles — see `ThemeContrastTests`.
        /// Not in the owner's palette because a palette lists identity, not
        /// legibility: white on Primary is 2.9:1 and Primary on white is 3.1:1,
        /// so Primary cannot carry body text either way. #B45309 is the same
        /// family, two steps darker, and clears 4.5:1 in both directions.
        public static var accentStrong: UIColor {
            dynamic(light: 0xB45309, dark: 0xF0913F)
        }

        /// The far end of the brand gradient (accent → accentSecondary) used on
        /// hero surfaces, the primary CTA and selection glows. A warm amber keeps
        /// the gradient inside the orange family — minimal, no clashing hue.
        public static var accentSecondary: UIColor {
            dynamic(light: 0xF59E0B, dark: 0xFBBF24)
        }

        // Backgrounds, from the owner's palette: Background #FFFFFF and Card
        // #FCFCFC. Those two are a hair apart on purpose — separation comes
        // from the border and the card shadow rather than from a fill
        // difference, which is what keeps a white-canvas app looking clean
        // instead of grey.
        public static var background: UIColor {
            dynamic(light: 0xFFFFFF, dark: 0x0D1117)
        }

        public static var surface: UIColor {
            dynamic(light: 0xFCFCFC, dark: 0x161B22)
        }

        public static var surfaceRaised: UIColor {
            dynamic(light: 0xFFFFFF, dark: 0x1C222B)
        }

        // Text.
        public static var textPrimary: UIColor {
            dynamic(light: 0x111827, dark: 0xF3F5F8)
        }

        public static var textSecondary: UIColor {
            dynamic(light: 0x6B7280, dark: 0x9CA3AF)
        }

        /// Ink for anything sitting on `accentStrong`.
        ///
        /// Not simply white. In dark mode `accentStrong` is the *bright*
        /// orange, and white on it is 2.5:1 — worse than the problem it was
        /// meant to solve. A warm near-black gets 7.4:1 there, and reads as a
        /// deliberate choice rather than a compromise.
        public static var textOnAccent: UIColor {
            dynamic(light: 0xFFFFFF, dark: 0x17110C)
        }

        /// A toast's ground and ink.
        ///
        /// Fixed in both appearances on purpose: a toast floats over whatever
        /// the screen happens to be showing — a photo, a video frame, a dark
        /// canvas — so it cannot borrow the surface tokens and stay readable.
        public static var toast: UIColor { UIColor(white: 0.08, alpha: 0.92) }
        public static var textOnToast: UIColor { .white }

        /// The fill behind an empty photo cell.
        ///
        /// Deliberately NOT dynamic. This colour is composited into exported
        /// images, so it must not depend on whether the user happened to be in
        /// dark mode when they hit Export; the on-screen canvas paints the same
        /// value so the preview matches the file.
        ///
        /// The value is `controlFill`'s light tone rather than a warm grey of its
        /// own. The warm well was a dark enough fill that the hairline tracing it
        /// had nothing to read against, so a grid of empty zones came out as one
        /// beige slab; the video editor, whose slots have always been this near-
        /// white, was visibly the clearer of the two. Both editors now paint the
        /// same well, and the boundary is what carries the zone.
        public static var cellWell: UIColor { rgb(0xF7F7F8) }

        /// The hairline tracing an empty zone's boundary, and the "+" chip that
        /// sits at its centre. Fixed for the same reason as `cellWell`: they are
        /// composited into exported files and template thumbnails.
        ///
        /// The outline is `separator`'s family, one shade down from its #E5E7EB:
        /// a template thumbnail is rendered at 300px and then shown at 132pt, and
        /// at that reduction a true #E5E7EB hairline resolves away to nothing —
        /// which is precisely where the zones most need to be legible.
        ///
        /// The chip is the counterweight — a warm near-black disc with white ink,
        /// so the tap target is the one thing in an empty zone carrying real
        /// contrast (12:1 on the well).
        public static var cellWellOutline: UIColor { rgb(0xE0E2E7) }
        public static var cellWellChip: UIColor { rgb(0x4D4842).withAlphaComponent(0.92) }
        public static var cellWellChipInk: UIColor { UIColor.white }

        // Lines & fills.
        /// Border, per the palette: #E5E7EB. Load-bearing now that the canvas
        /// and cards are both near-white.
        public static var separator: UIColor {
            dynamic(light: 0xE5E7EB, dark: 0x2A2F37)
        }

        /// Secondary Background from the palette, #F7F7F8, doing the job it is
        /// best at: the track under a segmented control, a chip, a field.
        public static var controlFill: UIColor {
            dynamic(light: 0xF7F7F8, dark: 0x22272E)
        }

        /// Error, per the palette: #EF4444. A purchase that did not go through,
        /// a save that could not be written.
        ///
        /// The dark value is lifted rather than matched: #EF4444 on a dark
        /// ground is 4.0:1, which is under the bar for the small text this
        /// token is used at.
        public static var critical: UIColor {
            dynamic(light: 0xDC2626, dark: 0xF87171)
        }

        /// Success, per the palette: #22C55E — an export that finished, a
        /// purchase that landed.
        ///
        /// #22C55E is a fill colour, not an ink one: at 2.3:1 on white it is
        /// fine behind a glyph and illegible as text, so the light value is
        /// darkened for the places this is used as a label.
        public static var success: UIColor {
            dynamic(light: 0x15803D, dark: 0x4ADE80)
        }

        /// Success at the palette's own value, #22C55E, for the far end of a
        /// gradient or a fill large enough that contrast is not the question.
        public static var successBright: UIColor {
            dynamic(light: 0x22C55E, dark: 0x22C55E)
        }

        /// Warning, per the palette: #F59E0B — a canvas that does not match the
        /// preset, an export that will be scaled. Darkened in light mode for the
        /// same reason as `success`.
        public static var warning: UIColor {
            dynamic(light: 0xB45309, dark: 0xFBBF24)
        }

        /// The accent as a low-opacity tint, e.g. selected-swatch halo.
        public static var accentSoft: UIColor {
            accent.withAlphaComponent(0.15)
        }

        /// The two-stop brand gradient, top-leading → bottom-trailing.
        ///
        /// Takes a trait collection because `CGColor` is resolved, not dynamic:
        /// a gradient layer keeps whatever colours it was given until something
        /// repaints it, so the caller has to say which appearance it wants.
        ///
        /// The stops differ by appearance for contrast, not for taste. In light
        /// the gradient runs `accentStrong → accent` under white; carrying it up
        /// to `accentSecondary` would put white on a 2.2:1 amber. In dark the
        /// ink flips to near-black, so the gradient can run the bright half of
        /// the ramp instead.
        public static func brandGradient(for traits: UITraitCollection) -> [CGColor] {
            let stops = traits.userInterfaceStyle == .dark
                ? [accent, accentSecondary]
                : [accentStrong, accent]
            return stops.map { $0.resolvedColor(with: traits).cgColor }
        }

        // MARK: helpers

        private static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
            UIColor { traits in
                traits.userInterfaceStyle == .dark ? rgb(dark) : rgb(light)
            }
        }

        private static func rgb(_ value: UInt32) -> UIColor {
            UIColor(
                red: CGFloat((value & 0xFF0000) >> 16) / 255,
                green: CGFloat((value & 0x00FF00) >> 8) / 255,
                blue: CGFloat(value & 0x0000FF) / 255,
                alpha: 1
            )
        }
    }

    // MARK: - Typography

    /// A rounded type scale. SF Pro Rounded gives the app a friendlier, more
    /// "creative-tool" character than the default while staying native. Every
    /// font is registered with `UIFontMetrics` so Dynamic Type still scales it.
    public enum Typography {

        public static var largeTitle: UIFont { rounded(34, .bold, .largeTitle) }
        public static var title: UIFont { rounded(28, .bold, .title1) }
        public static var title2: UIFont { rounded(22, .semibold, .title2) }
        public static var headline: UIFont { rounded(17, .semibold, .headline) }
        public static var body: UIFont { rounded(17, .regular, .body) }
        public static var callout: UIFont { rounded(16, .medium, .callout) }
        public static var subheadline: UIFont { rounded(15, .medium, .subheadline) }
        public static var caption: UIFont { rounded(13, .medium, .caption1) }

        /// Tab bar labels. Smaller and tighter than `caption`, because four of
        /// them plus their icons have to fit a phone's width without truncating.
        public static var tabLabel: UIFont { rounded(10, .semibold, .caption2) }
        public static var button: UIFont { rounded(17, .semibold, .headline) }

        /// A rounded system font at exactly `size`, with no Dynamic Type scaling.
        ///
        /// For type that is *drawn* rather than laid out — overlay labels whose
        /// size is derived from the geometry they sit in. Scaling those would
        /// push them out of the region they are labelling.
        public static func roundedFixed(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
            return UIFont(descriptor: descriptor, size: size)
        }

        /// A rounded system font at `size`/`weight`, scaled for the given text style.
        public static func rounded(
            _ size: CGFloat,
            _ weight: UIFont.Weight,
            _ style: UIFont.TextStyle
        ) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            let font: UIFont
            if let descriptor = base.fontDescriptor.withDesign(.rounded) {
                font = UIFont(descriptor: descriptor, size: size)
            } else {
                font = base
            }
            return UIFontMetrics(forTextStyle: style).scaledFont(for: font)
        }
    }

    // MARK: - Spacing

    /// A 4-pt spacing scale. Use these instead of literal constants so layout
    /// rhythm stays consistent across screens.
    public enum Spacing {
        public static let xxs: CGFloat = 4
        public static let xs: CGFloat = 8
        public static let sm: CGFloat = 12
        public static let md: CGFloat = 16
        public static let lg: CGFloat = 20
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
    }

    // MARK: - Corner radius

    public enum Radius {
        public static let sm: CGFloat = 10
        public static let md: CGFloat = 14
        public static let lg: CGFloat = 20
        public static let xl: CGFloat = 28
        /// Sentinel for a fully-rounded (pill/circle) corner; callers use height/2.
        public static let pill: CGFloat = .greatestFiniteMagnitude
    }

    // MARK: - Elevation

    /// A soft card shadow. Applied via `applyCardShadow(...)`.
    public enum Elevation {
        public static let cardOpacity: Float = 0.10
        public static let cardRadius: CGFloat = 14
        public static let cardOffset = CGSize(width: 0, height: 6)
    }

    // MARK: - Motion

    /// Standard animation timings so transitions feel coherent app-wide.
    public enum Motion {
        public static let quick: TimeInterval = 0.18
        public static let standard: TimeInterval = 0.28
        public static let slow: TimeInterval = 0.42

        /// A lively spring for selection / tap feedback.
        public static let springDamping: CGFloat = 0.72
        public static let springVelocity: CGFloat = 0.4

        /// True when the user has asked the system to reduce motion.
        @MainActor
        public static var isReduced: Bool { UIAccessibility.isReduceMotionEnabled }

        /// A duration honouring Reduce Motion: the same value normally, and a
        /// short cross-fade instead of a spring when motion is reduced.
        ///
        /// Zero would make state changes snap, which reads as a glitch; a brief
        /// fade keeps the change legible without moving anything.
        @MainActor
        public static func duration(_ base: TimeInterval) -> TimeInterval {
            isReduced ? min(base, 0.12) : base
        }

        /// Spring parameters, flattened to a plain fade when motion is reduced.
        /// Damping 1 removes the overshoot that is the point of a spring.
        @MainActor
        public static var effectiveSpringDamping: CGFloat {
            isReduced ? 1 : springDamping
        }

        @MainActor
        public static var effectiveSpringVelocity: CGFloat {
            isReduced ? 0 : springVelocity
        }
    }
}

// MARK: - Convenience

public extension UIView {

    /// Applies the standard soft card shadow. Note: the view must not clip to
    /// bounds for the shadow to show — put content in a rounded subview.
    func applyCardShadow() {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = Theme.Elevation.cardOpacity
        layer.shadowRadius = Theme.Elevation.cardRadius
        layer.shadowOffset = Theme.Elevation.cardOffset
    }
}
