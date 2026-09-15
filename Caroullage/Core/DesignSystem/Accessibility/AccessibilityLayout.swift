//
//  AccessibilityLayout.swift
//  Caroullage
//
//  Step 06 phase 6.5. Layout rules for accessibility text sizes, found by
//  walking the app at AX-XXXL (AccessibilityWalkthroughUITests): a row that
//  fits at body size squeezes its text mid-word at three times the size, a
//  half-height sheet shows a title and one row, and a two-column gallery
//  truncates every caption. Each rule here is Apple's own pattern — stack
//  vertically, open large, one column — applied from one place.
//

import UIKit

extension Theme.Layout {

    /// Two columns at standard text sizes, one at accessibility sizes: a
    /// caption that reads "2-Up H…" beside another card reads "2-Up
    /// Horizontal" alone.
    public static func galleryColumns(for traits: UITraitCollection) -> Int {
        traits.preferredContentSizeCategory.isAccessibilityCategory ? 1 : 2
    }

    /// Medium-and-large at standard text sizes; large only at accessibility
    /// sizes, where a medium detent holds a title and one row.
    @MainActor
    public static func sheetDetents(for traits: UITraitCollection) -> [UISheetPresentationController.Detent] {
        traits.preferredContentSizeCategory.isAccessibilityCategory ? [.large()] : [.medium(), .large()]
    }
}

extension UIStackView {

    /// Horizontal at standard text sizes, vertical at accessibility sizes —
    /// Apple's own pattern for a row that can no longer fit its text side by
    /// side. Applies now and again on every text-size change.
    ///
    /// - Parameter verticalAlignment: the alignment used when stacked.
    /// - Parameter horizontalAlignment: the alignment used in a row.
    func stackVerticallyAtAccessibilitySizes(
        verticalAlignment: UIStackView.Alignment = .leading,
        horizontalAlignment: UIStackView.Alignment = .center,
        onChange: ((Bool) -> Void)? = nil
    ) {
        let apply: (UIStackView) -> Void = { stack in
            let accessible = stack.traitCollection.preferredContentSizeCategory.isAccessibilityCategory
            stack.axis = accessible ? .vertical : .horizontal
            stack.alignment = accessible ? verticalAlignment : horizontalAlignment
            onChange?(accessible)
        }
        apply(self)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (stack: UIStackView, _) in
            apply(stack)
        }
    }
}
