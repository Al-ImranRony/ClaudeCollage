//
//  HomeViewController.swift
//  ClaudeCollage
//
//  Step 01 — the project gallery. Shows saved collages as thumbnail cards and
//  a "+" to start a new grid collage. UIKit UICollectionView (the SwiftUI shell
//  wrapper described in the plan is a Step 05 polish item).
//

import UIKit

@MainActor
final class HomeViewController: UIViewController {

    // Wired by AppCoordinator.
    var summariesProvider: (() -> [ProjectSummary])?
    var onNewProject: (() -> Void)?
    var onNewFreeform: ((CGSize) -> Void)?
    var onBrowseTemplates: (() -> Void)?
    var onOpenProject: ((UUID) -> Void)?
    var onDeleteProject: ((UUID) -> Void)?

    private var summaries: [ProjectSummary] = []
    private lazy var collectionView = makeCollectionView()
    private let emptyStateView = HomeEmptyStateView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "ClaudeCollage"
        view.backgroundColor = Theme.Color.background
        navigationController?.navigationBar.prefersLargeTitles = true

        let addButton = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            style: .plain, target: self, action: #selector(newTapped)
        )
        addButton.accessibilityIdentifier = "newProjectButton"
        addButton.accessibilityLabel = "New Collage"

        let templatesButton = UIBarButtonItem(
            image: UIImage(systemName: "rectangle.3.group"),
            style: .plain, target: self, action: #selector(templatesTapped)
        )
        templatesButton.accessibilityIdentifier = "templatesButton"
        templatesButton.accessibilityLabel = "Templates"

        let freeformButton = UIBarButtonItem(
            image: UIImage(systemName: "aspectratio"),
            style: .plain, target: self, action: #selector(freeformTapped)
        )
        freeformButton.accessibilityIdentifier = "freeformButton"
        freeformButton.accessibilityLabel = "Custom Size"
        navigationItem.rightBarButtonItems = [addButton, templatesButton, freeformButton]

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.onCreate = { [weak self] in self?.newTapped() }

        view.addSubview(collectionView)
        view.addSubview(emptyStateView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            emptyStateView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            emptyStateView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    func reload() {
        summaries = summariesProvider?() ?? []
        collectionView.reloadData()
        emptyStateView.isHidden = !summaries.isEmpty
        collectionView.isHidden = summaries.isEmpty
    }

    @objc private func newTapped() {
        onNewProject?()
    }

    @objc private func templatesTapped() {
        Haptics.tap()
        onBrowseTemplates?()
    }

    /// Prompts for a custom canvas size (100–4000 px) and starts a freeform collage.
    @objc private func freeformTapped() {
        Haptics.tap()
        let alert = UIAlertController(
            title: "Custom Canvas",
            message: "Enter a size in pixels (100–4000).",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "Width"
            field.text = "1080"
            field.keyboardType = .numberPad
            field.accessibilityIdentifier = "freeformWidthField"
        }
        alert.addTextField { field in
            field.placeholder = "Height"
            field.text = "1080"
            field.keyboardType = .numberPad
            field.accessibilityIdentifier = "freeformHeightField"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self, weak alert] _ in
            let width = Double(alert?.textFields?[0].text ?? "") ?? 1080
            let height = Double(alert?.textFields?[1].text ?? "") ?? 1080
            self?.onNewFreeform?(CGSize(width: width, height: height))
        })
        present(alert, animated: true)
    }

    private func makeCollectionView() -> UICollectionView {
        let item = NSCollectionLayoutItem(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.5), heightDimension: .fractionalHeight(1))
        )
        item.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .fractionalWidth(0.62)),
            subitems: [item]
        )
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 24, trailing: 12)
        let layout = UICollectionViewCompositionalLayout(section: section)

        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = Theme.Color.background
        view.dataSource = self
        view.delegate = self
        view.register(ProjectCardCell.self, forCellWithReuseIdentifier: ProjectCardCell.reuseID)
        return view
    }
}

extension HomeViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        summaries.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ProjectCardCell.reuseID, for: indexPath)
        if let card = cell as? ProjectCardCell {
            card.configure(with: summaries[indexPath.item])
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        onOpenProject?(summaries[indexPath.item].id)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        let id = summaries[indexPath.item].id
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let delete = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                self?.onDeleteProject?(id)
                self?.reload()
            }
            return UIMenu(children: [delete])
        }
    }
}

// MARK: - Card cell

final class ProjectCardCell: UICollectionViewCell {
    static let reuseID = "ProjectCardCell"

    private let imageView = UIImageView()
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

        dateLabel.font = Theme.Typography.caption
        dateLabel.textColor = Theme.Color.textSecondary
        dateLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(imageView)
        contentView.addSubview(dateLabel)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor),

            dateLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 6),
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
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        dateLabel.text = formatter.string(from: summary.updatedAt)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
    }
}

// MARK: - Empty state

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
