//
//  CarouselFrameCell.swift
//  ClaudeCollage
//
//  Step 03b slice 4b — one card in the carousel frame navigator: the frame's
//  rendered thumbnail, its 1-based number, and a selection ring for the frame the
//  editor last opened.
//

import UIKit

final class CarouselFrameCell: UICollectionViewCell {

    static let reuseID = "CarouselFrameCell"

    private let imageView = UIImageView()
    private let numberBadge = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.backgroundColor = Theme.Color.surface
        contentView.layer.cornerRadius = Theme.Radius.md
        contentView.clipsToBounds = true
        contentView.layer.borderColor = Theme.Color.accent.cgColor

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = Theme.Color.controlFill
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        numberBadge.font = Theme.Typography.caption
        numberBadge.textColor = Theme.Color.textOnAccent
        numberBadge.textAlignment = .center
        numberBadge.backgroundColor = Theme.Color.accent.withAlphaComponent(0.9)
        numberBadge.layer.cornerRadius = 11
        numberBadge.clipsToBounds = true
        numberBadge.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(numberBadge)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            numberBadge.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            numberBadge.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            numberBadge.heightAnchor.constraint(equalToConstant: 22),
            numberBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 22),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
    }

    func configure(number: Int, image: UIImage?, isSelected: Bool) {
        imageView.image = image
        numberBadge.text = "  \(number)  "
        contentView.layer.borderWidth = isSelected ? 3 : 0
        isAccessibilityElement = true
        accessibilityLabel = "Frame \(number)"
    }
}
