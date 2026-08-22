//
//  SuccessOverlayView.swift
//  ClaudeCollage
//
//  Step 05b Part D.
//
//  Exporting is the moment the whole app exists for, and it used to end with a
//  grey capsule reading "Saved to Photos" — the same treatment as "Sticker
//  removed". This is the one place the app is allowed to celebrate.
//
//  Deliberately not a confetti burst: the user's next action is almost always to
//  leave for Instagram, so the moment has to be legible in under a second and
//  get out of the way on its own. A gradient check that springs in, holds, and
//  fades is enough to feel like an event without becoming a delay.
//

import UIKit

@MainActor
public final class SuccessOverlayView: UIView {

    public static let accessibilityID = "successOverlay"

    private let card = UIView()
    private let badge = GradientLayerButton(type: .custom)
    private let label = UILabel()

    public init(message: String) {
        super.init(frame: .zero)

        accessibilityIdentifier = Self.accessibilityID
        isUserInteractionEnabled = false
        // One element, not three: VoiceOver should hear "Saved to Photos", not
        // a card, a decorative tick and a label.
        isAccessibilityElement = true
        accessibilityLabel = message

        card.backgroundColor = Theme.Color.surfaceRaised
        card.layer.cornerRadius = Theme.Radius.xl
        card.layer.cornerCurve = .continuous
        card.applyCardShadow()
        card.translatesAutoresizingMaskIntoConstraints = false

        badge.isUserInteractionEnabled = false
        badge.tintColor = Theme.Color.textOnAccent
        badge.setImage(
            UIImage(systemName: "checkmark", withConfiguration:
                        UIImage.SymbolConfiguration(pointSize: 30, weight: .bold)),
            for: .normal
        )
        badge.layer.cornerRadius = 34
        badge.layer.cornerCurve = .continuous
        badge.useBrandGradient()
        badge.translatesAutoresizingMaskIntoConstraints = false

        label.text = message
        label.font = Theme.Typography.headline
        label.textColor = Theme.Color.textPrimary
        label.textAlignment = .center
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(card)
        card.addSubview(badge)
        card.addSubview(label)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.centerYAnchor.constraint(equalTo: centerYAnchor),
            card.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: Theme.Spacing.xxl),
            card.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Theme.Spacing.xxl),

            badge.topAnchor.constraint(equalTo: card.topAnchor, constant: Theme.Spacing.xl),
            badge.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            badge.widthAnchor.constraint(equalToConstant: 68),
            badge.heightAnchor.constraint(equalToConstant: 68),

            label.topAnchor.constraint(equalTo: badge.bottomAnchor, constant: Theme.Spacing.md),
            label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Theme.Spacing.lg),
            label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Theme.Spacing.lg),
            label.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Theme.Spacing.xl),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Springs in, holds, and removes itself.
    ///
    /// Under Reduce Motion it cross-fades instead and holds slightly longer,
    /// since a fade takes less time to read than a spring and the message would
    /// otherwise feel snatched away.
    public func present(in host: UIView, holding duration: TimeInterval = 1.1) {
        translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(self)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: host.topAnchor),
            bottomAnchor.constraint(equalTo: host.bottomAnchor),
            leadingAnchor.constraint(equalTo: host.leadingAnchor),
            trailingAnchor.constraint(equalTo: host.trailingAnchor),
        ])

        let reduced = Theme.Motion.isReduced
        alpha = 0
        card.transform = reduced ? .identity : CGAffineTransform(scaleX: 0.82, y: 0.82)

        UIView.animate(
            withDuration: Theme.Motion.duration(Theme.Motion.standard),
            delay: 0,
            usingSpringWithDamping: Theme.Motion.effectiveSpringDamping,
            initialSpringVelocity: Theme.Motion.effectiveSpringVelocity,
            options: [.allowUserInteraction]
        ) {
            self.alpha = 1
            self.card.transform = .identity
        } completion: { _ in
            UIView.animate(
                withDuration: Theme.Motion.duration(Theme.Motion.standard),
                delay: reduced ? duration + 0.3 : duration,
                options: [.allowUserInteraction]
            ) {
                self.alpha = 0
            } completion: { _ in
                self.removeFromSuperview()
            }
        }

        UIAccessibility.post(notification: .announcement, argument: accessibilityLabel)
    }
}
