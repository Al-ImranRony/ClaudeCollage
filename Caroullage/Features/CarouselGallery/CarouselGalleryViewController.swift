//
//  CarouselGalleryViewController.swift
//  Caroullage
//
//  Step 07 — the Carousel tab, finally about carousels.
//
//  It used to be `ProjectsViewController(configuration: .carousels)`: the
//  Projects grid with a mode filter. Every card it showed was already one tab
//  over, and Projects' "By type" sort already groups carousels together — so the
//  tab spent a quarter of the tab bar on a filtered view of another tab. All the
//  while the app shipped twenty bundled carousel templates that no browse
//  surface exposed, and Home's "See All" opened the type picker because there
//  was no gallery to open.
//
//  This is that gallery. Sections by carousel type, a staggered masonry grid
//  inside each, and one card per template showing what the template actually
//  produces.
//
//  What decides the content is `CarouselGalleryFilter.sections(...)`, a pure
//  function with its own tests. This file only draws the answer.
//

import UIKit

@MainActor
final class CarouselGalleryViewController: UIViewController {

    /// Wired by AppCoordinator. Called for any template — the premium gate lives
    /// in the coordinator, so every door to a carousel gives one answer.
    var onSelectTemplate: ((CarouselTemplate) -> Void)?

    private let service: TemplateService

    private var selectedType: CarouselType?
    /// `nil` is "Any Ratio", and it is the default — see `CarouselGalleryFilter`.
    private var selectedRatio: CanvasPreset?
    private var searchText = ""

    private var sections: [CarouselGalleryFilter.Section] = []

    /// The chip row's items: "All" followed by the four types.
    private var chipTypes: [CarouselType?] { [nil] + CarouselType.allCases }

    private static let cardSpacing: CGFloat = 12
    private static let headerHeight: CGFloat = 44

    private lazy var ratioChip = makeRatioChip()
    private let filterDivider = UIView()
    private lazy var chipsView = makeChipsView()
    private lazy var gridView = makeGridView()
    private let emptyLabel = UILabel()
    private let searchController = UISearchController(searchResultsController: nil)

