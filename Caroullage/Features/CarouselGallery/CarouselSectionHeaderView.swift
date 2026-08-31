//
//  CarouselSectionHeaderView.swift
//  Caroullage
//
//  Step 07 — "Panoramic ›" above a block of the Carousel gallery.
//
//  The chevron does NOT push. It selects that type's chip, which collapses the
//  screen to that one section. Pushing would give the app two places that show
//  the same list and a back button between them; selecting keeps the tab a
//  single screen and means the header and the chip row can never disagree about
//  what is on display.
//

import UIKit

@MainActor
final class CarouselSectionHeaderView: UICollectionReusableView {
    static let reuseID = "CarouselSectionHeaderView"

    /// Tapped the title or the chevron — the whole row is the target, because a
    /// bare chevron is a 12pt tap target.
    var onTap: (() -> Void)?

    private let titleLabel = UILabel()
    private let button = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)

        titleLabel.font = Theme.Typography.title2
        titleLabel.textColor = Theme.Color.textPrimary
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        button.tintColor = Theme.Color.textSecondary
        button.setImage(
            UIImage(systemName: "chevron.right",
                    withConfiguration: UIImage.SymbolConfiguration(
                        pointSize: 14, weight: .semibold)),
            for: .normal)
        button.addTarget(self, action: #selector(tapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(button)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            button.leadingAnchor.constraint(
                greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: Theme.Spacing.xs),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
            button.heightAnchor.constraint(equalToConstant: 44),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(title: String, identifier: String) {
        titleLabel.text = title
        button.accessibilityIdentifier = identifier
        button.accessibilityLabel = String(localized: "See all \(title) carousels")
    }

    @objc private func tapped() {
        Haptics.selectionChanged()
        onTap?()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        onTap = nil
    }
}
