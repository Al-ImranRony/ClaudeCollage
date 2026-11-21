//
//  CollageShelfHeaderView.swift
//  Caroullage
//
//  2026-11-21 — a Collage-tab shelf's title, its one-line hook, and "See All".
//
//  The hook line is the half of the header that sells: "Instant & Booth" names
//  a style, "Prints, strips and taped snapshots" tells you what you would make
//  with it. Same voice as Home's strip subtitles, so the two tabs speak alike.
//
//  Its identifiers use the `collageShelf` prefix and never `sectionHeader-`:
//  Home's UI suites count section titles by that prefix.
//

import UIKit

@MainActor
final class CollageShelfHeaderView: UICollectionReusableView {

    var onSeeAll: (() -> Void)?

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let seeAllButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)

        titleLabel.font = Theme.Typography.title2
        titleLabel.textColor = Theme.Color.textPrimary
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        titleLabel.accessibilityTraits = .header

        subtitleLabel.font = Theme.Typography.subheadline
        subtitleLabel.textColor = Theme.Color.textSecondary
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.numberOfLines = 0

        var config = UIButton.Configuration.plain()
        config.title = String(localized: "See All")
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 0)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = Theme.Typography.subheadline
            return attributes
        }
        seeAllButton.configuration = config
        seeAllButton.tintColor = Theme.Color.accentStrong
        seeAllButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        seeAllButton.setContentHuggingPriority(.required, for: .horizontal)
        seeAllButton.addAction(UIAction { [weak self] _ in
            Haptics.selectionChanged()
            self?.onSeeAll?()
        }, for: .touchUpInside)

        let text = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        text.axis = .vertical
        text.spacing = 2
        for view in [text, seeAllButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            text.topAnchor.constraint(equalTo: topAnchor),
            text.leadingAnchor.constraint(equalTo: leadingAnchor),
            text.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Theme.Spacing.sm),
            seeAllButton.leadingAnchor.constraint(greaterThanOrEqualTo: text.trailingAnchor, constant: Theme.Spacing.xs),
            seeAllButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            seeAllButton.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),
            seeAllButton.heightAnchor.constraint(greaterThanOrEqualToConstant: Theme.Layout.minimumHitTarget),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(title: String, subtitle: String?, identifier: String, showsSeeAll: Bool) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil
        titleLabel.accessibilityIdentifier = "collageShelfTitle-\(identifier)"
        seeAllButton.isHidden = !showsSeeAll
        seeAllButton.accessibilityIdentifier = "collageShelfSeeAll-\(identifier)"
        seeAllButton.accessibilityLabel = String(localized: "See all \(title)")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onSeeAll = nil
        titleLabel.accessibilityIdentifier = nil
        seeAllButton.accessibilityIdentifier = nil
    }
}
