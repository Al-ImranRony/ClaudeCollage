//
//  CarouselStartViewController.swift
//  Caroullage
//
//  The host for the carousel type picker.
//
//  The Carousel tab has been three things, and this file has outlived two of
//  them. Step 04.5 made this selector the tab root: the wizard WAS the tab, so
//  its full-width "Create" bar and the shell's floating "+ Start Editing" pill
//  sat in the same band as two filled brand CTAs with nothing to say which was
//  the action. Step 06 made the tab a gallery of the carousels you had made and
//  this a sheet. Step 07 made the tab the carousel TEMPLATE catalog, because the
//  Step 06 gallery was the Projects grid with a filter.
//
//  Through all three the picker's job never changed: start a carousel from
//  blank. It is reached from the "+" menu's Carousel row and from the Carousel
//  tab's "New" bar button. The `NewStoryCarousel` intent is a third entry but
//  skips the picker — it already knows the type and frame count.
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
