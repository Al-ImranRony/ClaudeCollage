//
//  TemplateGalleryViewController.swift
//  Caroullage
//
//  The Collage tab.
//
//  2026-11-21 — re-imagined as a curated magazine. It was one uniform grid
//  behind a HARD ratio filter: the tab opened on Square, so two thirds of the
//  catalog was invisible until you found a menu, and every card was the same
//  shape. Top collage apps sell their catalogs as named styles — instant
//  prints, film, editorial, photo dumps — on shelves you browse sideways, and
//  narrow by the question users actually ask: how many photos do I have?
//
//  So, two modes (decided by `CollageGalleryPlanner`, a pure function):
//
//  - Browsing: a paged spotlight of fresh free templates, themed shelves at
//    their true proportions, then the whole catalog in a masonry grid.
//  - Finding: any chip, filter or search collapses it to one masonry grid of
//    matches. Ratio became an optional filter ("Any Ratio" by default), next
//    to the photo count, in one menu chip.
//
//  Smoothness rules, inherited from the Home/Carousel performance pass: cards
//  are cache-first (memory hits go up unanimated in the same frame, only late
//  arrivals crossfade), the spotlight's depth effect is a transform, shadows
//  carry paths, and the grid only reloads when what it shows changed.
//

import UIKit

@MainActor
final class TemplateGalleryViewController: UIViewController {

    /// Wired by AppCoordinator. Only called for templates the user may open.
    var onSelectTemplate: ((CollageTemplate) -> Void)?

    /// A chip: the template category it filters to (nil for All), its
    /// localized title, and the English name its accessibility identifier and
    /// Home's "See All" deep links use.
    struct Category {
        let id: String?
        let title: String
        let name: String
    }

    static let categories: [Category] = [
        Category(id: nil, title: String(localized: "All"), name: "All"),
        Category(id: "instant", title: String(localized: "Instant"), name: "Instant"),
        Category(id: "film", title: String(localized: "Film"), name: "Film"),
        Category(id: "editorial", title: String(localized: "Editorial"), name: "Editorial"),
        Category(id: "dump", title: String(localized: "Photo Dump"), name: "Photo Dump"),
        Category(id: "grid", title: String(localized: "Grid"), name: "Grid"),
        Category(id: "minimal", title: String(localized: "Minimal"), name: "Minimal"),
        Category(id: "story", title: String(localized: "Story"), name: "Story"),
        Category(id: "travel", title: String(localized: "Travel"), name: "Travel"),
        Category(id: "seasonal", title: String(localized: "Seasonal"), name: "Seasonal"),
        Category(id: "birthday", title: String(localized: "Birthday"), name: "Birthday"),
    ]

    private struct Item: Hashable {
        let section: String
        let templateID: String
    }

    private let service: TemplateService
    private let curation: CollageGalleryCuration
    private let calendar: Calendar

    private var query = CollageGalleryQuery()
    private var sections: [CollageGallerySection] = []
    private var templatesByID: [String: CollageTemplate] = [:]
    private var newIDs: Set<String> = []
    private var lastLockSignature: [Bool] = []

    private lazy var filterChip = makeFilterChip()
    private let filterDivider = UIView()
    private lazy var chipsView = makeChipsView()
    private lazy var gridView = makeGridView()
    private lazy var dataSource = makeDataSource()
    private let emptyState = UIStackView()
    private let emptyLabel = UILabel()
    private let clearFiltersButton = UIButton(type: .system)
    /// Holds a long-press menu's action until the menu is gone (phase 4).
    private let menuStash = ContextMenuActionStash()
    private let searchController = UISearchController(searchResultsController: nil)

    private static let cardSpacing: CGFloat = 12
    private static let shelfArtworkHeight: CGFloat = 200
    private static let tallShelfArtworkHeight: CGFloat = 280

