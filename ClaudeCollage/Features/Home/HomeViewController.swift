//
//  HomeViewController.swift
//  ClaudeCollage
//
//  Step 04.5 batch C — the discovery screen.
//
//  Home used to be the saved-project gallery with five module buttons packed into
//  its nav bar. The gallery moved to `ProjectsViewController` (its own tab) and
//  this became a landing screen: a featured template strip and large quick-start
//  tiles, so the module entry points finally get real touch targets.
//
//  "Custom Size" is deliberately absent — it lives in the floating "+" sheet
//  alongside Image and Video, so all creation-with-a-choice starts in one place.
//

import UIKit

@MainActor
final class HomeViewController: UIViewController {

    // Wired by AppCoordinator.
    var featuredTemplatesProvider: (() -> [CollageTemplate])?
    var onSelectTemplate: ((CollageTemplate) -> Void)?
    var onBrowseTemplates: (() -> Void)?
    var onNewProject: (() -> Void)?
    var onNewPolygon: (() -> Void)?
    var onNewVideoCollage: (() -> Void)?

    /// Asks for suggested layouts for the user's recent photos. Returns an empty
    /// list when access is absent or nothing is analysable.
    var suggestedLayoutsProvider: (() async -> [GridTemplate])?
    /// Current photo-library read access, and the request. Kept as closures so
    /// Home never imports PhotoKit itself.
    var photoAccessProvider: (() -> RecentPhotoProvider.Access)?
    var requestPhotoAccess: (() async -> RecentPhotoProvider.Access)?
    /// Build a collage from recent photos using the chosen layout.
    var onSelectSuggestedLayout: ((GridTemplate) -> Void)?

    private var featured: [CollageTemplate] = []
    private var suggestions: [GridTemplate] = []
    private var suggestionsSection: UIStackView?
    private lazy var suggestionsStrip = makeSuggestionsStrip()
    private lazy var enableSuggestionsButton = makeEnableSuggestionsButton()

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private lazy var featuredStrip = makeFeaturedStrip()
    private var featuredSection: UIStackView?

    override func viewDidLoad() {
        super.viewDidLoad()
        // `navigationItem.title`, NOT `title`: setting `title` on a tab root also
        // rewrites its tab bar label, so this screen would sit under a tab reading
        // "ClaudeCollage" instead of "Home".
        navigationItem.title = "ClaudeCollage"
        view.backgroundColor = Theme.Color.background
        navigationController?.navigationBar.prefersLargeTitles = true
        setupLayout()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    func reload() {
        featured = featuredTemplatesProvider?() ?? []
        featuredStrip.reloadData()
        featuredSection?.isHidden = featured.isEmpty
        refreshSuggestions()
    }

    // MARK: - Suggested layouts

    /// Shows whichever of the three states applies: an offer to enable, the
    /// suggestions themselves, or nothing at all.
    ///
    /// Deliberately does NOT prompt. Access is only requested when the user taps
    /// the button — see `RecentPhotoProvider`.
    private func refreshSuggestions() {
        let access = photoAccessProvider?() ?? .denied
        switch access {
        case .notDetermined:
            enableSuggestionsButton.isHidden = false
            suggestionsStrip.isHidden = true
            suggestionsSection?.isHidden = false
        case .denied:
            // iOS will not show the dialog again, so offering it would be a dead
            // end. The row simply goes away.
            suggestionsSection?.isHidden = true
        case .authorized:
            enableSuggestionsButton.isHidden = true
            loadSuggestions()
        }
    }

    private func loadSuggestions() {
        Task { @MainActor in
            let templates = await suggestedLayoutsProvider?() ?? []
            self.suggestions = templates
            self.suggestionsStrip.reloadData()
            self.suggestionsStrip.isHidden = templates.isEmpty
            // Nothing to suggest (no photos, or none analysable) hides the whole
            // section rather than leaving an empty labelled strip.
            self.suggestionsSection?.isHidden = templates.isEmpty
        }
    }

    private func makeSuggestionsSection() -> UIStackView {
        let header = sectionHeader("Suggested For You", actionTitle: nil, action: nil)
        let section = UIStackView(arrangedSubviews: [
            header, enableSuggestionsButton, suggestionsStrip,
        ])
        section.axis = .vertical
        section.spacing = Theme.Spacing.sm
        section.isHidden = true
        suggestionsStrip.heightAnchor.constraint(equalToConstant: 96).isActive = true
        return section
    }

    private func makeEnableSuggestionsButton() -> UIView {
        var config = UIButton.Configuration.tinted()
        config.title = "Suggest layouts from my photos"
        config.subtitle = "Reads your recent photos on this device to pick a layout."
        config.image = UIImage(systemName: "wand.and.stars")
        config.imagePadding = 8
        config.cornerStyle = .large
        config.baseBackgroundColor = Theme.Color.accent
        // The wash stays the identity orange; the label on it cannot — see
        // `Theme.Color.accentStrong`.
        config.baseForegroundColor = Theme.Color.accentStrong
        config.titleAlignment = .leading

        let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            Haptics.tap()
            self?.enableSuggestions()
        })
        button.accessibilityIdentifier = "enableSuggestionsButton"
        button.contentHorizontalAlignment = .leading

