//
//  UIViewController+Popover.swift
//  Caroullage
//
//  Step 06 — anchor popover-backed presentations on iPad only.
//

import UIKit

extension UIViewController {

    /// Anchors a popover-backed presentation, but **only on iPad**.
    ///
    /// iPad presents both `.actionSheet` alerts and share sheets as popovers, and
    /// raises an exception if one is presented without location information, so
    /// the anchor is required there.
    ///
    /// On iPhone the anchor must be omitted. Measured on the iOS 26.5 simulator
    /// against a 17.0 deployment target, matching the app:
    ///
    /// - `UIAlertController(.actionSheet)`: anchored, it is laid out as an arrow
    ///   popover and its `.cancel` action is registered but **never rendered** —
    ///   the user loses the Cancel button outright.
    /// - `UIActivityViewController`: anchored, every activity still renders but
    ///   the sheet is pinned to the top of the screen over the navigation bar
    ///   instead of sitting at the bottom where it belongs.
    ///
    /// Unanchored, both present the way iPhone users expect.
    ///
    /// The anchor is supplied by the closure so each call site can pass whichever
    /// kind it uses — `sourceView`/`sourceRect`, or `barButtonItem`.
    func anchorPopover(_ presented: UIViewController,
                       _ configure: (UIPopoverPresentationController) -> Void) {
        guard traitCollection.userInterfaceIdiom == .pad,
              let popover = presented.popoverPresentationController else { return }
        configure(popover)
    }
}
