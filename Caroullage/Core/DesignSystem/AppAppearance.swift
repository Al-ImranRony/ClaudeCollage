//
//  AppAppearance.swift
//  Caroullage
//
//  One-shot global UIKit appearance configuration, applied at scene setup.
//  Centralising it here means the brand tint and navigation-bar styling apply to
//  every screen automatically — including the editors added in later steps — so
//  no screen has to remember to re-theme its chrome.
//

import UIKit

@MainActor
public enum AppAppearance {

    /// Applies the app-wide tint and navigation-bar appearance. Call once, on the
    /// key window, during scene connection.
    ///
    /// The global tint is the ink, not the indigo.
    ///
    /// This is the rule the whole palette turns on: **ink is chrome, indigo is
    /// state.** Anything that is simply *there* and tappable — a bar button, a
    /// filled action, a segmented control's selected pill — takes
    /// `accentStrong`. The indigo marks which thing is currently chosen: a
    /// selected cell's stroke, the selected tab, a swatch halo, the wash under
    /// a `.tinted()` button.
    ///
    /// Splitting them the other way is what left the nav bar and the tab bar
    /// disagreeing, and it is also what makes the indigo mean something: a
    /// colour used on every bar item is decoration, and the eye stops reading
    /// it as "this one".
    public static func apply(to window: UIWindow) {
        window.tintColor = Theme.Color.accentStrong
        configureNavigationBar()
        // SwiftUI's `.pickerStyle(.segmented)` is a UISegmentedControl under the
        // hood, so theming the appearance proxy is the only way to reach the
        // pickers inside the app's SwiftUI sheets.
        ThemeSegmentedControl.apply(to: UISegmentedControl.appearance())
    }

    private static func configureNavigationBar() {
        let appearance = UINavigationBarAppearance()
        // Transparent, with `TopFadeView` behind it: an opaque bar draws a hard
        // line across the screen and flattens the depth the floating tab bar
        // just bought. Content should dissolve toward the top edge, not stop at
        // a rule.
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.shadowColor = nil

        let title = Theme.Color.textPrimary
        appearance.titleTextAttributes = [
            .foregroundColor: title,
            .font: Theme.Typography.headline,
        ]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: title,
            .font: Theme.Typography.largeTitle,
        ]

        let proxy = UINavigationBar.appearance()
        proxy.standardAppearance = appearance
        proxy.scrollEdgeAppearance = appearance
        proxy.compactAppearance = appearance
        proxy.tintColor = Theme.Color.accentStrong
    }
}
