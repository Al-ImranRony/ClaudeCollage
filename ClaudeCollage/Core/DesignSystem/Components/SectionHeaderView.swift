//
//  SectionHeaderView.swift
//  ClaudeCollage
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
        actionTitle: String? = nil,
        actionIdentifier: String? = nil,
        action: (() -> Void)? = nil
    ) {
        super.init(frame: .zero)

        titleLabel.text = title
        titleLabel.font = Theme.Typography.title2
        titleLabel.textColor = Theme.Color.textPrimary
        titleLabel.adjustsFontForContentSizeCategory = true
        addArrangedSubview(titleLabel)

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

        axis = .horizontal
        alignment = .firstBaseline
        distribution = arrangedSubviews.count > 1 ? .equalSpacing : .fill
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