    init(service: TemplateService = .shared) {
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // `navigationItem.title`, NOT `title`: the latter also rewrites this
        // tab's bar label, and this screen is called "Carousel Templates" while
        // the tab is called "Carousel". It is titled to match the Collage tab's
        // gallery — the parallel only pays off if both screens introduce
        // themselves the same way.
        navigationItem.title = String(localized: "Carousel Templates")
        view.backgroundColor = Theme.Color.background
        // Inline, not large. A large title costs about a third of the first
        // screen on a tab whose whole job is to show you twenty pictures, and it
        // has to earn that against a search bar and a filter row already stacked
        // beneath it. The tab bar underneath already says "Carousel", so the
        // title is a label rather than a headline.
        navigationController?.navigationBar.prefersLargeTitles = false

        // No "New" button here, deliberately.
        //
        // There was one, on the reasoning that the tab needed to keep the door
        // to a blank carousel that the old empty state provided. It does keep
        // it — the shell's floating "+ Start Editing" pill has a Carousel row
        // and is present on every tab — so the bar button was a second door to
        // the same sheet, sitting directly above the pill that opens it. That is
        // a milder version of the two-CTAs-in-one-band defect that made this tab
        // stop being the picker in the first place.

        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = String(localized: "Search carousel templates")
        // On the TEXT FIELD, not on the search bar. A search bar hosted by the
        // navigation item is not itself an element in the accessibility tree —
        // only the field inside it is, and it does not inherit its host's
        // identifier. Setting this on `searchBar` compiles, reads correctly and
        // silently identifies nothing, which is exactly how the UI test that
        // types into this field failed to find it.
        searchController.searchBar.searchTextField.accessibilityIdentifier
            = "carouselGallerySearchField"
        navigationItem.searchController = searchController
        definesPresentationContext = true

        emptyLabel.font = Theme.Typography.body
        emptyLabel.textColor = Theme.Color.textSecondary
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.accessibilityIdentifier = "carouselGalleryEmptyLabel"
        // Constant — the catalog is bundled, so the only empty this screen has
        // is "your filters match nothing", never "you have made nothing".
        emptyLabel.text = String(localized: "No carousel templates match your filters.")
        emptyLabel.isHidden = true

        filterDivider.backgroundColor = Theme.Color.separator

        for subview in [ratioChip, filterDivider, chipsView, gridView, emptyLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        // The grid runs under the pinned controls, so it belongs behind them,
        // with the fade between the two — the same treatment Projects and the
        // Collage gallery use.
        view.sendSubviewToBack(gridView)
        TopFadeView.install(in: self, above: gridView)

        NSLayoutConstraint.activate([
            ratioChip.leadingAnchor.constraint(
                equalTo: view.leadingAnchor, constant: Theme.Spacing.md),
            ratioChip.centerYAnchor.constraint(equalTo: chipsView.centerYAnchor),

            filterDivider.leadingAnchor.constraint(
                equalTo: ratioChip.trailingAnchor, constant: Theme.Spacing.sm),
            filterDivider.centerYAnchor.constraint(equalTo: chipsView.centerYAnchor),
            filterDivider.widthAnchor.constraint(equalToConstant: 1),
            filterDivider.heightAnchor.constraint(equalToConstant: 20),

            chipsView.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Theme.Spacing.xs),
            chipsView.leadingAnchor.constraint(
                equalTo: filterDivider.trailingAnchor, constant: Theme.Spacing.xs),
            chipsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chipsView.heightAnchor.constraint(equalToConstant: 48),

            gridView.topAnchor.constraint(equalTo: view.topAnchor),
            gridView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gridView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gridView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: gridView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: gridView.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.leadingAnchor, constant: Theme.Spacing.xxl),
            emptyLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: view.trailingAnchor, constant: -Theme.Spacing.xxl),
        ])

        service.loadBundledCarouselTemplates()
        applyFilters(animated: false)
    }

    /// Re-asks the entitlement, so an unlock is reflected without a relaunch.
    ///
    /// The lock badge and the `.premium` identifier are decided in
    /// `cellForItemAt` from `canOpen`, which means a card laid out while locked
    /// stays locked-looking until it recycles. That matters here more than on the
    /// Collage tab: the paywall's completion pushes the editor, so the user
    /// comes back to this exact grid moments after buying, and would find the
    /// thing they just paid for still wearing a padlock.
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyFilters(animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Clears the pinned ratio chip and type chips above the grid.
        let inset = chipsView.frame.maxY - view.safeAreaInsets.top + Theme.Spacing.xs
        if abs(gridView.contentInset.top - inset) > 0.5 {
            gridView.contentInset.top = inset
            gridView.verticalScrollIndicatorInsets.top = inset
        }
    }

    // MARK: - Filtering

    private func applyFilters(animated: Bool = true) {
        sections = CarouselGalleryFilter.sections(
            service.carouselTemplates,
            type: selectedType, ratio: selectedRatio, search: searchText)

        emptyLabel.isHidden = !sections.isEmpty

        // The masonry section's height depends on the items in it, so the layout
        // has to be rebuilt rather than merely reloaded — `reloadData` re-runs
        // the section provider, and `invalidateLayout` makes sure a cached
        // section from the previous filter is not reused.
        //
        // The reload happens INSIDE the transition. A crossfade wrapped around
        // an empty closure animates nothing: the grid would still swap its
        // contents in one hard frame, which on a screen where every card is a
        // photograph reads as a flicker.
        let reload = { [gridView] in
            gridView.collectionViewLayout.invalidateLayout()
            gridView.reloadData()
        }
        if animated {
            UIView.transition(
                with: gridView,
                duration: Theme.Motion.duration(Theme.Motion.quick),
                options: [.transitionCrossDissolve, .allowUserInteraction],
                animations: reload)
        } else {
            reload()
        }
    }

    private func select(type: CarouselType?) {
        guard selectedType != type else { return }
        selectedType = type
        Haptics.selectionChanged()
        chipsView.reloadData()
        applyFilters()
        scrollGridToTop()
    }

    private func select(ratio: CanvasPreset?) {
        guard selectedRatio != ratio else { return }
        selectedRatio = ratio
        ratioChip.setValue(ratio?.displayName ?? String(localized: "Any Ratio"))
        ratioChip.menu = makeRatioMenu()
        Haptics.selectionChanged()
        applyFilters()
        // The ratio narrows as hard as the type does — "Landscape" matches
        // exactly one of the twenty — so it needs this just as much. Leaving it
        // off `select(ratio:)` was how the same defect got back in on half the
        // controls.
        scrollGridToTop()
    }

    /// `adjustedContentInset`, not `contentInset`: the grid runs the full height
    /// of the view, so the safe area is half of what holds the first row clear of
    /// the pinned chips. Scrolling to `-contentInset.top` parks that row under
    /// them, where the top fade leaves it as a ghost — and with a filter that
    /// leaves one card there is nothing to bounce it back. The same correction
    /// `ProjectsViewController` carries on its sort change.
    private func scrollGridToTop() {
        gridView.setContentOffset(
            CGPoint(x: 0, y: -gridView.adjustedContentInset.top), animated: false)
    }

    // MARK: - Subview factories

    private func makeRatioChip() -> FilterMenuChip {
        let chip = FilterMenuChip(
            symbolName: "aspectratio",
            identifier: "carouselRatioChip",
            accessibilityLabel: String(localized: "Canvas ratio"))
        chip.setValue(String(localized: "Any Ratio"))
        chip.menu = makeRatioMenu()
        chip.setContentCompressionResistancePriority(.required, for: .horizontal)
        return chip
    }

    /// Rebuilt on every change so the checkmark follows the selection.
    private func makeRatioMenu() -> UIMenu {
        // "Any Ratio" first and selected by default. The Collage tab has no
        // such entry because its catalog is large enough per preset; this one
        // has exactly one landscape template.
        let any = UIAction(
            title: String(localized: "Any Ratio"),
            state: selectedRatio == nil ? .on : .off
        ) { [weak self] _ in self?.select(ratio: nil) }

        let presets = CanvasPreset.allCases.map { preset in
            UIAction(
                title: preset.displayName,
                subtitle: preset.aspectRatio,
                state: preset == selectedRatio ? .on : .off
            ) { [weak self] _ in self?.select(ratio: preset) }
        }
        return UIMenu(title: String(localized: "Canvas Ratio"), children: [any] + presets)
    }

    private func makeChipsView() -> UICollectionView {
        let item = NSCollectionLayoutItem(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .estimated(80), heightDimension: .absolute(32)))
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .estimated(80), heightDimension: .absolute(32)),
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
        view.accessibilityIdentifier = "carouselTypeChips"
        view.register(CategoryChipCell.self, forCellWithReuseIdentifier: CategoryChipCell.reuseID)
        return view
    }

    private func makeGridView() -> UICollectionView {
        // Rebuilt per invalidation rather than configured once: a masonry
        // section's height depends on the items it is laying out, which change
        // with every chip tap and search keystroke.
        let layout = UICollectionViewCompositionalLayout { [weak self] index, environment in
            self?.makeMasonrySection(at: index, for: environment)
        }

        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = Theme.Color.background
        view.showsVerticalScrollIndicator = false
        view.dataSource = self
        view.delegate = self
        view.accessibilityIdentifier = "carouselTemplateGrid"
        view.register(
            BrowseTemplateCell.self,
            forCellWithReuseIdentifier: BrowseTemplateCell.reuseID)
        view.register(
            CarouselSectionHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: CarouselSectionHeaderView.reuseID)
        return view
    }

    private func makeMasonrySection(
        at index: Int, for environment: NSCollectionLayoutEnvironment
    ) -> NSCollectionLayoutSection? {
        guard sections.indices.contains(index) else { return nil }
        let entry = sections[index]

        let insets = NSDirectionalEdgeInsets(
            top: Theme.Spacing.xs, leading: Theme.Spacing.md,
            bottom: Theme.Spacing.lg, trailing: Theme.Spacing.md)
        let width = environment.container.effectiveContentSize.width
            - insets.leading - insets.trailing

        let placement = MasonryLayout.frames(
            aspectRatios: entry.templates.map { template in
                let size = CanvasSize.size(forAspectRatio: template.canvasAspectRatio)
                return size.width / max(size.height, 1)
            },
            columns: 2,
            containerWidth: width,
            spacing: Self.cardSpacing,
            captionHeight: BrowseTemplateCell.captionHeight)

        // A custom group is clipped to its declared size, so the height must be
        // the measured total rather than an estimate. `max(1,…)` keeps an empty
        // section from declaring a zero-height group, which UIKit rejects.
        let group = NSCollectionLayoutGroup.custom(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .absolute(max(1, width)),
                heightDimension: .absolute(max(1, placement.totalHeight)))
        ) { _ in
            placement.frames.map(NSCollectionLayoutGroupCustomItem.init(frame:))
        }

        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = insets
        // A collapsed section draws no header — it would only repeat the chip
        // the user just tapped.
        if entry.type != nil {
            section.boundarySupplementaryItems = [
                NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: NSCollectionLayoutSize(
                        widthDimension: .fractionalWidth(1),
                        heightDimension: .absolute(Self.headerHeight)),
                    elementKind: UICollectionView.elementKindSectionHeader,
                    alignment: .top),
            ]
        }
        return section
    }
}

