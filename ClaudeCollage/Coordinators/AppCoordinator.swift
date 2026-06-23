//
//  AppCoordinator.swift
//  ClaudeCollage
//
//  Root navigation coordinator. Owns the root UINavigationController and
//  routes to the home screen. Per Step 00, this is a placeholder that
//  presents an empty UIKit view controller. Home screen lands in Step 01.
//

import UIKit

@MainActor
final class AppCoordinator {

    private let navigationController: UINavigationController

    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
    }

    func start() {
        let placeholder = PlaceholderRootViewController()
        navigationController.setViewControllers([placeholder], animated: false)
    }
}

// MARK: - Step 00 placeholder

/// Replaced by the real Home view controller in Step 01.
@MainActor
final class PlaceholderRootViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "ClaudeCollage"
        view.backgroundColor = .systemBackground

        let label = UILabel()
        label.text = "Step 00 — Project Setup ✓\nHome screen lands in Step 01."
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .title3)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
    }
}
