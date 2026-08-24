//
//  ThemeSegmentedControl.swift
//  Caroullage
//
//  Step 05b Part B.
//
//  `UISegmentedControl` cannot be subclassed usefully, so this is a styling
//  function rather than a type. Three screens build one (Projects sort, the
//  editor's Grid/Shapes switch, the gallery's canvas preset) and all three
//  looked like stock iOS next to themed neighbours.
//

import UIKit

@MainActor
public enum ThemeSegmentedControl {

    /// Applies the app's segmented-control styling in place.
    ///
    /// The selected segment carries `accentStrong`, not `accent`: its label is
    /// body-sized, and white on the identity orange is 3.2:1 — legible as a
    /// glyph, not as text.
    public static func apply(to control: UISegmentedControl) {
        control.selectedSegmentTintColor = Theme.Color.accentStrong
        control.backgroundColor = Theme.Color.controlFill

        control.setTitleTextAttributes([
            .font: Theme.Typography.subheadline,
            .foregroundColor: Theme.Color.textSecondary,
        ], for: .normal)

        control.setTitleTextAttributes([
            .font: Theme.Typography.subheadline,
            .foregroundColor: Theme.Color.textOnAccent,
        ], for: .selected)
    }
}