// MARK: - Data source + selection

extension CarouselGalleryViewController: UICollectionViewDataSource, UICollectionViewDelegate {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        collectionView === chipsView ? 1 : sections.count
    }

    func collectionView(
        _ collectionView: UICollectionView, numberOfItemsInSection section: Int
    ) -> Int {
        if collectionView === chipsView { return chipTypes.count }
        return sections.indices.contains(section) ? sections[section].templates.count : 0
    }

    func collectionView(
        _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        if collectionView === chipsView {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: CategoryChipCell.reuseID, for: indexPath)
            if let chip = cell as? CategoryChipCell {
                let type = chipTypes[indexPath.item]
                chip.configure(
                    title: type?.displayName ?? String(localized: "All"),
                    isSelected: type == selectedType)
            }
            return cell
        }

        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: BrowseTemplateCell.reuseID, for: indexPath)
        guard let card = cell as? BrowseTemplateCell,
              let template = template(at: indexPath) else { return cell }

        // `canOpen`, not `isPremium`. A crown on something you have already
        // bought is noise; this says "you cannot open this", which is the only
        // thing the badge is for. The Collage tab agrees, since Step 07 —
        // before that it badged every premium card whether or not you owned it.
        let locked = !service.canOpen(template)
        card.configure(
            BrowseTemplateCell.Content(
                name: template.name,
                // Shown here, unlike the Collage tab: this screen defaults to
                // "Any Ratio", so the cards genuinely differ and the word earns
                // its place.
                ratio: CanvasPreset(aspectRatio: template.canvasAspectRatio)?.displayName
                    ?? template.canvasAspectRatio,
                photos: template.photoZoneCount,
                pages: template.frameCount,
                locked: locked,
                identifier: locked ? "carouselTemplateCard.premium" : "carouselTemplateCard.free"),
            preview: { [service] in
                // Photo-real first; the wireframe is what stops a card in a LIST
                // ever coming back blank.
                service.showcaseCover(for: template) ?? service.schematicCover(for: template)
            })
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath
    ) -> UICollectionReusableView {
        guard kind == UICollectionView.elementKindSectionHeader,
              let header = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind, withReuseIdentifier: CarouselSectionHeaderView.reuseID,
                for: indexPath) as? CarouselSectionHeaderView,
              sections.indices.contains(indexPath.section),
              let type = sections[indexPath.section].type
        else {
            return collectionView.dequeueReusableSupplementaryView(
                ofKind: kind, withReuseIdentifier: CarouselSectionHeaderView.reuseID,
                for: indexPath)
        }

        header.configure(
            title: type.displayName,
            identifier: "carouselSectionHeader-\(type.rawValue)")
        header.onTap = { [weak self] in self?.select(type: type) }
        return header
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if collectionView === chipsView {
            select(type: chipTypes[indexPath.item])
            return
        }

        collectionView.deselectItem(at: indexPath, animated: true)
        guard let template = template(at: indexPath) else { return }
        Haptics.tap()
        // Unconditional: the coordinator owns the premium gate, so the paywall
        // is presented from exactly one place no matter which door was used.
        onSelectTemplate?(template)
    }

    private func template(at indexPath: IndexPath) -> CarouselTemplate? {
        guard sections.indices.contains(indexPath.section),
              sections[indexPath.section].templates.indices.contains(indexPath.item)
        else { return nil }
        return sections[indexPath.section].templates[indexPath.item]
    }
}

// MARK: - Search

extension CarouselGalleryViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        searchText = searchController.searchBar.text ?? ""
        // Not animated: a crossfade per keystroke re-runs a full-grid transition
        // AND re-configures every visible cell, each spawning its own 0.2s
        // cross-dissolve. `ProjectsViewController` does not animate its reload
        // either. The chip and ratio paths keep the fade — those are one
        // deliberate tap, not a stream of them.
        applyFilters(animated: false)
    }
}
