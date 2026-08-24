//
//  PaywallPlaceholderViewController.swift
//  Caroullage
//
//  Step 03a — a stand-in bottom sheet shown when a free user taps a premium
//  template. The real SwiftUI paywall (with live StoreKit products) is built in
//  Step 06 and replaces the body of this screen; the presentation call sites
//  stay unchanged.
//

import UIKit

@MainActor
final class PaywallPlaceholderViewController: UIViewController {

    /// The gallery's standard presentation: a medium-height grabber sheet.
    static func sheet() -> PaywallPlaceholderViewController {
        let controller = PaywallPlaceholderViewController()
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.custom { _ in 360 }]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = Theme.Radius.xl
        }
        return controller
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.Color.surface

        let iconBackdrop = GradientCircleView()
        iconBackdrop.translatesAutoresizingMaskIntoConstraints = false
        iconBackdrop.widthAnchor.constraint(equalToConstant: 72).isActive = true
        iconBackdrop.heightAnchor.constraint(equalToConstant: 72).isActive = true

        let icon = UIImageView(image: UIImage(
            systemName: "crown.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 30, weight: .semibold)
        ))
        icon.tintColor = Theme.Color.textOnAccent
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconBackdrop.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: iconBackdrop.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconBackdrop.centerYAnchor),
        ])

        let title = UILabel()
        title.text = "Premium Template"
        title.font = Theme.Typography.title2
        title.textColor = Theme.Color.textPrimary
        title.textAlignment = .center

        let message = UILabel()
        message.text = "This design is part of Caroullage Premium. Unlocking arrives with the paywall in an upcoming update."
        message.font = Theme.Typography.body
        message.textColor = Theme.Color.textSecondary
        message.numberOfLines = 0
        message.textAlignment = .center

        var config = UIButton.Configuration.filled()
        config.cornerStyle = .large
        config.baseBackgroundColor = Theme.Color.accentStrong
        config.baseForegroundColor = Theme.Color.textOnAccent
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 22, bottom: 14, trailing: 22)
        config.attributedTitle = AttributedString(
            "Got it", attributes: AttributeContainer([.font: Theme.Typography.button])
        )
        let dismissButton = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            Haptics.tap()
            self?.dismiss(animated: true)
        })
        dismissButton.accessibilityIdentifier = "paywallDismissButton"

        let stack = UIStackView(arrangedSubviews: [iconBackdrop, title, message, dismissButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = Theme.Spacing.sm
        stack.setCustomSpacing(Theme.Spacing.lg, after: message)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.Spacing.xxl),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.Spacing.xxl),
            dismissButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
        ])
    }

    /// The brand gradient in a circle, backing the crown icon.
    private final class GradientCircleView: UIView {
        override class var layerClass: AnyClass { CAGradientLayer.self }

        override init(frame: CGRect) {
            super.init(frame: frame)
            guard let gradient = layer as? CAGradientLayer else { return }
            gradient.startPoint = CGPoint(x: 0, y: 0)
            gradient.endPoint = CGPoint(x: 1, y: 1)
            refreshColours()
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: Self, _) in
                view.refreshColours()
            }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func layoutSubviews() {
            super.layoutSubviews()
            layer.cornerRadius = bounds.width / 2
        }

        private func refreshColours() {
            (layer as? CAGradientLayer)?.colors = Theme.Color.brandGradient(for: traitCollection)
        }
    }
}