    init(service: TemplateService = .shared,
         curation: CollageGalleryCuration = .bundled(),
         calendar: Calendar = .current) {
        self.service = service
        self.curation = curation
        self.calendar = calendar
        self.newIDs = Set(curation.newTemplateIDs)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // `navigationItem.title`, NOT `title`: the latter also rewrites this
        // tab's bar label. The tab is "Collage"; this screen is "Collage Templates".
        navigationItem.title = String(localized: "Collage Templates")
        view.backgroundColor = Theme.Color.background
        navigationController?.navigationBar.prefersLargeTitles = false

        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = String(localized: "Search collage templates")
        searchController.searchBar.searchTextField.accessibilityIdentifier = "collageGallerySearchField"
        navigationItem.searchController = searchController
        definesPresentationContext = true

        configureEmptyState()
        filterDivider.backgroundColor = Theme.Color.separator

        for subview in [filterChip, filterDivider, chipsView, gridView, emptyState] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        view.sendSubviewToBack(gridView)
        TopFadeView.install(in: self, above: gridView)

        NSLayoutConstraint.activate([
            filterChip.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.Spacing.md),
            filterChip.centerYAnchor.constraint(equalTo: chipsView.centerYAnchor),

            filterDivider.leadingAnchor.constraint(equalTo: filterChip.trailingAnchor, constant: Theme.Spacing.sm),
            filterDivider.centerYAnchor.constraint(equalTo: chipsView.centerYAnchor),
            filterDivider.widthAnchor.constraint(equalToConstant: 1),
            filterDivider.heightAnchor.constraint(equalToConstant: 20),

            chipsView.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Theme.Spacing.xs),
            chipsView.leadingAnchor.constraint(equalTo: filterDivider.trailingAnchor, constant: Theme.Spacing.xs),
            chipsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chipsView.heightAnchor.constraint(equalToConstant: 48),

            gridView.topAnchor.constraint(equalTo: view.topAnchor),
            gridView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gridView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gridView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyState.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyState.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.leadingAnchor, constant: Theme.Spacing.xxl),
            emptyState.trailingAnchor.constraint(
                lessThanOrEqualTo: view.trailingAnchor, constant: -Theme.Spacing.xxl),
        ])

        service.loadBundledTemplates()
        applyQuery(animated: false)
        lastLockSignature = lockSignature()

        // A save made here or on Home redraws the hearts here.
        NotificationCenter.default.addObserver(
            self, selector: #selector(favouritesChanged),
            name: FavoritesStore.didChangeNotification, object: nil)
    }

    /// Re-asks the entitlement, so a purchase shows without a relaunch — the
    /// paywall's completion pushes the editor, and coming back to padlocks on
    /// the thing just bought would read as a failed purchase. Only when a lock
    /// actually changed: a tab switch must not re-run every visible card.
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let locks = lockSignature()
        guard locks != lastLockSignature else { return }
        lastLockSignature = locks
        reconfigureVisibleCards()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        revealSelectedChipIfNeeded()
        // Clears the pinned filter row above the content.
        let inset = chipsView.frame.maxY - view.safeAreaInsets.top + Theme.Spacing.xs
        if abs(gridView.contentInset.top - inset) > 0.5 {
            gridView.contentInset.top = inset
            gridView.verticalScrollIndicatorInsets.top = inset
        }
    }

    private func lockSignature() -> [Bool] {
        service.templates.map { service.canOpen($0) }
    }

    @objc private func favouritesChanged() {
        reconfigureVisibleCards()
    }

    /// Re-runs the configuration of every card (cache-first, so cheap) without
    /// rebuilding the layout — for a lock or a heart that changed underneath.
    private func reconfigureVisibleCards() {
        var snapshot = dataSource.snapshot()
        guard !snapshot.itemIdentifiers.isEmpty else { return }
        snapshot.reconfigureItems(snapshot.itemIdentifiers)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    // MARK: - Query

    /// Lands the gallery on one category, as a Home collection's "See All"
    /// does. Matched against a chip's category or its English name without
    /// regard to case, so "seasonal" and "Seasonal" both find the Seasonal
    /// chip; an unknown name leaves the gallery as it was. Safe before the view
    /// loads: `viewDidLoad` applies whatever is selected.
    func preselect(category: String) {
        guard let match = Self.categories.first(where: {
            $0.name.caseInsensitiveCompare(category) == .orderedSame
                || ($0.id.map { $0.caseInsensitiveCompare(category) == .orderedSame } ?? false)
        }) else { return }
        query.category = match.id
        needsChipReveal = true
        guard isViewLoaded else { return }
        chipsView.reloadData()
        applyQuery(animated: false)
        scrollToTop()
        revealSelectedChipIfNeeded()
    }

    private var needsChipReveal = false

    private func revealSelectedChipIfNeeded() {
        guard needsChipReveal, chipsView.bounds.width > 0,
              let index = Self.categories.firstIndex(where: { $0.id == query.category }) else { return }
        needsChipReveal = false
        chipsView.layoutIfNeeded()
        chipsView.scrollToItem(
            at: IndexPath(item: index, section: 0), at: .centeredHorizontally, animated: false)
    }

    private func applyQuery(animated: Bool) {
        let month = calendar.component(.month, from: Date())
        sections = CollageGalleryPlanner.sections(
            templates: service.templates, curation: curation, query: query, month: month)
        templatesByID = Dictionary(
            service.templates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var snapshot = NSDiffableDataSourceSnapshot<String, Item>()
        for section in sections {
            snapshot.appendSections([section.id])
            snapshot.appendItems(section.templates.map { Item(section: section.id, templateID: $0.id) })
        }

        // A reload, not a diff: shelf widths and masonry heights depend on the
        // items, so every section is re-asked of the provider. NO explicit
        // `invalidateLayout()` first — `sections` is already the new answer
        // while the collection view still holds the old snapshot, and a scrolled
        // grid resolves the layout right there (to save its offset anchor),
        // asking for sections that no longer exist. That was an abort on any
        // See All tapped below the fold. The swap happens INSIDE the
        // crossfade — a crossfade around an empty closure animates nothing.
        let swap = { [self] in
            dataSource.applySnapshotUsingReloadData(snapshot)
        }
        if animated {
            UIView.transition(
                with: gridView, duration: Theme.Motion.duration(Theme.Motion.quick),
                options: [.transitionCrossDissolve, .allowUserInteraction], animations: swap)
        } else {
            swap()
        }

        emptyState.isHidden = !sections.isEmpty
        filterChip.setValue(filterSummary)
        filterChip.menu = makeFilterMenu()
        prefetchShelfHeads()
    }

    /// Shelves scroll sideways, where the grid's prefetching cannot see; their
    /// first cards are warmed up here so the first swipe lands on pictures.
    private func prefetchShelfHeads() {
        let heads = sections.flatMap { section -> [CollageTemplate] in
            switch section {
            case let .spotlight(t): return Array(t.prefix(3))
            case let .shelf(_, t): return Array(t.prefix(4))
            case .catalog, .results: return []
            }
        }
        service.prefetchPreviews(for: heads)
    }

    private func setQuery(_ mutate: (inout CollageGalleryQuery) -> Void) {
        var next = query
        mutate(&next)
        guard next != query else { return }
        query = next
        applyQuery(animated: true)
        scrollToTop()
    }

    private func select(category: Category) {
        guard query.category != category.id else { return }
        Haptics.selectionChanged()
        setQuery { $0.category = category.id }
        chipsView.reloadData()
    }

    private func clearFilters() {
        Haptics.selectionChanged()
        if !(searchController.searchBar.text ?? "").isEmpty {
            searchController.searchBar.text = ""
        }
        setQuery { $0 = CollageGalleryQuery() }
        chipsView.reloadData()
    }

    /// `adjustedContentInset`, not `contentInset`: the grid runs under the
    /// pinned row, so the safe area is half of what holds the first row clear.
    private func scrollToTop() {
        gridView.setContentOffset(
            CGPoint(x: 0, y: -gridView.adjustedContentInset.top), animated: false)
    }

    // MARK: - Filter chip

    private var filterSummary: String {
        var parts: [String] = []
        if query.photos != .any { parts.append(query.photos.title) }
        if let ratio = query.ratio { parts.append(ratio.displayName) }
        return parts.isEmpty ? String(localized: "Filters") : parts.joined(separator: " · ")
    }

    private func makeFilterChip() -> FilterMenuChip {
        let chip = FilterMenuChip(
            symbolName: "slider.horizontal.3",
            identifier: "collageFilterChip",
            accessibilityLabel: String(localized: "Filters"))
        chip.setValue(String(localized: "Filters"))
        chip.setContentCompressionResistancePriority(.required, for: .horizontal)
        return chip
    }

    /// Two questions in one menu — how many photos, and where it will be
    /// posted. Rebuilt on every change so the checkmarks follow the query.
    private func makeFilterMenu() -> UIMenu {
        let photos = CollagePhotoFilter.allCases.map { filter in
            UIAction(title: filter.title, state: query.photos == filter ? .on : .off) { [weak self] _ in
                Haptics.selectionChanged()
                self?.setQuery { $0.photos = filter }
            }
        }
        let anyRatio = UIAction(
            title: String(localized: "Any Ratio"), state: query.ratio == nil ? .on : .off
        ) { [weak self] _ in
            Haptics.selectionChanged()
            self?.setQuery { $0.ratio = nil }
        }
        let ratios = CanvasPreset.allCases.map { preset in
            UIAction(title: preset.displayName, subtitle: preset.aspectRatio,
                     state: query.ratio == preset ? .on : .off) { [weak self] _ in
                Haptics.selectionChanged()
                self?.setQuery { $0.ratio = preset }
            }
        }
        return UIMenu(children: [
            UIMenu(title: String(localized: "How Many Photos"), options: .displayInline, children: photos),
            UIMenu(title: String(localized: "Canvas Ratio"), options: .displayInline, children: [anyRatio] + ratios),
        ])
    }

    // MARK: - Empty state

    private func configureEmptyState() {
        emptyLabel.font = Theme.Typography.body
        emptyLabel.adjustsFontForContentSizeCategory = true
        emptyLabel.textColor = Theme.Color.textSecondary
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.text = String(localized: "No collage templates match your filters.")
        emptyLabel.accessibilityIdentifier = "galleryEmptyLabel"

        var config = UIButton.Configuration.tinted()
        config.cornerStyle = .capsule
        config.title = String(localized: "Clear Filters")
        clearFiltersButton.configuration = config
        clearFiltersButton.tintColor = Theme.Color.accentStrong
        clearFiltersButton.accessibilityIdentifier = "galleryClearFiltersButton"
        clearFiltersButton.addAction(UIAction { [weak self] _ in self?.clearFilters() }, for: .touchUpInside)

        emptyState.axis = .vertical
        emptyState.alignment = .center
        emptyState.spacing = Theme.Spacing.md
        emptyState.addArrangedSubview(emptyLabel)
        emptyState.addArrangedSubview(clearFiltersButton)
        emptyState.isHidden = true
    }

    // MARK: - Subview factories

    private func makeChipsView() -> UICollectionView {
        let item = NSCollectionLayoutItem(
            layoutSize: NSCollectionLayoutSize(widthDimension: .estimated(80), heightDimension: .absolute(32)))
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(widthDimension: .estimated(80), heightDimension: .absolute(32)),
            subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuous
        section.interGroupSpacing = Theme.Spacing.xs
        section.contentInsets = NSDirectionalEdgeInsets(
            top: Theme.Spacing.xs, leading: Theme.Spacing.md,
            bottom: Theme.Spacing.xs, trailing: Theme.Spacing.md)

        let view = UICollectionView(
            frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout(section: section))
        view.backgroundColor = .clear
        view.showsHorizontalScrollIndicator = false
        view.dataSource = self
        view.delegate = self
        view.accessibilityIdentifier = "categoryChips"
        view.register(CategoryChipCell.self, forCellWithReuseIdentifier: CategoryChipCell.reuseID)
        return view
    }

    private func makeGridView() -> UICollectionView {
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.interSectionSpacing = Theme.Spacing.md
        let layout = UICollectionViewCompositionalLayout(
            sectionProvider: { [weak self] index, environment in
                self?.makeSection(at: index, environment: environment) ?? Self.emptySection()
            }, configuration: configuration)

        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = Theme.Color.background
        view.showsVerticalScrollIndicator = false
        view.delegate = self
        view.prefetchDataSource = self
        view.accessibilityIdentifier = "templateGalleryGrid"
        return view
    }

    // MARK: - Layout

    private func makeSection(
        at index: Int, environment: NSCollectionLayoutEnvironment
    ) -> NSCollectionLayoutSection {
        // Never nil: a nil section is an assertion inside UIKit. An index past
        // the plan can only be a stale query mid-reload; an empty sliver
        // answers it harmlessly and is replaced on the next pass.
        guard sections.indices.contains(index) else { return Self.emptySection() }
        switch sections[index] {
        case let .spotlight(templates):
            return spotlightSection(count: templates.count, environment: environment)
        case let .shelf(shelf, templates):
            return shelfSection(templates, tall: shelf.tall == true)
        case let .catalog(templates):
            return masonrySection(templates, environment: environment, header: true)
        case let .results(templates):
            return masonrySection(templates, environment: environment, header: false)
        }
    }

    private static func emptySection() -> NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(1))
        return NSCollectionLayoutSection(group: .horizontal(
            layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)]))
    }

    private func header(estimated height: CGFloat = 60) -> NSCollectionLayoutBoundarySupplementaryItem {
        NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1),
                                               heightDimension: .estimated(height)),
            elementKind: UICollectionView.elementKindSectionHeader, alignment: .top)
    }

    /// The paged hero row: one card centred, its neighbours peeking and
    /// stepped back in depth as they leave the centre.
    private func spotlightSection(
        count: Int, environment: NSCollectionLayoutEnvironment
    ) -> NSCollectionLayoutSection {
        let container = environment.container.effectiveContentSize.width
        let width = min(container - 72, 380)
        let height = width * 0.78 + CollageSpotlightCell.captionHeight(for: environment.traitCollection)
        let item = NSCollectionLayoutItem(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1),
                                               heightDimension: .fractionalHeight(1)))
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(width),
                                               heightDimension: .absolute(height)),
            subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .groupPagingCentered
        section.interGroupSpacing = Theme.Spacing.sm
        section.contentInsets = NSDirectionalEdgeInsets(
            top: Theme.Spacing.xxs, leading: 0, bottom: Theme.Spacing.xs, trailing: 0)
        let header = header()
        header.contentInsets = NSDirectionalEdgeInsets(
            top: 0, leading: Theme.Spacing.md, bottom: 0, trailing: Theme.Spacing.md)
        section.boundarySupplementaryItems = [header]

        guard !Theme.Motion.isReduced else { return section }
        section.visibleItemsInvalidationHandler = { items, offset, environment in
            let centre = offset.x + environment.container.contentSize.width / 2
            for item in items where item.representedElementCategory == .cell {
                let distance = abs(item.frame.midX - centre)
                let t = min(1, distance / max(item.frame.width, 1))
                let scale = 1 - 0.07 * t
                item.transform = CGAffineTransform(scaleX: scale, y: scale)
                item.alpha = 1 - 0.25 * t
            }
        }
        return section
    }

    /// A sideways shelf whose cards keep each template's own shape: a 9:16
    /// story is tall and narrow, an instant print nearly square. Widths are
    /// clamped so a landscape template does not take a whole screen.
    private func shelfSection(_ templates: [CollageTemplate], tall: Bool) -> NSCollectionLayoutSection {
        let artworkHeight = tall ? Self.tallShelfArtworkHeight : Self.shelfArtworkHeight
        let captionHeight = BrowseTemplateCell.captionHeight
        var x: CGFloat = 0
        let frames: [CGRect] = templates.map { template in
            let size = CanvasSize.size(forAspectRatio: template.canvasAspectRatio)
            let aspect = min(max(size.width / max(size.height, 1), 0.5625), 1.4)
            let frame = CGRect(x: x, y: 0, width: (artworkHeight * aspect).rounded(),
                               height: artworkHeight + captionHeight)
            x = frame.maxX + Self.cardSpacing
            return frame
        }
        let width = max(1, x - Self.cardSpacing)
        let group = NSCollectionLayoutGroup.custom(
            layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(width),
                                               heightDimension: .absolute(artworkHeight + captionHeight))
        ) { _ in frames.map(NSCollectionLayoutGroupCustomItem.init(frame:)) }
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuous
        section.contentInsets = NSDirectionalEdgeInsets(
            top: 0, leading: Theme.Spacing.md, bottom: Theme.Spacing.xs, trailing: Theme.Spacing.md)
        section.boundarySupplementaryItems = [header()]
        return section
    }

    private func masonrySection(
        _ templates: [CollageTemplate], environment: NSCollectionLayoutEnvironment, header showsHeader: Bool
    ) -> NSCollectionLayoutSection {
        let insets = NSDirectionalEdgeInsets(
            top: Theme.Spacing.xxs, leading: Theme.Spacing.md,
            bottom: Theme.Spacing.xl, trailing: Theme.Spacing.md)
        let width = environment.container.effectiveContentSize.width - insets.leading - insets.trailing
        let placement = MasonryLayout.frames(
            aspectRatios: templates.map { template in
                let size = CanvasSize.size(forAspectRatio: template.canvasAspectRatio)
                return size.width / max(size.height, 1)
            },
            columns: Theme.Layout.galleryColumns(for: environment.traitCollection),
            containerWidth: width,
            spacing: Self.cardSpacing,
            captionHeight: BrowseTemplateCell.captionHeight)
        // A custom group is clipped to its declared size, so the height is the
        // measured total; `max(1,…)` keeps an empty section legal.
        let group = NSCollectionLayoutGroup.custom(
            layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(max(1, width)),
                                               heightDimension: .absolute(max(1, placement.totalHeight)))
        ) { _ in placement.frames.map(NSCollectionLayoutGroupCustomItem.init(frame:)) }
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = insets
        if showsHeader { section.boundarySupplementaryItems = [header()] }
        return section
    }

    // MARK: - Data source

    private func makeDataSource() -> UICollectionViewDiffableDataSource<String, Item> {
        let browse = UICollectionView.CellRegistration<BrowseTemplateCell, Item> {
            [weak self] cell, _, item in
            guard let self, let template = self.templatesByID[item.templateID] else { return }
            self.configure(cell, with: template, inShelf: item.section.hasPrefix("shelf-"))
        }
        let spotlight = UICollectionView.CellRegistration<CollageSpotlightCell, Item> {
            [weak self] cell, _, item in
            guard let self, let template = self.templatesByID[item.templateID] else { return }
            self.configure(cell, with: template)
        }
        let header = UICollectionView.SupplementaryRegistration<CollageShelfHeaderView>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] view, _, indexPath in
            guard let self, self.sections.indices.contains(indexPath.section) else { return }
            self.configure(view, for: self.sections[indexPath.section])
        }

        let source = UICollectionViewDiffableDataSource<String, Item>(collectionView: gridView) {
            collectionView, indexPath, item in
            item.section == "spotlight"
                ? collectionView.dequeueConfiguredReusableCell(using: spotlight, for: indexPath, item: item)
                : collectionView.dequeueConfiguredReusableCell(using: browse, for: indexPath, item: item)
        }
        source.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
        }
        return source
    }

    private func artwork(for template: CollageTemplate) -> BrowseTemplateCell.Artwork {
        // Photo-real first, schematic second — the reason a browse card can
        // never come back blank. Memory first, then off the main thread.
        .init(cached: service.cachedShowcasePreview(for: template),
              load: { [service] in await service.loadShowcasePreview(for: template) })
    }

    private func tag(for template: CollageTemplate) -> String? {
        newIDs.contains(template.id) ? String(localized: "New") : nil
    }

    private func configure(_ cell: BrowseTemplateCell, with template: CollageTemplate, inShelf: Bool) {
        // Keyed off `isPremium`, NOT `canOpen`, unlike the badge itself: these
        // identifiers are how the paywall UI tests find a locked card. Shelf
        // cards take their own prefix — a card half off-screen in a sideways
        // shelf is not one a test (or a user) can tap.
        let isPremium = service.isPremium(template)
        let prefix = inShelf ? "templateShelfCard" : "templateCard"
        let item = FavoritesStore.Item(kind: .photo, id: template.id)
        cell.configure(
            BrowseTemplateCell.Content(
                name: template.name,
                // The card's shape already states the ratio on a shelf; in the
                // grid (clamped) the word would repeat on half the cards.
                ratio: nil,
                photos: template.photoCount,
                pages: nil,
                locked: !service.canOpen(template),
                identifier: "\(prefix).\(isPremium ? "premium" : "free")",
                saved: FavoritesStore.shared.isSaved(item),
                // Not on shelves: with a whole new collection, a pill on every
                // shelf card stops meaning anything and covers the headline
                // art. The spotlight and the catalog grid carry it.
                tag: inShelf ? nil : tag(for: template)),
            artwork: artwork(for: template))
        cell.accessibilityCustomActions = [FavouriteContextMenu.customAction(for: item) {}]
    }

    private func configure(_ cell: CollageSpotlightCell, with template: CollageTemplate) {
        let size = CanvasSize.size(forAspectRatio: template.canvasAspectRatio)
        let category = Self.categories.first {
            $0.id?.caseInsensitiveCompare(template.category) == .orderedSame
        }?.title
        let photos = String(localized: "\(template.photoCount) photos")
        cell.configure(
            CollageSpotlightCell.Content(
                name: template.name,
                detail: [category, photos].compactMap { $0 }.joined(separator: " · "),
                aspectRatio: size.width / max(size.height, 1),
                tintHex: template.background.hex,
                tag: tag(for: template),
                locked: !service.canOpen(template),
                identifier: "templateSpotlightCard.\(service.isPremium(template) ? "premium" : "free")"),
            artwork: artwork(for: template))
    }

    private func configure(_ header: CollageShelfHeaderView, for section: CollageGallerySection) {
        switch section {
        case .spotlight:
            header.configure(title: String(localized: "Fresh This Week"),
                             subtitle: String(localized: "New looks, free to try"),
                             identifier: "spotlight", showsSeeAll: false)
        case let .shelf(shelf, _):
            let category = shelf.category.flatMap { id in
                Self.categories.first { $0.id?.caseInsensitiveCompare(id) == .orderedSame }
            }
            header.configure(title: shelf.title, subtitle: shelf.subtitle,
                             identifier: shelf.id, showsSeeAll: category != nil)
            header.onSeeAll = { [weak self] in
                guard let self, let category else { return }
                self.select(category: category)
                self.needsChipReveal = true
                self.revealSelectedChipIfNeeded()
            }
        case let .catalog(templates):
            header.configure(title: String(localized: "All Templates"),
                             subtitle: String(localized: "\(templates.count) designs, newest first"),
                             identifier: "catalog", showsSeeAll: false)
        case .results:
            header.configure(title: "", subtitle: nil, identifier: "results", showsSeeAll: false)
        }
    }
}

