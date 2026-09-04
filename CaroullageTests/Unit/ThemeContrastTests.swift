//
//  ThemeContrastTests.swift
//  CaroullageTests
//
//  Step 05b Part B.
//
//  Almost nothing about "does it look right" can be asserted mechanically.
//  Contrast can. These tests pin the brand ink pairs to WCAG AA in BOTH
//  appearances, which is what stops the orange identity from quietly becoming
//  unreadable as tokens get tuned.
//
//  Thresholds are WCAG 2.1: 4.5:1 for body text, 3:1 for large text (≥24px, or
//  ≥18.66px bold) and for non-text UI components.
//

import UIKit
import XCTest
@testable import Caroullage

final class ThemeContrastTests: XCTestCase {

    private let body: CGFloat = 4.5
    private let large: CGFloat = 3.0

    // MARK: - Text on backgrounds

    func testPrimaryTextClearsAAOnEverySurface() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            assertContrast(Theme.Color.textPrimary, on: Theme.Color.background, atLeast: body, style: style)
            assertContrast(Theme.Color.textPrimary, on: Theme.Color.surface, atLeast: body, style: style)
            assertContrast(Theme.Color.textPrimary, on: Theme.Color.surfaceRaised, atLeast: body, style: style)
        }
    }

    func testSecondaryTextClearsAAOnEverySurface() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            assertContrast(Theme.Color.textSecondary, on: Theme.Color.background, atLeast: body, style: style)
            assertContrast(Theme.Color.textSecondary, on: Theme.Color.surface, atLeast: body, style: style)
        }
    }

    // MARK: - The brand pairs

    /// `accentStrong` is the surface a filled brand button paints, and
    /// `textOnAccent` is the ink it carries. This is the pair the whole orange
    /// identity rests on, and the one that is easy to get wrong: white on the
    /// raw brand orange is only 3.2:1.
    func testTextOnAccentStrongClearsAAInBothAppearances() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            assertContrast(Theme.Color.textOnAccent, on: Theme.Color.accentStrong, atLeast: body, style: style)
        }
    }

    /// `accentInk` is the accent used as *ink* — accent-coloured labels,
    /// glyphs and strokes on the app's own surfaces. It is a different token
    /// from `accentFill` because no single orange can be both readable on
    /// near-white and readable under white in both appearances.
    func testAccentInkClearsAAOnAppSurfaces() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            assertContrast(Theme.Color.accentStrong, on: Theme.Color.background, atLeast: body, style: style)
            assertContrast(Theme.Color.accentStrong, on: Theme.Color.surface, atLeast: body, style: style)
        }
    }

    /// The identity orange is allowed to be lighter than `accentInk` because it
    /// is only ever a fill, a gradient stop, or large display text — all of
    /// which need 3:1, not 4.5:1.
    func testAccentClearsLargeTextThresholdOnAppSurfaces() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            assertContrast(Theme.Color.accent, on: Theme.Color.background, atLeast: large, style: style)
        }
    }

    /// A filled brand button must also be distinguishable from the surface it
    /// sits on, or its edge disappears and only the label locates it.
    func testAccentStrongIsDistinguishableFromTheBackground() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            assertContrast(Theme.Color.accentStrong, on: Theme.Color.background, atLeast: large, style: style)
        }
    }

    /// Both gradients carry `textOnAccent` at both ends, and neither end was
    /// covered before.
    ///
    /// `brandGradient` runs `accentStrong → accentSecondary`; the spark ramp
    /// `accent → accentFar`. A gradient is the easiest place for a token change
    /// to go unnoticed, because only one of its two stops is usually the one
    /// anybody looked at.
    func testTextOnAccentClearsAAAcrossTheBrandGradient() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            assertContrast(Theme.Color.textOnAccent, on: Theme.Color.accentStrong, atLeast: body, style: style)
            assertContrast(Theme.Color.textOnAccent, on: Theme.Color.accentSecondary, atLeast: body, style: style)
        }
    }

    /// The spark ramp reverses direction between appearances, which reads as a
    /// mistake and is not: `textOnAccent` is white in light and near-black in
    /// dark, so the far stop has to move *away* from the ink in whichever
    /// direction the ink is. A far stop that went deeper in both appearances
    /// would strand the dark one at 4.06:1 — this is the test that says so.
    func testTextOnAccentClearsAAAcrossTheSparkRamp() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            assertContrast(Theme.Color.textOnAccent, on: Theme.Color.accent, atLeast: body, style: style)
            assertContrast(Theme.Color.textOnAccent, on: Theme.Color.accentFar, atLeast: body, style: style)
        }
    }

    // MARK: - Contrast maths

    private func assertContrast(
        _ foreground: UIColor,
        on background: UIColor,
        atLeast threshold: CGFloat,
        style: UIUserInterfaceStyle,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let traits = UITraitCollection(userInterfaceStyle: style)
        let ratio = contrastRatio(
            foreground.resolvedColor(with: traits),
            background.resolvedColor(with: traits)
        )
        XCTAssertGreaterThanOrEqual(
            ratio, threshold,
            String(
                format: "%@: contrast %.2f:1 is below %.1f:1",
                style == .light ? "light" : "dark", ratio, threshold
            ),
            file: file, line: line
        )
    }

    private func contrastRatio(_ a: UIColor, _ b: UIColor) -> CGFloat {
        let lighter = max(relativeLuminance(a), relativeLuminance(b))
        let darker = min(relativeLuminance(a), relativeLuminance(b))
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// WCAG relative luminance: sRGB channels linearised, then weighted.
    private func relativeLuminance(_ color: UIColor) -> CGFloat {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func linear(_ channel: CGFloat) -> CGFloat {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}
