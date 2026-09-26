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

    /// Who shows the special offer after this sheet closes. Weak: it is the
    /// screen underneath, which owns this one.
    weak var offerPresenter: UIViewController?

    /// Runs when this sheet goes away, however it went — the close button, a
    /// completed purchase, or a swipe down. Onboarding uses it to know the
    /// funnel is over.
    var onDismissed: (() -> Void)?

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || presentingViewController == nil else { return }
        onDismissed?()
    }

    /// Presents the paywall as a full-height sheet. `onUnlocked` runs after the
    /// sheet has dismissed, so the caller can retry whatever the user was
    /// blocked from doing.
    static func sheet(
        service: PurchaseService = .shared,
        onUnlocked: @escaping () -> Void = {}
    ) -> PaywallHostingController {
        let model = PaywallViewModel(service: service)
        // Weak: this controller owns the root view whose callbacks capture it, so a
        // strong capture kept every sheet alive for the life of the process
        // (HostingControllerLifetimeTests).
        weak var controller: PaywallHostingController?

        let view = PaywallView(
            model: model,
            onUnlocked: { [weak model] in
                _ = model
                controller?.dismiss(animated: true, completion: onUnlocked)
            },
            onClose: { [weak model] in
                let unlocked = model?.isPremium ?? false
                // Read before dismissing: once the sheet is gone, nothing holds
                // `controller` any more.
                let presenter = controller?.offerPresenter
                controller?.dismiss(animated: true) {
                    // Someone who walked away without buying gets one discounted
                    // second chance — not every time, see SpecialOfferPolicy.
                    guard !unlocked else { return }
                    // The screen underneath: this sheet is gone by now.
                    presenter?.presentSpecialOfferIfDue(service: service, onUnlocked: onUnlocked)
                }
            }
        )

        let hosting = PaywallHostingController(rootView: view)
        controller = hosting
        hosting.view.accessibilityIdentifier = "paywallScreen"
        hosting.isModalInPresentation = false
        if let sheet = hosting.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = Theme.Radius.xl
        }
        return hosting
    }
}

public extension UIViewController {

    /// Shows the paywall for a feature the user cannot use yet. Does nothing if
    /// they are already premium — the caller's gate has the final say.
    func presentPaywall(onUnlocked: @escaping () -> Void = {}) {
        Haptics.warning()
        let paywall = PaywallHostingController.sheet(onUnlocked: onUnlocked)
        paywall.offerPresenter = self
        present(paywall, animated: true)
    }
}
