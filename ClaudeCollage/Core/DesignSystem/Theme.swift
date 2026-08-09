//
//  Theme.swift
//  ClaudeCollage
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
        public static var accent: UIColor {
            dynamic(light: 0xE86A2A, dark: 0xF5843E)
        }

        /// A slightly deeper accent for pressed/active states.
        public static var accentPressed: UIColor {
            dynamic(light: 0xCC5716, dark: 0xE0702B)
        }

        /// The far end of the brand gradient (accent → accentSecondary) used on
        /// hero surfaces, the primary CTA and selection glows. A warm amber keeps
        /// the gradient inside the orange family — minimal, no clashing hue.
        public static var accentSecondary: UIColor {
            dynamic(light: 0xF29B3C, dark: 0xF7AC53)
        }

        // Backgrounds — layered so cards read against the canvas.
        public static var background: UIColor {
            dynamic(light: 0xF7F6F4, dark: 0x0E0E10)
        }

        public static var surface: UIColor {
            dynamic(light: 0xFFFFFF, dark: 0x1B1B1E)
        }

        public static var surfaceRaised: UIColor {
            dynamic(light: 0xFFFFFF, dark: 0x252528)
        }

        // Text.
        public static var textPrimary: UIColor {
            dynamic(light: 0x1A1A1C, dark: 0xF5F5F7)
        }

        public static var textSecondary: UIColor {
            dynamic(light: 0x6B6B70, dark: 0x9B9BA1)
        }

        public static var textOnAccent: UIColor { .white }

        // Lines & fills.
        public static var separator: UIColor {
            dynamic(light: 0xE4E2DE, dark: 0x2E2E32)
        }

        public static var controlFill: UIColor {
            dynamic(light: 0xEFEDE9, dark: 0x2A2A2E)
        }

        /// The accent as a low-opacity tint, e.g. selected-swatch halo.
        public static var accentSoft: UIColor {
            accent.withAlphaComponent(0.15)
        }

        /// The two-stop brand gradient, top-leading → bottom-trailing.
        public static var brandGradient: [CGColor] {
            [accent.cgColor, accentSecondary.cgColor]
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
        public static var button: UIFont { rounded(17, .semibold, .headline) }

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
