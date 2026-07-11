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
    var onOpenProject: ((UUID) -> Void)?
    var onDeleteProject: ((UUID) -> Void)?

    private var summaries: [ProjectSummary] = []
    private lazy var collectionView = makeCollectionView()
    private let emptyStateView = HomeEmptyStateView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "ClaudeCollage"
        view.backgroundColor = .systemBackground
        navigationController?.navigationBar.prefersLargeTitles = true

        let addButton = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            style: .plain, target: self, action: #selector(newTapped)
        )
        addButton.accessibilityIdentifier = "newProjectButton"
        addButton.accessibilityLabel = "New Collage"
        navigationItem.rightBarButtonItem = addButton

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
        view.backgroundColor = .systemBackground
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
        imageView.layer.cornerRadius = 14
        imageView.backgroundColor = .secondarySystemBackground
        imageView.translatesAutoresizingMaskIntoConstraints = false

        dateLabel.font = .preferredFont(forTextStyle: .caption1)
        dateLabel.textColor = .secondaryLabel
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

        let icon = UIImageView(image: UIImage(systemName: "square.grid.2x2"))
        icon.tintColor = .tertiaryLabel
        icon.contentMode = .scaleAspectFit
        icon.heightAnchor.constraint(equalToConstant: 56).isActive = true

        let title = UILabel()
        title.text = "No collages yet"
        title.font = .preferredFont(forTextStyle: .title2)
        title.textAlignment = .center

        let subtitle = UILabel()
        subtitle.text = "Create your first grid collage to get started."
        subtitle.font = .preferredFont(forTextStyle: .body)
        subtitle.textColor = .secondaryLabel
        subtitle.numberOfLines = 0
        subtitle.textAlignment = .center

        var config = UIButton.Configuration.filled()
        config.title = "New Collage"
        config.image = UIImage(systemName: "plus")
        config.imagePadding = 6
        config.cornerStyle = .large
        let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
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
