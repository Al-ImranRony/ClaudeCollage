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

    private var featured: [CollageTemplate] = []

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
    }

    // MARK: - Layout

    private func setupLayout() {
        contentStack.axis = .vertical
        contentStack.spacing = Theme.Spacing.xl
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true

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
        let label = UILabel()
        label.text = title
        label.font = Theme.Typography.title2
        label.textColor = Theme.Color.textPrimary

        var arranged: [UIView] = [label]
        if let actionTitle, let action {
            let button = UIButton(type: .system, primaryAction: UIAction(title: actionTitle) { _ in
                action()
            })
            button.titleLabel?.font = Theme.Typography.subheadline
            button.tintColor = Theme.Color.accent
            button.accessibilityIdentifier = "seeAllTemplatesButton"
            button.setContentHuggingPriority(.required, for: .horizontal)
            arranged.append(button)
        }

        let row = UIStackView(arrangedSubviews: arranged)
        row.axis = .horizontal
        row.alignment = .firstBaseline
        row.distribution = arranged.count > 1 ? .equalSpacing : .fill
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(
            top: 0, left: Theme.Spacing.md, bottom: 0, right: Theme.Spacing.md)
        return row
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
        featured.count
    }

    func collectionView(
        _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: FeaturedTemplateCell.reuseID, for: indexPath)
        if let card = cell as? FeaturedTemplateCell, featured.indices.contains(indexPath.item) {
            card.configure(with: featured[indexPath.item])
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard featured.indices.contains(indexPath.item) else { return }
        Haptics.tap()
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

        let icon = UIImageView(image: UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)))
        icon.tintColor = Theme.Color.accent
        icon.contentMode = .scaleAspectFit
        icon.setContentHuggingPriority(.required, for: .horizontal)

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

        let row = UIStackView(arrangedSubviews: [icon, labels, chevron])
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
            icon.widthAnchor.constraint(equalToConstant: 30),
        ])

        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func tapped() { action() }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            UIView.animate(withDuration: Theme.Motion.quick) {
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
        config.baseBackgroundColor = Theme.Color.accent
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
    private let nameLabel = UILabel()
    private let dateLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = Theme.Radius.lg
        imageView.layer.cornerCurve = .continuous
        imageView.backgroundColor = Theme.Color.controlFill
        imageView.translatesAutoresizingMaskIntoConstraints = false

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
        contentView.addSubview(nameLabel)
        contentView.addSubview(dateLabel)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor),

            nameLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 6),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),

            dateLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 1),
            dateLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            dateLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
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

    func configure(with summary: ProjectSummary) {
        imageView.image = summary.thumbnail
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
    }
}
