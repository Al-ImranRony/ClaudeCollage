//
//  SectionHeaderView.swift
//  Caroullage
//
//  Step 05b Part B. The one section header — title, optional trailing action.
//  Home grew a private copy of this; Projects and the template gallery each
//  wanted one and settled for a bare label instead.
//

import UIKit

@MainActor
public final class SectionHeaderView: UIStackView {

    private let titleLabel = UILabel()

    public init(
        title: String,
        titleIdentifier: String? = nil,
        badge: String? = nil,
        actionTitle: String? = nil,
        actionIdentifier: String? = nil,
        action: (() -> Void)? = nil
    ) {
        super.init(frame: .zero)

        titleLabel.text = title
        titleLabel.font = Theme.Typography.title2
        titleLabel.textColor = Theme.Color.textPrimary
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0   // wraps at accessibility sizes rather than clipping
        titleLabel.accessibilityIdentifier = titleIdentifier

        if let badge, !badge.isEmpty {
            // A small capsule beside the title — "NEW" on a collection that
            // just landed (Home retention, phase 2). The selected category
            // chip's colours, so the two marks read as one system.
            let badgeLabel = PaddedLabel()
            badgeLabel.text = badge
            badgeLabel.font = Theme.Typography.rounded(11, .bold, .caption2)
            badgeLabel.adjustsFontForContentSizeCategory = true
            badgeLabel.textColor = Theme.Color.accentStrong
            badgeLabel.backgroundColor = Theme.Color.accentSoft
            badgeLabel.layer.cornerRadius = 8
            badgeLabel.layer.cornerCurve = .continuous
            badgeLabel.clipsToBounds = true
            badgeLabel.setContentHuggingPriority(.required, for: .horizontal)
            badgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            badgeLabel.accessibilityIdentifier = titleIdentifier.map { "\($0)-badge" }

            let titleRow = UIStackView(arrangedSubviews: [titleLabel, badgeLabel])
            titleRow.axis = .horizontal
            titleRow.alignment = .center
            titleRow.spacing = Theme.Spacing.xs
            addArrangedSubview(titleRow)
        } else {
            addArrangedSubview(titleLabel)
        }

        if let actionTitle, let action {
            let button = ThemeButton(
                style: .tertiary, title: actionTitle,
                action: UIAction { _ in action() }
            )
            // The action sits on the title's baseline, so it carries no vertical
            // padding of its own; the trailing inset is dropped too so the label
            // aligns with the section's margin instead of floating inside it.
            button.configuration?.contentInsets = .zero
            button.configuration?.titleTextAttributesTransformer =
                UIConfigurationTextAttributesTransformer { incoming in
                    var outgoing = incoming
                    outgoing.font = Theme.Typography.subheadline
                    return outgoing
                }
            button.accessibilityIdentifier = actionIdentifier
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            addArrangedSubview(button)
        }

        distribution = arrangedSubviews.count > 1 ? .equalSpacing : .fill
        // Title and action side by side; at accessibility sizes the action
        // drops under the title so neither squeezes the other mid-word.
        stackVerticallyAtAccessibilitySizes(verticalAlignment: .leading, horizontalAlignment: .firstBaseline)
        isLayoutMarginsRelativeArrangement = true
        layoutMargins = UIEdgeInsets(
            top: 0, left: Theme.Spacing.md, bottom: 0, right: Theme.Spacing.md
        )
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    public var title: String? {
        get { titleLabel.text }
        set { titleLabel.text = newValue }
    }
}

/// A label with its own horizontal padding, so a capsule badge can be one
/// view rather than a label inside a container.
private final class PaddedLabel: UILabel {
    private let inset = UIEdgeInsets(top: 3, left: 7, bottom: 3, right: 7)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: inset))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + inset.left + inset.right,
                      height: size.height + inset.top + inset.bottom)
    }
}