// MARK: - Chips + selection

extension TemplateGalleryViewController: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        collectionView === chipsView ? Self.categories.count : 0
    }

    func collectionView(
        _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: CategoryChipCell.reuseID, for: indexPath)
        if let chip = cell as? CategoryChipCell {
            let category = Self.categories[indexPath.item]
            chip.configure(title: category.title, isSelected: category.id == query.category,
                           identifierName: category.name)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if collectionView === chipsView {
            select(category: Self.categories[indexPath.item])
            return
        }
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath),
              let template = templatesByID[item.templateID] else { return }
        if service.canOpen(template) {
            Haptics.tap()
            onSelectTemplate?(template)
        } else {
            Haptics.boundary()
            presentPaywall { [weak self] in self?.onSelectTemplate?(template) }
        }
    }

    // MARK: Save on long press (phase 4)

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard collectionView === gridView,
              let item = dataSource.itemIdentifier(for: indexPath) else { return nil }
        return FavouriteContextMenu.configuration(
            for: .init(kind: .photo, id: item.templateID), at: indexPath, stash: menuStash) {}
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willEndContextMenuInteraction configuration: UIContextMenuConfiguration,
        animator: UIContextMenuInteractionAnimating?
    ) {
        menuStash.complete(with: animator)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        FavouriteContextMenu.preview(for: configuration, in: collectionView)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        FavouriteContextMenu.preview(for: configuration, in: collectionView)
    }
}

// MARK: - Prefetch + search

extension TemplateGalleryViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        guard collectionView === gridView else { return }
        service.prefetchPreviews(for: indexPaths.compactMap {
            dataSource.itemIdentifier(for: $0).flatMap { templatesByID[$0.templateID] }
        })
    }
}

extension TemplateGalleryViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let text = searchController.searchBar.text ?? ""
        guard text != query.search else { return }
        query.search = text
        applyQuery(animated: false)
    }
}
