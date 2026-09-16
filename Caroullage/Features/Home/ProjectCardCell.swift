//
//  ProjectCardCell.swift
//  Caroullage
//
//  The Projects tab's card and its empty state. Both lived at the bottom of
//  HomeViewController.swift from Step 04.5, when Home was the projects grid;
//  Home has not shown a project since Step 07, and phase 2 of the retention
//  work gives it a "Continue editing" strip that uses this cell again — so
//  the cell now lives where both screens can find it (Home retention, phase 1).
//

import UIKit

// MARK: - Empty state

/// Shown by `ProjectsViewController` when nothing has been saved yet.
///
/// The words come in rather than being baked in because Step 06 ran this panel
/// on two tabs, where "No collages yet" would have been wrong on the Carousel
/// one — you may well have collages, just no carousels. Step 07 gave that tab
/// to the carousel template catalog, which is bundled and so never empty, and
/// only `.projects` remains. The seam is kept for the same reason the gallery's
/// `Configuration` is.
final class HomeEmptyStateView: UIView {

    struct Content {
        let symbol: String
        let title: String
        let subtitle: String
        let buttonTitle: String
        let buttonIdentifier: String

        static let projects = Content(
            symbol: "square.grid.2x2.fill",
            title: String(localized: "No collages yet"),
            subtitle: String(localized: "Create your first grid collage to get started."),
            buttonTitle: String(localized: "New Collage"),
            buttonIdentifier: "emptyStateCreateButton")
    }

    var onCreate: (() -> Void)?

    init(content: Content = .projects) {
        super.init(frame: .zero)

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 52, weight: .regular)
        let icon = UIImageView(image: UIImage(systemName: content.symbol, withConfiguration: symbolConfig))
        icon.tintColor = Theme.Color.accent
        icon.contentMode = .scaleAspectFit
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let title = UILabel()
        title.text = content.title
        title.font = Theme.Typography.title2
        title.adjustsFontForContentSizeCategory = true
        title.textColor = Theme.Color.textPrimary
        title.textAlignment = .center

        let subtitle = UILabel()
        subtitle.text = content.subtitle
        subtitle.font = Theme.Typography.body
        subtitle.adjustsFontForContentSizeCategory = true
        subtitle.textColor = Theme.Color.textSecondary
        subtitle.numberOfLines = 0
        subtitle.textAlignment = .center

        var config = UIButton.Configuration.filled()
        config.title = content.buttonTitle
        config.image = UIImage(systemName: "plus")
        config.imagePadding = 8
        config.cornerStyle = .large
        config.baseBackgroundColor = Theme.Color.accentStrong
        config.baseForegroundColor = Theme.Color.textOnAccent
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 22, bottom: 14, trailing: 22)
        config.attributedTitle = AttributedString(
            content.buttonTitle, attributes: AttributeContainer([.font: Theme.Typography.button])
        )
        let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            Haptics.tap()
            self?.onCreate?()
        })
        button.accessibilityIdentifier = content.buttonIdentifier

        let stack = UIStackView(arrangedSubviews: [icon, title, subtitle, button])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.setCustomSpacing(20, after: subtitle)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Card cell

final class ProjectCardCell: UICollectionViewCell {
    static let reuseID = "ProjectCardCell"

    private let imageView = UIImageView()
    private let modeBadge = UIImageView()
    private let nameLabel = UILabel()
    private let dateLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = Theme.Radius.lg
        imageView.layer.cornerCurve = .continuous
        // The same well the canvas and the export renderer paint, so a project
        // with empty cells looks like itself here too.
        imageView.backgroundColor = Theme.Color.cellWell
        imageView.translatesAutoresizingMaskIntoConstraints = false

        // A masonry grid mixes square grids, 9:16 carousels and video side by
        // side, so the card says which is which instead of leaving the shape to
        // imply it.
        modeBadge.contentMode = .center
        modeBadge.tintColor = Theme.Color.textOnAccent
        modeBadge.backgroundColor = Theme.Color.accentStrong
        modeBadge.layer.cornerRadius = 13
        modeBadge.layer.cornerCurve = .continuous
        modeBadge.clipsToBounds = true
        modeBadge.translatesAutoresizingMaskIntoConstraints = false

        // Soft elevation sits on the (non-clipping) contentView, behind the
        // rounded image. The shadow path is set in layoutSubviews.
        contentView.applyCardShadow()

        nameLabel.font = Theme.Typography.subheadline
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.textColor = Theme.Color.textPrimary
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        dateLabel.font = Theme.Typography.caption
        dateLabel.adjustsFontForContentSizeCategory = true
        dateLabel.textColor = Theme.Color.textSecondary
        dateLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(imageView)
        contentView.addSubview(modeBadge)
        contentView.addSubview(nameLabel)
        contentView.addSubview(dateLabel)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            // No fixed aspect: the masonry layout decides the card's height and
            // the thumbnail takes whatever is left above the caption. A square
            // constraint here would fight it and win, since it is the stronger
            // of the two.
            imageView.bottomAnchor.constraint(
                equalTo: nameLabel.topAnchor, constant: -Theme.Spacing.xs),

            modeBadge.topAnchor.constraint(equalTo: imageView.topAnchor, constant: Theme.Spacing.xs),
            modeBadge.leadingAnchor.constraint(
                equalTo: imageView.leadingAnchor, constant: Theme.Spacing.xs),
            modeBadge.widthAnchor.constraint(equalToConstant: 26),
            modeBadge.heightAnchor.constraint(equalToConstant: 26),

            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),

            dateLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 1),
            dateLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            dateLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            // Equality, not `lessThanOrEqualTo`: the caption block is what pins
            // the bottom of the stack, and with only an inequality the whole
            // chain is satisfiable by collapsing the thumbnail to zero height
            // and parking the labels at the top — which is exactly what it did.
            dateLabel.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor, constant: -2),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentView.layer.shadowPath = UIBezierPath(
            roundedRect: imageView.frame, cornerRadius: Theme.Radius.lg
        ).cgPath
    }

    /// A subtle scale-down while the card is pressed, springing back on release.
    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            setPressed(isHighlighted, scale: 0.96)
        }
    }

    func configure(with summary: ProjectSummary) {
        imageView.image = summary.thumbnail
        modeBadge.image = UIImage(
            systemName: summary.mode.badgeSymbolName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        )
        // Name first, date second: once projects are nameable and searchable, the
        // name is what identifies a card.
        nameLabel.text = summary.displayName
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        dateLabel.text = "\(summary.mode.displayName) · \(formatter.string(from: summary.updatedAt))"
        accessibilityLabel = summary.displayName
        // The kind is on the card as a badge glyph, which no assistive technology
        // and no test can read. Naming it here is what lets the Carousel tab be
        // checked for what it is filtering rather than for how many cards fit.
        accessibilityIdentifier = "projectCard-\(summary.mode.rawValue)"
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        modeBadge.image = nil
    }
}
