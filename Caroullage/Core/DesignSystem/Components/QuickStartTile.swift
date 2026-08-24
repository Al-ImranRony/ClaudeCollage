//
//  QuickStartTile.swift
//  Caroullage
//
//  Step 04.5 — a full-width row: icon, title, subtitle, chevron. Deliberately
//  large; these replaced nav-bar icons that were far too small to hit reliably.
//
//  Step 05b lifted it out of `HomeViewController` so the floating "+" sheet can
//  use the same row. That is the point: "Start Something" on Home and the "+"
//  sheet offer overlapping choices, and when they were built from different
//  parts they looked like two unrelated features.
//

import UIKit

/// A full-width row: icon, title, subtitle, chevron. Deliberately large — these
/// replace nav-bar icons that were far too small to hit reliably.
@MainActor
final class QuickStartTile: UIControl {

    private let action: () -> Void

    init(title: String, subtitle: String, symbol: String, identifier: String,
         action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)

        accessibilityIdentifier = identifier
        accessibilityLabel = title
        isAccessibilityElement = true
        accessibilityTraits = .button

        backgroundColor = Theme.Color.surface
        layer.cornerRadius = Theme.Radius.lg
        layer.cornerCurve = .continuous
        applyCardShadow()

        let icon = UIImageView(image: UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold)))
        icon.tintColor = Theme.Color.accentStrong
        icon.contentMode = .center

        // The glyph sits in a soft-accent well rather than floating loose: it
        // gives the row a fixed left edge to align to, and it is what makes
        // three stacked rows read as one list instead of three unrelated cards.
        let iconWell = UIView()
        iconWell.backgroundColor = Theme.Color.accentSoft
        iconWell.layer.cornerRadius = Theme.Radius.sm
        iconWell.layer.cornerCurve = .continuous
        iconWell.setContentHuggingPriority(.required, for: .horizontal)
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconWell.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: iconWell.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconWell.centerYAnchor),
        ])

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = Theme.Typography.headline
        titleLabel.textColor = Theme.Color.textPrimary

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = Theme.Typography.caption
        subtitleLabel.textColor = Theme.Color.textSecondary

        let labels = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        labels.axis = .vertical
        labels.spacing = 2

        let chevron = UIImageView(image: UIImage(
            systemName: "chevron.right",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)))
        chevron.tintColor = Theme.Color.textSecondary
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [iconWell, labels, chevron])
        row.axis = .horizontal
        row.spacing = Theme.Spacing.sm
        row.alignment = .center
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: Theme.Spacing.md),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Theme.Spacing.md),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.Spacing.md),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.Spacing.md),
            iconWell.widthAnchor.constraint(equalToConstant: 38),
            iconWell.heightAnchor.constraint(equalToConstant: 38),
        ])

        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func tapped() {
        Haptics.tap()
        action()
    }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            UIView.animate(withDuration: Theme.Motion.duration(Theme.Motion.quick)) {
                self.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.98, y: 0.98) : .identity
                self.backgroundColor = self.isHighlighted
                    ? Theme.Color.controlFill : Theme.Color.surface
            }
        }
    }
}
