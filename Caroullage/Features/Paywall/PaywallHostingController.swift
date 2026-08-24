//
//  PaywallHostingController.swift
//  Caroullage
//
//  Step 06 phase 6.2 — the one way the app shows the paywall.
//
//  Every premium gate in the editors is UIKit, so the SwiftUI paywall is
//  presented through this wrapper. It replaces `PaywallPlaceholderViewController`
//  at the call sites that stood in for it since Step 03a.
//

import SwiftUI
import UIKit

@MainActor
final class PaywallHostingController: UIHostingController<PaywallView> {

    /// Presents the paywall as a full-height sheet. `onUnlocked` runs after the
    /// sheet has dismissed, so the caller can retry whatever the user was
    /// blocked from doing.
    static func sheet(
        service: PurchaseService = .shared,
        onUnlocked: @escaping () -> Void = {}
    ) -> PaywallHostingController {
        let model = PaywallViewModel(service: service)
        var controller: PaywallHostingController!

        let view = PaywallView(
            model: model,
            onUnlocked: { [weak model] in
                _ = model
                controller?.dismiss(animated: true, completion: onUnlocked)
            },
            onClose: { controller?.dismiss(animated: true) }
        )

        controller = PaywallHostingController(rootView: view)
        controller.view.accessibilityIdentifier = "paywallScreen"
        controller.isModalInPresentation = false
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = Theme.Radius.xl
        }
        return controller
    }
}

public extension UIViewController {

    /// Shows the paywall for a feature the user cannot use yet. Does nothing if
    /// they are already premium — the caller's gate has the final say.
    func presentPaywall(onUnlocked: @escaping () -> Void = {}) {
        Haptics.warning()
        present(PaywallHostingController.sheet(onUnlocked: onUnlocked), animated: true)
    }
}
