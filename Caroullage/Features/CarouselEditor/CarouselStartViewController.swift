//
//  CarouselStartViewController.swift
//  Caroullage
//
//  The host for the carousel type picker.
//
//  Step 04.5 batch C made this the Carousel tab's root: the selector WAS the tab.
//  Step 06 undid that. It left Carousel as the only tab whose root was a form
//  rather than a place, so the selector's full-width "Create" bar and the shell's
//  floating "+ Start Editing" pill sat in the same band as two filled brand CTAs
//  with nothing to say which was the action — and the tab gave finished carousels
//  nowhere to live.
//
//  The picker is now a sheet, reached from the "+" menu or from the Carousel
//  tab's empty state, and the tab itself is a gallery of the carousels you have
//  made. `CarouselTypeSelectorView` already drew a Cancel header whenever
//  `onCancel` was non-nil; until now nothing passed one.
//

import UIKit
import SwiftUI

@MainActor
final class CarouselStartViewController: UIViewController {

    /// Wired by AppCoordinator — turns the chosen config into a carousel.
    var onCreate: ((CarouselStartConfig) -> Void)?

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            // Four type cards, the frame/aspect controls and the Create bar are
            // very nearly a full screen; a medium detent would open with the
            // options already cut off.
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = Theme.Radius.xl
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.Color.background

        let selector = CarouselTypeSelectorView(
            onCreate: { [weak self] config in
                guard let self else { return }
                // Dismiss FIRST, then act. The editor is pushed onto the
                // presenting tab's navigation stack — and panoramic opens a photo
                // picker — neither of which UIKit will do from behind this sheet.
                // The handler is captured before dismissing because `self` may be
                // released by the time the completion runs.
                let handler = self.onCreate
                self.dismiss(animated: true) { handler?(config) }
            },
            onCancel: { [weak self] in self?.dismiss(animated: true) }
        )
        let host = UIHostingController(rootView: selector)
        host.view.accessibilityIdentifier = "carouselTypeSelector"
        host.view.backgroundColor = .clear

        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }
}
