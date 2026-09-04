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

        // Brand — obsidian. The single most important decision here: this
        // app's identity is carried by ink and restraint, not by a hue.

        /// The one chromatic note in the system: selection, and little else.
        ///
        /// This is a collage app, so the warm end of the spectrum belongs to
        /// the photographs — skin, golden hour, food, wood — and chrome painted
        /// in that family competes with the canvas it is meant to frame. The
        /// chrome is therefore ink (`accentStrong`), and the colour that used
        /// to be spread across every button is concentrated here instead:
        /// selection strokes, selected-cell borders, the wash under a `.tinted()`
        /// button, a progress tint.
        ///
        /// It has to stay chromatic precisely because `accentStrong` is not.
        /// A selection stroke drawn in ink disappears into the dark regions of
        /// a photograph, which is the one place a collage app cannot afford to
        /// lose it. Indigo reads over any exposure, and it is clear of
        /// `critical`, `success` and `warning`, which have already claimed the
        /// red, green and amber families.
        ///
        /// Because it now covers a few percent of the screen rather than most
        /// of the chrome, it can be fully saturated without shouting.
        public static var accent: UIColor {
            dynamic(light: 0x5B54E8, dark: 0x8B85F5)
        }

        /// Primary Pressed — the pressed state of the ink chrome.
        ///
        /// Lighter than `accentStrong` in light mode, not darker: at #18181B
        /// there is no darker left to go, so the press reads by stepping toward
        /// the surface. Dark mode mirrors it.
        public static var accentPressed: UIColor {
            dynamic(light: 0x3F3F46, dark: 0xD4D4D8)
        }

        /// The chrome: filled buttons, the tab bar tint, badges, the selected
        /// segment, and any label or glyph marking an active state.
        ///
        /// Obsidian cannot compete with a photograph because it is not a
        /// colour; it reads as chrome at every exposure, over every image, in
        /// both appearances. It also retires a workaround — the previous orange
        /// needed a separate, darkened token here because no single orange is
        /// both a legible fill and legible ink against near-white. That orange
        /// cleared its gates at 1.03× the requirement; this clears them at 17:1.
        ///
        /// It inverts in dark mode rather than lifting: ink chrome's job is to
        /// be the furthest thing from the ground it sits on.
        public static var accentStrong: UIColor {
            dynamic(light: 0x18181B, dark: 0xFAFAFA)
        }

        /// The far end of the brand gradient (accentStrong → accentSecondary),
        /// used on hero surfaces and the primary CTA. A charcoal one step off
        /// the ink: enough for the gradient to read as a gradient, not enough
        /// to turn the chrome back into a colour.
        public static var accentSecondary: UIColor {
            dynamic(light: 0x3F3F46, dark: 0xD4D4D8)
        }

        // Backgrounds, from the owner's palette: Background #FFFFFF and Card
        // #FCFCFC. Those two are a hair apart on purpose — separation comes
        // from the border and the card shadow rather than from a fill
        // difference, which is what keeps a white-canvas app looking clean
        // instead of grey.
        //
        // Every neutral in this file sits on ONE axis: true grey, no hue. Two
        // reasons, and the first is specific to this app. A tinted neutral
        // shifts the apparent colour of whatever sits next to it, and what sits
        // next to these surfaces is always a photograph — a blue-grey chrome
        // makes a warm photo read warmer, which is the one thing a tool for
        // judging pictures must not do. Colour-critical tools are neutral-grey
        // for exactly this reason. The second is coherence: with an ink brand
        // the accent IS a neutral, so a blue-tinted text ramp beside a pure-grey
        // accent reads as two greys that don't match. These values used to be
        // Tailwind slate and GitHub dark-blue, chosen when the brand was orange
        // and a cool chrome was its complement.
        public static var background: UIColor {
            dynamic(light: 0xFFFFFF, dark: 0x0E0E10)
        }

        public static var surface: UIColor {
            dynamic(light: 0xFCFCFC, dark: 0x17171A)
        }

        public static var surfaceRaised: UIColor {
            dynamic(light: 0xFFFFFF, dark: 0x1D1D21)
        }

        // Text.
        /// Body ink.
        ///
        /// The same value as `accentStrong`, which is correct rather than a
        /// collision: in an ink system the brand and the body ink are the same
        /// black, and an "accent-coloured" label is distinguished from a plain
        /// one by weight and by what sits next to it, not by hue. Its old value
        /// was blue-tinted slate — see the note on the neutral axis above.
        public static var textPrimary: UIColor {
            dynamic(light: 0x18181B, dark: 0xFAFAFA)
        }

        /// Supporting ink. Two steps up the same grey, and a little darker than
        /// the slate it replaces, which was scraping 4.83:1 on white.
        public static var textSecondary: UIColor {
            dynamic(light: 0x6E6E77, dark: 0xA1A1AA)
        }

        /// Ink for anything sitting on `accentStrong`.
        ///
        /// Not simply white, because `accentStrong` inverts: it is near-black
        /// in light mode and near-white in dark, so its ink has to invert with
        /// it. Neutral rather than the warm near-black this token used to
        /// carry — that value was chosen to sit under an orange fill and reads
        /// as a stain under a neutral one.
        public static var textOnAccent: UIColor {
            dynamic(light: 0xFFFFFF, dark: 0x18181B)
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
        /// The outline is `separator`'s family, one shade down from its #E4E4E7:
        /// a template thumbnail is rendered at 300px and then shown at 132pt, and
        /// at that reduction a true #E4E4E7 hairline resolves away to nothing —
        /// which is precisely where the zones most need to be legible.
        ///
        /// The chip is the counterweight — a neutral near-black disc with
        /// white ink, so the tap target is the one thing in an empty zone
        /// carrying real contrast (9.8:1 on the well). Neutral rather than the
        /// warm grey it used to be: that value was picked to partner an orange
        /// brand, and it reads as a colour cast beside an ink one.
        public static var cellWellOutline: UIColor { rgb(0xE0E2E7) }
        public static var cellWellChip: UIColor { rgb(0x3F3F46).withAlphaComponent(0.92) }
        public static var cellWellChipInk: UIColor { UIColor.white }

        // Lines & fills.
        /// Border. Load-bearing now that the canvas and cards are both
        /// near-white — this hairline is what separates them, not a fill step.
        /// The palette's #E5E7EB moved onto the neutral axis as #E4E4E7; the
        /// two are indistinguishable side by side.
        public static var separator: UIColor {
            dynamic(light: 0xE4E4E7, dark: 0x2B2B31)
        }

        /// Secondary Background from the palette, #F7F7F8, doing the job it is
        /// best at: the track under a segmented control, a chip, a field.
        ///
        /// The light value is untouched — it was already a true grey, and
        /// `cellWell` is defined as this exact tone. Only the dark value moved
        /// onto the neutral axis.
        public static var controlFill: UIColor {
            dynamic(light: 0xF7F7F8, dark: 0x232327)
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

        /// Warning — a canvas that does not match the preset, an export that
        /// will be scaled. Darkened in light mode for the same reason as
        /// `success`: the palette's #F59E0B is a fill, not an ink.
        ///
        /// The light value is amber rather than the burnt orange it used to be.
        /// #B45309 was picked to sit beside an orange brand and had to be
        /// *pushed* toward red to stay distinct from it — which is also how it
        /// ended up identical to the old `accentStrong`. With the brand out of
        /// the warm end entirely, warning is free to look like a warning.
        public static var warning: UIColor {
            dynamic(light: 0xA16207, dark: 0xFBBF24)
        }

        /// The accent as a low-opacity tint, e.g. selected-swatch halo.
        ///
        /// Built from `accent` rather than `accentStrong` for the reason
        /// `accent` stays chromatic at all: fifteen percent of an ink chrome is
        /// a grey smudge, which is exactly what a halo must not be.
        public static var accentSoft: UIColor {
            accent.withAlphaComponent(0.15)
        }

        /// The two-stop brand gradient, top-leading → bottom-trailing.
        ///
        /// Takes a trait collection because `CGColor` is resolved, not dynamic:
        /// a gradient layer keeps whatever colours it was given until something
        /// repaints it, so the caller has to say which appearance it wants.
        ///
        /// The stops are the same two tokens in both appearances now. The old
        /// gradient picked different stops per appearance to dodge orange's
        /// contrast cliff — carrying it up to the bright amber would have put
        /// white on a 2.2:1 fill. `accentStrong` and `accentSecondary` both
        /// invert on their own, so the appearance branch has nothing left to
        /// decide.
        public static func brandGradient(for traits: UITraitCollection) -> [CGColor] {
            [accentStrong, accentSecondary].map { $0.resolvedColor(with: traits).cgColor }
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
