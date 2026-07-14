//
//  TemplateGalleryCells.swift
//  ClaudeCollage
//
//  Step 03a — the template gallery's cells: the 2-column template card
//  (thumbnail + name + premium crown) and the category filter chip.
//

import UIKit

// MARK: - Template card

final class TemplateCardCell: UICollectionViewCell {

    /// Vertical room reserved under the thumbnail for the name label; the
    /// gallery layout adds this to the preset-driven thumbnail height.
    static let labelStripHeight: CGFloat = 26

    private let thumbnailView = UIImageView()
    private let nameLabel = UILabel()
    private let crownBadge = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.layer.cornerRadius = Theme.Radius.md
        thumbnailView.layer.cornerCurve = .continuous
        thumbnailView.layer.borderWidth = 1
        thumbnailView.layer.borderColor = Theme.Color.separator.cgColor
        thumbnailView.backgroundColor = Theme.Color.controlFill

        contentView.applyCardShadow()

        nameLabel.font = Theme.Typography.caption
        nameLabel.textColor = Theme.Color.textPrimary
        nameLabel.lineBreakMode = .byTruncatingTail

        // Crown pill floating on the thumbnail's top-right corner.
        crownBadge.image = UIImage(
            systemName: "crown.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        )
        crownBadge.tintColor = Theme.Color.textOnAccent
        crownBadge.contentMode = .center
        crownBadge.backgroundColor = Theme.Color.accent
        crownBadge.layer.cornerRadius = 11
        crownBadge.layer.cornerCurve = .continuous
        crownBadge.isHidden = true

        for subview in [thumbnailView, nameLabel, crownBadge] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            thumbnailView.topAnchor.constraint(equalTo: contentView.topAnchor),
            thumbnailView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            thumbnailView.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor, constant: -Self.labelStripHeight),

            nameLabel.topAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: 6),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),

            crownBadge.topAnchor.constraint(equalTo: thumbnailView.topAnchor, constant: Theme.Spacing.xs),
            crownBadge.trailingAnchor.constraint(
                equalTo: thumbnailView.trailingAnchor, constant: -Theme.Spacing.xs),
            crownBadge.widthAnchor.constraint(equalToConstant: 30),
            crownBadge.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentView.layer.shadowPath = UIBezierPath(
            roundedRect: thumbnailView.frame, cornerRadius: Theme.Radius.md
        ).cgPath
    }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            UIView.animate(
                withDuration: Theme.Motion.quick,
                delay: 0,
                usingSpringWithDamping: Theme.Motion.springDamping,
                initialSpringVelocity: Theme.Motion.springVelocity,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                self.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
            }
        }
    }

    func configure(name: String, thumbnail: CGImage?, isPremium: Bool) {
        nameLabel.text = name
        thumbnailView.image = thumbnail.map(UIImage.init(cgImage:))
        crownBadge.isHidden = !isPremium
        accessibilityLabel = isPremium ? "\(name), premium template" : name
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailView.image = nil
        crownBadge.isHidden = true
    }
}

// MARK: - Category chip

final class CategoryChipCell: UICollectionViewCell {
    static let reuseID = "CategoryChipCell"

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 16
        contentView.layer.cornerCurve = .continuous
        contentView.layer.borderWidth = 1.5
        contentView.clipsToBounds = true

        label.font = Theme.Typography.subheadline
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Theme.Spacing.sm),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Theme.Spacing.sm),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(title: String, isSelected: Bool) {
        label.text = title
        label.textColor = isSelected ? Theme.Color.accent : Theme.Color.textSecondary
        contentView.backgroundColor = isSelected ? Theme.Color.accentSoft : Theme.Color.controlFill
        contentView.layer.borderColor = (isSelected ? Theme.Color.accent : Theme.Color.separator).cgColor
    }
}
