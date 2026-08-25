//
//  OnboardingHostingController.swift
//  Caroullage
//
//  Step 06 phase 6.3 — hosting the funnel.
//
//  It owns the last beat as well as the slides: reaching the paywall presents
//  Phase 6.2's screen over the funnel, and *however* that ends — bought, closed,
//  or skipped past — onboarding is marked seen and the app drops into Home on
//  the free tier. No relaunch, and no second run of the funnel.
//

import SwiftUI
import UIKit

@MainActor
final class OnboardingHostingController: UIHostingController<OnboardingView> {

    private let model: OnboardingViewModel
    private var didPresentPaywall = false

    /// Runs once the funnel is over, whatever the outcome.
    var onFinished: () -> Void = {}
    /// Supplies the user's own photos for the preview beat.
    var recentPhotosProvider: () async -> [CGImage] = { [] }

    static func make(
        model: OnboardingViewModel = OnboardingViewModel(),
        requestPhotoAccess: @escaping () async -> RecentPhotoProvider.Access
    ) -> OnboardingHostingController {
        var controller: OnboardingHostingController!
        let view = OnboardingView(
            model: model,
            onReachedPaywall: { controller?.presentPaywall() },
            requestPhotoAccess: requestPhotoAccess
        )
        controller = OnboardingHostingController(model: model, rootView: view)
        controller.view.accessibilityIdentifier = "onboardingScreen"
        controller.modalPresentationStyle = .fullScreen
        controller.isModalInPresentation = true
        return controller
    }

    private init(model: OnboardingViewModel, rootView: OnboardingView) {
        self.model = model
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Load the preview photos in the background so the beat that shows them
        // is not waiting on PhotoKit when it arrives.
        Task { [weak self] in
            guard let self else { return }
            let photos = await self.recentPhotosProvider()
            self.model.setPreviewPhotos(photos)
        }
    }

    private func presentPaywall() {
        guard !didPresentPaywall else { return }
        didPresentPaywall = true

        let paywall = PaywallHostingController.sheet()
        // `offerPresenter` is deliberately left unset: the exit-intent discount
        // belongs to a user who came back to the paywall later, not to someone
        // who has been in the funnel for the last minute.
        //
        // Whichever way the sheet goes — bought, closed, or swiped away — the
        // funnel is finished with them and the app opens on the free tier.
        paywall.onDismissed = { [weak self] in self?.complete() }
        present(paywall, animated: true)
    }

    private func complete() {
        model.finish()
        dismiss(animated: true) { [weak self] in
            self?.onFinished()
        }
    }
}
