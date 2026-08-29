//
//  HomeNavBarViews.swift
//  Caroullage
//
//  Step 07 — Home's header.
//
//  Losing the large title bought the second pillar its room back, but it left
//  the top of the app reading as a system screen label: a small centred word
//  over a transparent bar. This is the front door of a creative app, and it
//  should say whose app it is and what the app sells.
//
//  Two pieces, both leaning on what the design system already has: the brand
//  lockup (the icon's own mark and glyph, so the icon, the onboarding splash
//  and the header agree), and the Pro button, which carries the brand gradient
//  `GradientLayerButton` already knows how to paint and opens the paywall.
//

import UIKit

// MARK: - Brand mark

/// The app's mark: the icon's glyph on the icon's gradient.
///
/// The gradient is the view's BACKING layer rather than a sublayer — the same
/// reason `GradientLayerButton` exists. A sublayer would sit above the image
/// view added after it and swallow the glyph.
@MainActor
final class BrandMarkView: UIView {

    override class var layerClass: AnyClass { CAGradientLayer.self }

    private let glyph = UIImageView()

    init(side: CGFloat = 30) {
        super.init(frame: .zero)

        let gradient = layer as? CAGradientLayer
        gradient?.startPoint = CGPoint(x: 0, y: 0)
        gradient?.endPoint = CGPoint(x: 1, y: 1)
        repaint()
        // CGColors are resolved, not dynamic: without this the mark keeps its
        // light-mode ramp after a switch to dark.
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: Self, _) in
            view.repaint()
        }

        // A squircle, not a circle: it echoes the app icon's own shape.
        layer.cornerRadius = side * 0.28
        layer.cornerCurve = .continuous

        glyph.image = UIImage(
            systemName: "square.stack.3d.up.fill",
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: side * 0.5, weight: .semibold))
        // The mark's ink is the same token every filled accent surface uses, so
        // it stays legible when the gradient flips ends in dark mode.
        glyph.tintColor = Theme.Color.textOnAccent
        glyph.contentMode = .center
        glyph.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyph)

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: side),
            heightAnchor.constraint(equalToConstant: side),
            glyph.centerXAnchor.constraint(equalTo: centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func repaint() {
        (layer as? CAGradientLayer)?.colors = Theme.Color.brandGradient(for: traitCollection)
    }
}

// MARK: - Brand lockup

/// Mark plus wordmark, for the navigation bar's leading side.
///
/// Read as one element by assistive technology: two labels ("Caroullage", and
/// an unnamed image) would make the app's own name arrive twice.
@MainActor
final class BrandLockupView: UIView {

    init(title: String) {
        super.init(frame: .zero)

        let wordmark = UILabel()
        wordmark.text = title
        wordmark.font = Theme.Typography.title2
        wordmark.textColor = Theme.Color.textPrimary
        wordmark.adjustsFontForContentSizeCategory = true

        let stack = UIStackView(arrangedSubviews: [BrandMarkView(), wordmark])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = Theme.Spacing.xs
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .header
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Pro button

/// The paywall's entry point from the app's front door.
///
/// Gradient-filled rather than tinted: this is the one control in the bar that
/// is asking for something, and it has to win against a screen of photography
/// without shouting over the content below it.
///
/// It is not shown at all once premium is unlocked — a "Pro" button that leads
/// to a paywall you have already paid is a dead end, and the tiny gain of a
/// status badge is not worth a permanent CTA in the header.
@MainActor
final class ProBadgeButton: GradientLayerButton {

    private let action: () -> Void

    init(title: String, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)

        var config = UIButton.Configuration.filled()
        config.title = title
        config.image = UIImage(
            systemName: "sparkles",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold))
        config.imagePadding = 5
        config.attributedTitle = AttributedString(
            title, attributes: AttributeContainer([.font: Theme.Typography.caption]))
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 7, leading: 12, bottom: 7, trailing: 13)
        // The gradient is the backing layer, so the button's own background must
        // not paint over it.
        config.background.backgroundColor = .clear
        config.baseForegroundColor = Theme.Color.textOnAccent
        // `.capsule` states the intent once and survives re-layout; a manual
        // cornerRadius on a configured button is overwritten by its own updates.
        config.cornerStyle = .capsule
        configuration = config

        useBrandGradient()
        layer.cornerCurve = .circular

        addAction(UIAction { [weak self] _ in
            Haptics.tap()
            self?.action()
        }, for: .touchUpInside)
        addTarget(self, action: #selector(pressDown), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(pressUp),
                  for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])

        accessibilityIdentifier = "homeProButton"
        accessibilityLabel = title
        accessibilityHint = String(localized: "Unlocks every template, export and tool.")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // A capsule's radius is half its height, and the backing layer is ours
        // to round — `.capsule` shapes the configuration's background, which is
        // clear here so the gradient can show.
        layer.cornerRadius = bounds.height / 2
    }

    /// The same press spring every card in the app uses, so the header answers
    /// the touch the way the content does.
    @objc private func pressDown() {
        UIView.animate(
            withDuration: Theme.Motion.duration(Theme.Motion.quick), delay: 0,
            usingSpringWithDamping: Theme.Motion.effectiveSpringDamping,
            initialSpringVelocity: Theme.Motion.effectiveSpringVelocity,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        }
    }

    @objc private func pressUp() {
        UIView.animate(
            withDuration: Theme.Motion.duration(Theme.Motion.quick), delay: 0,
            usingSpringWithDamping: Theme.Motion.effectiveSpringDamping,
            initialSpringVelocity: Theme.Motion.effectiveSpringVelocity,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.transform = .identity
        }
    }
}
