//
//  SpecialOfferHostingController.swift
//  Caroullage
//
//  Step 06 phase 6.2b — presenting the special offer.
//
//  It follows a dismissed paywall, gated by `SpecialOfferPolicy` so a discount
//  that is supposed to feel like a second chance does not turn up every time.
//

import SwiftUI
import UIKit

@MainActor
final class SpecialOfferHostingController: UIHostingController<SpecialOfferView> {

    static func sheet(
        service: PurchaseService = .shared,
        onUnlocked: @escaping () -> Void = {}
    ) -> SpecialOfferHostingController {
        let model = SpecialOfferViewModel(service: service)
        var controller: SpecialOfferHostingController!

        let view = SpecialOfferView(
            model: model,
            onUnlocked: { controller?.dismiss(animated: true, completion: onUnlocked) },
            onClose: { controller?.dismiss(animated: true) }
        )

        controller = SpecialOfferHostingController(rootView: view)
        controller.view.accessibilityIdentifier = "specialOfferScreen"
        controller.modalPresentationStyle = .fullScreen
        return controller
    }
}

public extension UIViewController {

    /// Shows the discounted offer if the user is free and has not been shown one
    /// recently. Returns whether it was presented.
    @discardableResult
    func presentSpecialOfferIfDue(
        service: PurchaseService = .shared,
        policy: SpecialOfferPolicy = SpecialOfferPolicy(),
        onUnlocked: @escaping () -> Void = {}
    ) -> Bool {
        guard policy.shouldPresent(tier: service.currentTier) else { return false }
        guard service.info(for: .yearlyOffer) != nil else { return false }

        policy.recordPresented()
        present(SpecialOfferHostingController.sheet(service: service, onUnlocked: onUnlocked), animated: true)
        return true
    }
}
