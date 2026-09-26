//
//  QuickStartChip.swift
//  Caroullage
//
//  Home's quick-start chip. Split out of HomeViewController.swift; internal
//  only so Home, in the other file, can build it.
//

import UIKit

// MARK: - Quick-start chip

/// One compact door into a format: glyph, word, pill.
///
/// The full-width `QuickStartTile` still exists and is still right where it is
/// used — the "+" sheet, where the choice IS the screen. On a showcase Home the
/// same four rows took half the page to say what four chips say in one line.
@MainActor
final class QuickStartChip: UIControl {

    private let action: () -> Void

    init(title: String, caption: String, symbol: String, identifier: String, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)

        accessibilityIdentifier = identifier
        accessibilityLabel = title
        // The format hint is spoken as the hint, not folded into the name, so
        // a test (and a user) still finds the door by the word on it.
        accessibilityHint = caption
        isAccessibilityElement = true
        accessibilityTraits = .button

        backgroundColor = Theme.Color.controlFill
        layer.cornerRadius = Theme.Radius.md
        layer.cornerCurve = .continuous

        let icon = UIImageView(image: UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)))
        icon.tintColor = Theme.Color.accentStrong
        icon.contentMode = .center

        let label = UILabel()
        label.text = title
        label.font = Theme.Typography.caption
        label.textColor = Theme.Color.textPrimary
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = true
        // A quarter of the width, four times over: "Carousel" is the longest word
        // and the tightest fit, so it is allowed to shrink a little before it
        // truncates.
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8

        // The format under the word (Home retention, phase 4): "Shapes" meant
        // nothing to a first-run user, and the apps this one is measured
        // against name their doors by destination. Caption-sized and secondary,
        // so the word still leads. Its ~15pt is paid for by the hero — see
        // `heroAspectRatio`.
        let captionLabel = UILabel()
        captionLabel.text = caption
        captionLabel.font = Theme.Typography.rounded(11, .medium, .caption2)
        captionLabel.textColor = Theme.Color.textSecondary
        captionLabel.textAlignment = .center
        captionLabel.adjustsFontForContentSizeCategory = true
        captionLabel.adjustsFontSizeToFitWidth = true
        captionLabel.minimumScaleFactor = 0.8

        let stack = UIStackView(arrangedSubviews: [icon, label, captionLabel])
        stack.axis = .vertical
        stack.spacing = Theme.Spacing.xxs
        stack.setCustomSpacing(1, after: label)
        stack.alignment = .center
        // The chip owns the touch; nothing inside it may intercept one.
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: Theme.Spacing.sm),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Theme.Spacing.sm),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.Spacing.xs),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.Spacing.xs),
        ])

        addTarget(self, action: #selector(fire), for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            setPressed(isHighlighted, scale: 0.94)
        }
    }

    @objc private func fire() { action() }
}
