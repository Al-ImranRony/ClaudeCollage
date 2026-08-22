//
//  CarouselStartViewController.swift
//  ClaudeCollage
//
//  Step 04.5 batch C — the Carousel tab's root.
//
//  The carousel type selector used to be a modal presented from a Home nav-bar
//  button. Now that Carousel is a tab, the selector IS the tab: hosting it inline
//  removes a presentation step and gives the tab something to be. The SwiftUI view
//  itself is unchanged from Step 03b slice 5.
//
//  Titled "New Carousel" rather than "Carousel" so it does not collide with the
//  carousel editor's own nav-bar title.
//

import UIKit
import SwiftUI

@MainActor
final class CarouselStartViewController: UIViewController {

    /// Wired by AppCoordinator — turns the chosen config into a carousel.
    var onCreate: ((CarouselStartConfig) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        // `navigationItem.title`, NOT `title` — the latter would relabel the tab
        // "New Carousel" the first time this tab's view loaded.
        navigationItem.title = "New Carousel"
        view.backgroundColor = Theme.Color.background
        navigationController?.navigationBar.prefersLargeTitles = true

        let selector = CarouselTypeSelectorView(
            onCreate: { [weak self] config in self?.onCreate?(config) },
            // Nothing to dismiss — this is a tab root, not a sheet.
            onCancel: nil
        )
        let host = UIHostingController(rootView: selector)
        host.view.accessibilityIdentifier = "carouselTypeSelector"
        host.view.backgroundColor = .clear

        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }
}