        let row = UIStackView(arrangedSubviews: [button])
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(
            top: 0, left: Theme.Spacing.md, bottom: 0, right: Theme.Spacing.md)
        return row
    }

    private func enableSuggestions() {
        Task { @MainActor in
            let access = await requestPhotoAccess?() ?? .denied
            self.refreshSuggestions()
            if access == .denied {
                self.showAccessDeniedNote()
            }
        }
    }

    private func showAccessDeniedNote() {
        let alert = UIAlertController(
            title: "Photo access is off",
            message: "Suggestions need permission to read your recent photos. "
                + "You can turn it on in Settings — everything else keeps working without it.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Not Now", style: .cancel))
        alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        })
        present(alert, animated: true)
    }

    private func makeSuggestionsStrip() -> UICollectionView {
        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)))
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .absolute(96), heightDimension: .absolute(96)),
            subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuous
        section.interGroupSpacing = Theme.Spacing.sm
        section.contentInsets = NSDirectionalEdgeInsets(
            top: 0, leading: Theme.Spacing.md, bottom: 0, trailing: Theme.Spacing.md)

        let view = UICollectionView(
            frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout(section: section))
        view.backgroundColor = .clear
        view.showsHorizontalScrollIndicator = false
        view.dataSource = self
        view.delegate = self
        view.accessibilityIdentifier = "suggestedLayoutsStrip"
        view.register(LayoutSchematicCell.self, forCellWithReuseIdentifier: LayoutSchematicCell.reuseID)
        return view
    }

    // MARK: - Layout

    private func setupLayout() {
        contentStack.axis = .vertical
        contentStack.spacing = Theme.Spacing.xl
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true

        let suggestionsSection = makeSuggestionsSection()
        self.suggestionsSection = suggestionsSection
        contentStack.addArrangedSubview(suggestionsSection)

        let featuredSection = makeFeaturedSection()
        self.featuredSection = featuredSection
        contentStack.addArrangedSubview(featuredSection)
        contentStack.addArrangedSubview(makeQuickStartSection())

        scrollView.addSubview(contentStack)
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.topAnchor, constant: Theme.Spacing.md),
            contentStack.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -Theme.Spacing.xxl),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor),
        ])
    }

    private func makeFeaturedSection() -> UIStackView {
        let header = sectionHeader("Featured Templates", actionTitle: "See All") { [weak self] in
            Haptics.tap()
            self?.onBrowseTemplates?()
        }
        let section = UIStackView(arrangedSubviews: [header, featuredStrip])
        section.axis = .vertical
        section.spacing = Theme.Spacing.sm
        featuredStrip.heightAnchor.constraint(equalToConstant: 190).isActive = true
        return section
    }

    private func makeQuickStartSection() -> UIStackView {
        let header = sectionHeader("Start Something", actionTitle: nil, action: nil)

        let grid = QuickStartTile(
            title: "Grid", subtitle: "Classic photo grid", symbol: "square.grid.2x2.fill",
            identifier: "newProjectButton"
        ) { [weak self] in
            Haptics.tap()
            self?.onNewProject?()
        }
        let polygon = QuickStartTile(
            title: "Shapes", subtitle: "Diagonal & polygon cuts", symbol: "triangle.fill",
            identifier: "polygonQuickStartButton"
        ) { [weak self] in
            Haptics.tap()
            self?.onNewPolygon?()
        }
        let video = QuickStartTile(
            title: "Video", subtitle: "Moving collage", symbol: "play.rectangle.fill",
            identifier: "videoCollageButton"
        ) { [weak self] in
            Haptics.tap()
            self?.onNewVideoCollage?()
        }

        let tiles = UIStackView(arrangedSubviews: [grid, polygon, video])
        tiles.axis = .vertical
        tiles.spacing = Theme.Spacing.sm
        tiles.isLayoutMarginsRelativeArrangement = true
        tiles.layoutMargins = UIEdgeInsets(
            top: 0, left: Theme.Spacing.md, bottom: 0, right: Theme.Spacing.md)

        let section = UIStackView(arrangedSubviews: [header, tiles])
        section.axis = .vertical
        section.spacing = Theme.Spacing.sm
        return section
    }

    private func sectionHeader(
        _ title: String, actionTitle: String?, action: (() -> Void)?
    ) -> UIStackView {
        SectionHeaderView(
            title: title,
            actionTitle: actionTitle,
            actionIdentifier: actionTitle == nil ? nil : "seeAllTemplatesButton",
            action: action
        )
    }

    private func makeFeaturedStrip() -> UICollectionView {
        let item = NSCollectionLayoutItem(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1))
        )
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .absolute(132), heightDimension: .absolute(190)),
            subitems: [item]
        )
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuous
        section.interGroupSpacing = Theme.Spacing.sm
        section.contentInsets = NSDirectionalEdgeInsets(
            top: 0, leading: Theme.Spacing.md, bottom: 0, trailing: Theme.Spacing.md)
        let layout = UICollectionViewCompositionalLayout(section: section)

        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.showsHorizontalScrollIndicator = false
        view.dataSource = self
        view.delegate = self
        view.accessibilityIdentifier = "featuredTemplateStrip"
        view.register(FeaturedTemplateCell.self, forCellWithReuseIdentifier: FeaturedTemplateCell.reuseID)
        return view
    }
}

