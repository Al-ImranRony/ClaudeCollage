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
    /// The selected segment carries `accentStrong` — the ink — and its label
    /// `textOnAccent`. That is the pair `ThemeContrastTests` pins, and a filled
    /// segment is chrome rather than state, so the indigo stays out of it.
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
