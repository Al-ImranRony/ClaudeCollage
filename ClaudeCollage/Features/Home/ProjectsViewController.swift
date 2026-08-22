//
//  ProjectsViewController.swift
//  ClaudeCollage
//
//  Step 04.5 batch C — the saved-project gallery.
//
//  This is the Step 01 Home gallery, unchanged in behaviour and lifted out of
//  `HomeViewController` when Home became a discovery screen. The card grid, the
//  empty state, and the delete context menu are exactly as they were; only the
//  five nav-bar module buttons went away, replaced by the tab bar and the
//  floating "+".
//

import UIKit

@MainActor
final class ProjectsViewController: UIViewController {

    // Wired by AppCoordinator.
    var summariesProvider: (() -> [ProjectSummary])?
    var onNewProject: (() -> Void)?
    var onOpenProject: ((UUID) -> Void)?
    var onDeleteProject: ((UUID) -> Void)?
    var onRenameProject: ((UUID, String) -> Void)?
    var onDuplicateProject: ((UUID) -> Void)?
    var onExportProject: ((UUID) -> Void)?

    /// How the gallery is ordered. Search filters within the chosen order.
    private enum SortOrder: Int, CaseIterable {
        case recent, oldest, byMode
        var title: String {
            switch self {
            case .recent: return "Recent"
            case .oldest: return "Oldest"
            case .byMode: return "By type"
            }
        }
    }
    private var sortOrder: SortOrder = .recent
    private var searchText = ""
    private lazy var sortControl = makeSortControl()
    private let searchController = UISearchController(searchResultsController: nil)

    /// What the grid actually shows: `summaries` narrowed by search and ordered.
    private var visibleSummaries: [ProjectSummary] = []

    private var summaries: [ProjectSummary] = []
    private lazy var collectionView = makeCollectionView()
    private let emptyStateView = HomeEmptyStateView()

    override func viewDidLoad() {
        super.viewDidLoad()
        // See HomeViewController — `title` on a tab root rewrites the tab label.
        navigationItem.title = "Projects"
        view.backgroundColor = Theme.Color.background
        navigationController?.navigationBar.prefersLargeTitles = true

        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search your collages"
        searchController.searchBar.accessibilityIdentifier = "projectsSearchField"
        navigationItem.searchController = searchController
        definesPresentationContext = true

        sortControl.translatesAutoresizingMaskIntoConstraints = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.onCreate = { [weak self] in self?.onNewProject?() }

        view.addSubview(sortControl)
        view.addSubview(collectionView)
        view.addSubview(emptyStateView)
        NSLayoutConstraint.activate([
            sortControl.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Theme.Spacing.xs),
            sortControl.leadingAnchor.constraint(
                equalTo: view.leadingAnchor, constant: Theme.Spacing.md),
            sortControl.trailingAnchor.constraint(
                equalTo: view.trailingAnchor, constant: -Theme.Spacing.md),

            collectionView.topAnchor.constraint(
                equalTo: sortControl.bottomAnchor, constant: Theme.Spacing.xs),
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
        applyFilters()
    }

    /// Narrows by search text, then orders. Kept separate from `reload` so typing
    /// never re-reads the store.
    private func applyFilters() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        var filtered = summaries
        if !query.isEmpty {
            filtered = filtered.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
        }
        switch sortOrder {
        case .recent: filtered.sort { $0.updatedAt > $1.updatedAt }
        case .oldest: filtered.sort { $0.updatedAt < $1.updatedAt }
        case .byMode:
            // Grouped by type, newest first inside each group.
            filtered.sort {
                $0.mode.rawValue == $1.mode.rawValue
                    ? $0.updatedAt > $1.updatedAt
                    : $0.mode.rawValue < $1.mode.rawValue
            }
        }
        visibleSummaries = filtered
        // The masonry section is computed from `visibleSummaries`, so the layout
        // has to be thrown away too — `reloadData` alone would re-use the frames
        // computed for the previous filter.
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.reloadData()

        // The empty state is for "no projects at all". A search that matches
        // nothing is a different situation and must not invite creating one.
        let hasProjects = !summaries.isEmpty
        emptyStateView.isHidden = hasProjects
        collectionView.isHidden = !hasProjects
        sortControl.isHidden = !hasProjects
    }

