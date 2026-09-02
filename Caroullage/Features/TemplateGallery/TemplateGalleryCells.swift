//
//  TemplateGalleryCells.swift
//  Caroullage
//
//  Step 03a — the template gallery's category filter chip.
//
//  It used to carry the 2-column template card too: a schematic thumbnail in a
//  bordered well, a name strip and a crown. Step 07 made this tab photo-real
//  and the card became `BrowseTemplateCell`, shared with the Carousel tab so
//  the app's two browse grids cannot drift apart.
//

import UIKit

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
        // A chip label is body-sized, so the selected state takes `accentStrong`
        // — `accent` on the soft-accent fill is 3.6:1, short of AA.
        label.textColor = isSelected ? Theme.Color.accentStrong : Theme.Color.textSecondary
        contentView.backgroundColor = isSelected ? Theme.Color.accentSoft : Theme.Color.controlFill
        contentView.layer.borderColor = (isSelected ? Theme.Color.accentStrong : Theme.Color.separator).cgColor
    }
}