extension HomeViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        collectionView === suggestionsStrip ? suggestions.count : featured.count
    }

    func collectionView(
        _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        if collectionView === suggestionsStrip {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: LayoutSchematicCell.reuseID, for: indexPath)
            if let schematic = cell as? LayoutSchematicCell,
               suggestions.indices.contains(indexPath.item) {
                // Reuses the editor's own layout schematic, so a suggestion looks
                // exactly like the chip the user will see once inside.
                schematic.configure(with: suggestions[indexPath.item], isSelected: false)
            }
            return cell
        }

        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: FeaturedTemplateCell.reuseID, for: indexPath)
        if let card = cell as? FeaturedTemplateCell, featured.indices.contains(indexPath.item) {
            card.configure(with: featured[indexPath.item])
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        Haptics.tap()

        if collectionView === suggestionsStrip {
            guard suggestions.indices.contains(indexPath.item) else { return }
            onSelectSuggestedLayout?(suggestions[indexPath.item])
            return
        }
        guard featured.indices.contains(indexPath.item) else { return }
        onSelectTemplate?(featured[indexPath.item])
    }
}

// MARK: - Quick-start tile

/// A full-width row: icon, title, subtitle, chevron. Deliberately large — these
/// replace nav-bar icons that were far too small to hit reliably.
private final class QuickStartTile: UIControl {

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

// MARK: - Featured template cell

final class FeaturedTemplateCell: UICollectionViewCell {
    static let reuseID = "FeaturedTemplateCell"

    private let imageView = UIImageView()
    private let nameLabel = UILabel()
    private var thumbnailTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = Theme.Color.controlFill
        imageView.layer.cornerRadius = Theme.Radius.md
        imageView.layer.cornerCurve = .continuous
        imageView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = Theme.Typography.caption
        nameLabel.textColor = Theme.Color.textSecondary
        nameLabel.numberOfLines = 1
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(imageView)
        contentView.addSubview(nameLabel)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            nameLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 6),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),
            nameLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailTask?.cancel()
        thumbnailTask = nil
        imageView.image = nil
    }

    func configure(with template: CollageTemplate) {
        nameLabel.text = template.name
        accessibilityIdentifier = "featuredTemplate-\(template.id)"
        // Thumbnails are rendered and disk-cached by TemplateService; hop off the
        // first layout pass so a cold cache never stalls the Home screen.
        thumbnailTask?.cancel()
        thumbnailTask = Task { @MainActor [weak self] in
            let rendered = TemplateService.shared.thumbnail(for: template)
            guard !Task.isCancelled else { return }
            self?.imageView.image = rendered.map { UIImage(cgImage: $0) }
        }
    }
}

// MARK: - Empty state

/// Shown by `ProjectsViewController` when nothing has been saved yet.
final class HomeEmptyStateView: UIView {
    var onCreate: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 52, weight: .regular)
        let icon = UIImageView(image: UIImage(systemName: "square.grid.2x2.fill", withConfiguration: symbolConfig))
        icon.tintColor = Theme.Color.accent
        icon.contentMode = .scaleAspectFit
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let title = UILabel()
        title.text = "No collages yet"
        title.font = Theme.Typography.title2
        title.textColor = Theme.Color.textPrimary
        title.textAlignment = .center

        let subtitle = UILabel()
        subtitle.text = "Create your first grid collage to get started."
        subtitle.font = Theme.Typography.body
        subtitle.textColor = Theme.Color.textSecondary
        subtitle.numberOfLines = 0
        subtitle.textAlignment = .center

        var config = UIButton.Configuration.filled()
        config.title = "New Collage"
        config.image = UIImage(systemName: "plus")
        config.imagePadding = 8
        config.cornerStyle = .large
        config.baseBackgroundColor = Theme.Color.accentStrong
        config.baseForegroundColor = Theme.Color.textOnAccent
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 22, bottom: 14, trailing: 22)
        config.attributedTitle = AttributedString(
            "New Collage", attributes: AttributeContainer([.font: Theme.Typography.button])
        )
        let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            Haptics.tap()
            self?.onCreate?()
        })
        button.accessibilityIdentifier = "emptyStateCreateButton"

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
        nameLabel.textColor = Theme.Color.textPrimary
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        dateLabel.font = Theme.Typography.caption
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
            UIView.animate(
                withDuration: Theme.Motion.duration(Theme.Motion.quick),
                delay: 0,
                usingSpringWithDamping: Theme.Motion.effectiveSpringDamping,
                initialSpringVelocity: Theme.Motion.effectiveSpringVelocity,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                self.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
            }
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
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        modeBadge.image = nil
    }
}