    private func makeSortControl() -> UISegmentedControl {
        let control = UISegmentedControl(items: SortOrder.allCases.map(\.title))
        control.selectedSegmentIndex = 0
        control.accessibilityIdentifier = "projectsSortControl"
        ThemeSegmentedControl.apply(to: control)
        control.addTarget(self, action: #selector(sortChanged), for: .valueChanged)
        return control
    }

    @objc private func sortChanged() {
        sortOrder = SortOrder(rawValue: sortControl.selectedSegmentIndex) ?? .recent
        Haptics.selectionChanged()
        applyFilters()
        collectionView.setContentOffset(.zero, animated: false)
    }

    // MARK: - Masonry layout

    /// Room under each thumbnail for the name and date. Fixed, so captions line
    /// up across a row even though the thumbnails above them do not.
    private static let captionHeight: CGFloat = 44
    private static let cardSpacing: CGFloat = 12

    private func makeCollectionView() -> UICollectionView {
        // The section is rebuilt on every invalidation rather than configured
        // once, because a masonry section's height depends on the items it is
        // laying out — which change as the user searches and re-sorts.
        let layout = UICollectionViewCompositionalLayout { [weak self] _, environment in
            self?.makeMasonrySection(for: environment)
        }

        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = Theme.Color.background
        view.showsVerticalScrollIndicator = false
        view.dataSource = self
        view.delegate = self
        view.accessibilityIdentifier = "projectsGrid"
        view.register(ProjectCardCell.self, forCellWithReuseIdentifier: ProjectCardCell.reuseID)
        return view
    }

    private func makeMasonrySection(
        for environment: NSCollectionLayoutEnvironment
    ) -> NSCollectionLayoutSection {
        let insets = NSDirectionalEdgeInsets(
            top: Theme.Spacing.xs, leading: Theme.Spacing.md,
            bottom: Theme.Spacing.xl, trailing: Theme.Spacing.md
        )
        let width = environment.container.effectiveContentSize.width - insets.leading - insets.trailing

        let placement = MasonryLayout.frames(
            aspectRatios: visibleSummaries.map(\.thumbnailAspectRatio),
            columns: 2,
            containerWidth: width,
            spacing: Self.cardSpacing,
            captionHeight: Self.captionHeight
        )

        // A custom group is clipped to its declared size, so the height has to
        // be the measured total rather than an estimate. `max(1,…)` keeps an
        // empty gallery from declaring a zero-height group, which UIKit rejects.
        let group = NSCollectionLayoutGroup.custom(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .absolute(max(1, width)),
                heightDimension: .absolute(max(1, placement.totalHeight))
            )
        ) { _ in
            placement.frames.map(NSCollectionLayoutGroupCustomItem.init(frame:))
        }

        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = insets
        return section
    }
}

extension ProjectsViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        visibleSummaries.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ProjectCardCell.reuseID, for: indexPath)
        if let card = cell as? ProjectCardCell {
            card.configure(with: visibleSummaries[indexPath.item])
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard visibleSummaries.indices.contains(indexPath.item) else { return }
        onOpenProject?(visibleSummaries[indexPath.item].id)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard visibleSummaries.indices.contains(indexPath.item) else { return nil }
        let summary = visibleSummaries[indexPath.item]

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return UIMenu(children: []) }
            let rename = UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { _ in
                self.promptRename(for: summary)
            }
            let duplicate = UIAction(
                title: "Duplicate", image: UIImage(systemName: "plus.square.on.square")
            ) { _ in
                Haptics.success()
                self.onDuplicateProject?(summary.id)
                self.reload()
            }
            let export = UIAction(
                title: "Export", image: UIImage(systemName: "square.and.arrow.up")
            ) { _ in
                self.onExportProject?(summary.id)
            }
            let delete = UIAction(
                title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive
            ) { _ in
                self.confirmDelete(summary)
            }
            return UIMenu(children: [rename, duplicate, export, delete])
        }
    }

    /// Deleting a collage cannot be undone once the files are gone, so it asks —
    /// and names the project, so there is no doubt which one is about to go.
    private func confirmDelete(_ summary: ProjectSummary) {
        let alert = UIAlertController(
            title: "Delete \u{201C}\(summary.displayName)\u{201D}?",
            message: "This can't be undone.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            Haptics.error()
            self?.onDeleteProject?(summary.id)
            self?.reload()
        })
        present(alert, animated: true)
    }

    private func promptRename(for summary: ProjectSummary) {
        let alert = UIAlertController(title: "Rename", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = summary.name
            field.placeholder = summary.displayName
            field.autocapitalizationType = .sentences
            field.accessibilityIdentifier = "renameField"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            let name = alert?.textFields?.first?.text ?? ""
            self?.onRenameProject?(summary.id, name)
            self?.reload()
        })
        present(alert, animated: true)
    }
}


// MARK: - Search

extension ProjectsViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        searchText = searchController.searchBar.text ?? ""
        applyFilters()
    }
}
