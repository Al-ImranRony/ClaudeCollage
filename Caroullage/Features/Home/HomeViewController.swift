//
//  HomeViewController.swift
//  Caroullage
//
//  Step 04.5 batch C made this the discovery screen; Step 07 made it a showcase.
//
//  The screen it replaced previewed templates as empty layout SCHEMATICS and led
//  with four icon tiles. That is an honest picture of the app's structure and a
//  terrible picture of its output: it reads as a dev tool, and it asks a first-run
//  user to imagine the result instead of showing it. Home now shows finished
//  work instead — a rotating hero card and three strips of photo-real collages
//  dressed in bundled sample photography — and every one of them is rendered
//  through the SAME `CollageRenderer` the editor and the exporter use. Tapping
//  one opens exactly that structure with the photo zones EMPTY, so the picture
//  on Home is a promise the editor can keep rather than marketing art.
//
//  Section order is the argument the screen makes, top to bottom: start here (the
//  quick-start chips) → here is what this app makes (hero) → here is one made from
//  YOUR photos (Suggested For You) → and here is the catalog, if you want to browse
//  (Photo Collages, Video Collages, Carousels).
//
//  The chips lead because this is an editor, not a feed — the App Store's editors
//  open on create actions and put inspiration below, and Home was doing the
//  reverse. The chips used to CLOSE the screen, roughly 1,400pt down, behind three
//  strips that duplicate the Collage and Carousel tabs: the one section only Home
//  offers was the one section nobody reached. They keep their section header —
//  every other block here is a headed section, and four unlabelled icon pills
//  under the nav bar is the closest this screen gets to the schematic tile grid
//  Step 07 removed.
//
//  The strips lost nothing by moving down. Their "See All" actions exist precisely
//  to hand a browsing user to the tab built for browsing.
//
//  "Custom Size" is deliberately absent — it lives in the floating "+" sheet
//  alongside Image and Video, so all creation-with-a-choice starts in one place.
//

import UIKit

@MainActor
final class HomeViewController: UIViewController {

    // MARK: - Wiring (AppCoordinator)

    /// Every standard template. Filtered here to the ones the sample-content
    /// manifest dresses — see `showcasedPhotoTemplates()`. It stays a provider of
    /// the FULL list because onboarding re-orders it to lead with what the user
    /// said they make, and that ordering has to survive the filter.
    var featuredTemplatesProvider: (() -> [CollageTemplate])?
    var onSelectTemplate: ((CollageTemplate) -> Void)?
    var onBrowseTemplates: (() -> Void)?
    var carouselTemplatesProvider: (() -> [CarouselTemplate])?
    var onSelectCarouselTemplate: ((CarouselTemplate) -> Void)?
    var videoShowcasesProvider: (() -> [SampleContentManifest.VideoShowcase])?
    var onSelectVideoShowcase: ((SampleContentManifest.VideoShowcase) -> Void)?
    var onBrowseCarousels: (() -> Void)?
    var onNewProject: (() -> Void)?
    var onNewPolygon: (() -> Void)?
    var onNewVideoCollage: (() -> Void)?
    var onNewCarousel: (() -> Void)?

    /// Asks for suggested layouts for the user's recent photos. Returns an empty
    /// list when access is absent or nothing is analysable.
    var suggestedLayoutsProvider: (() async -> [GridTemplate])?
    /// Current photo-library read access, and the request. Kept as closures so
    /// Home never imports PhotoKit itself.
    var photoAccessProvider: (() -> RecentPhotoProvider.Access)?
    var requestPhotoAccess: (() async -> RecentPhotoProvider.Access)?
    /// Build a collage from recent photos using the chosen layout.
    var onSelectSuggestedLayout: ((GridTemplate) -> Void)?

    // MARK: - Showcase geometry

    /// A showcase card is portrait-ish (4:5), which is what most of the catalog
    /// is. 176pt is inherited from the pre-reorder fold budget, not derived from
    /// the one in `heroAspectRatio` below — it was sized as what was left for a
    /// complete card once the hero had taken its share, back when the first
    /// strip still lived above the fold. The strips moved below the fold in the
    /// reorder; this number did not need to move with them, so the catalog kept
    /// the size it was tuned to before.
    private static let cardHeight: CGFloat = 176
    private static let cardWidth: CGFloat = 140

    /// The gap at the two seams around the suggestions section, overriding
    /// `contentStack`'s uniform `Spacing.xl` (24pt) for those two only — see the
    /// `setCustomSpacing` calls in `setupLayout`.
    ///
    /// At the stack's default 24pt the "Photo Collages" header landed ON the
    /// floating "Start Editing" pill rather than behind it: measured on an
    /// iPhone 17, the header ran 730.3 → 756.7pt against a pill whose top edge
    /// is 733.0. The pill cut the header mid-word — the first screen read
    /// "Photo Coll ( + Start Editing )" with "See All" stranded to its right. A
    /// CARD peeking under the pill reads as "scroll for more"; a word cut in
    /// half just reads as broken.
    ///
    /// The header has to come up about 32pt to clear, and one 24pt seam cannot
    /// give that much — the first attempt at this used a NEGATIVE spacing on the
    /// single seam below the suggestions, which bought the pixels by overlapping
    /// the header onto the card above it. Splitting the cost across BOTH seams
    /// keeps every value positive and nothing overlapping.
    private static let foldSeamSpacing: CGFloat = 8

    /// The height of whatever the suggestions section is showing — the
    /// `suggestionsStrip`'s cells and its own height anchor both.
    ///
    /// 83 because that is what `enableSuggestionsButton` measures on an iPhone 17
    /// at default type (title plus a subtitle that wraps to two lines), and the
    /// section has to be the SAME height in both of its visible states or the
    /// fold moves with a runtime permission. It used to be 96 here and ~83 there,
    /// and the 13pt difference was not cosmetic — measured frames, with the pill
    /// fixed at 733:
    ///
    ///   content 83 → "Photo Collages" header 698.3 → 724.7, clears by 8.3
    ///   content 96 → "Photo Collages" header 711.3 → 737.7, OVERLAPS by 4.7
    ///
    /// So the strip came down to the card rather than the card going up to the
    /// strip: 96 is not a height this section can afford. The card is left
    /// intrinsic — pinning it too would clip its subtitle at larger type, which
    /// is worse than a moved fold — so the two can still drift apart if that
    /// copy changes. `testTheCatalogHeaderClearsTheStartEditingPill` is what
    /// catches it if they do.
    private static let suggestionsContentHeight: CGFloat = 83
    /// A carousel's preview is three pages laid side by side, so its card is
    /// half again as wide: at photo-card width the centre crop shows one page and
    /// the strip stops saying the only thing it exists to say.
    private static let carouselCardWidth: CGFloat = 212

    /// The hero's height as a share of its width.
    ///
    /// Derived from the fold, not chosen. On an iPhone 17 (402 x 874pt) the
    /// screen is spent like this:
    ///
    ///   106  the title block (62pt status bar + 44pt standard nav)
    ///   + 8  `contentStack`'s top padding
    ///   + 26 the "Create New" header (`title2`, 22pt)
    ///   + 12 the section's own spacing (`Spacing.sm`)
    ///   + 65 the chip row (`sm` + 17pt glyph + `xxs` + `caption` + `sm`)
    ///   + 24 `contentStack.spacing` (`Spacing.xl`)
    ///   + H  the hero, which is `width - 2 * Spacing.md` = 370pt across
    ///   ---
    ///   = 552 at 0.84, where H is 311.
    ///
    /// Below the hero the stack narrows to `foldSeamSpacing` (8pt) at both
    /// seams around the suggestions — see that constant for why.
    ///
    /// Every figure here is a frame read off a running iPhone 17 through the
    /// accessibility tree, not arithmetic. `.notDetermined`:
    ///
    ///   hero                 250.3 → 561.0
    ///   "Suggested For You"  569.0 → 595.3
    ///   suggestions content  607.3 → 690.3   (`suggestionsContentHeight`, 83)
    ///   "Photo Collages"     698.3 → 724.7
    ///   the pill             733.0 → 779.0
    ///
    /// So the catalog's header clears the pill by 8.3pt, and what the pill
    /// overlaps is that strip's CARDS — the "peeks below the fold" cue this
    /// budget relies on everywhere else. The pill's 733 is not measured alone:
    /// `AppTabBarController` computes
    /// `plusY = tabBar.frame.minY - barGap(12) - plusHeight(46)`, which on an
    /// 874pt screen with a stock 83pt bar is `791 - 58 = 733`. Derivation and
    /// measurement agree exactly.
    ///
    /// The other two states move only this section's content, and both are
    /// accounted for. `.denied` (and `.authorized` with nothing analysable)
    /// hides the section outright, which `UIStackView` collapses along with one
    /// seam — measured, the header rises to 569.0, far clear. `.authorized`
    /// with results swaps the enable card for `suggestionsStrip`, which is now
    /// pinned to the same `suggestionsContentHeight`, so the frames above hold
    /// unchanged. That equality is the point: this section used to be 96pt in
    /// one state and 83 in the other, which put the header at 737.7 against a
    /// pill at 733 — a 4.7pt overlap that no test caught and no screenshot
    /// showed, because that state is genuinely hard to stage on a simulator
    /// (`HomeShowcaseUITests` records how, and why the obvious routes fail).
    ///
    /// This block previously claimed the pill sat at 702 and that the
    /// suggestions strip tucked its last 8pt under it, "showing 88 of 96". Both
    /// were invented. 702 was never derived from anything — the comment this
    /// text replaced said 728 — and no state has ever produced that peek. The
    /// numbers above are the first in this block to have been observed.
    ///
    /// The ratio did NOT have to move when the chips took the top. The hero
    /// itself starts 127pt lower than it used to — not merely the chip
    /// section's own 103 (26 + 12 + 65), but that plus a 24pt
    /// `contentStack.spacing` above the hero that the old stack spent between
    /// the hero and the first strip's header instead. The catalog strips moved
    /// further still, past Suggested For You as well, but that shift is below
    /// the fold by design and costs the first screen nothing it has to prove:
    /// you can start here, this is what it makes, here is one from your own
    /// photos — all of it still lands above the pill.
    ///
    /// This budget also assumed the 168pt LARGE-title block until the compact
    /// title freed 62pt (see `viewDidLoad`), and the ratio did not move for that
    /// either.
    ///
    /// It was 1.15 before the chips moved up, which put the hero's bottom at
    /// 602pt and the first strip's cards half under the tab bar: a first screen
    /// that showed ONE template and no evidence the app also makes video or
    /// carousels.
    ///
    /// Still the focal point at 370 x 311: the hero is two and a half times the
    /// width of a strip card and more than a third of the screen's height.
    private static let heroAspectRatio: CGFloat = 0.84

    // MARK: - State

    private let sampleContent = SampleContentCatalog.shared

    private var photoTemplates: [CollageTemplate] = []
    private var videoShowcases: [SampleContentManifest.VideoShowcase] = []
    private var carouselTemplates: [CarouselTemplate] = []
    private var suggestions: [GridTemplate] = []

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let heroView = HeroShowcaseView()
    private var heroSection: UIStackView?

    private lazy var photoStrip = makeShowcaseStrip(
        identifier: "photoShowcaseStrip", itemWidth: Self.cardWidth,
        cellClass: ShowcaseTemplateCell.self, reuseID: ShowcaseTemplateCell.reuseID)
    private lazy var videoStrip = makeShowcaseStrip(
        identifier: "videoShowcaseStrip", itemWidth: Self.cardWidth,
        cellClass: ShowcaseVideoCell.self, reuseID: ShowcaseVideoCell.reuseID)
    private lazy var carouselStrip = makeShowcaseStrip(
        identifier: "carouselShowcaseStrip", itemWidth: Self.carouselCardWidth,
        cellClass: ShowcaseTemplateCell.self, reuseID: ShowcaseTemplateCell.reuseID)
    private var photoSection: UIStackView?
    private var videoSection: UIStackView?
    private var carouselSection: UIStackView?

    private var suggestionsSection: UIStackView?
    private lazy var suggestionsStrip = makeSuggestionsStrip()
    private lazy var enableSuggestionsButton = makeEnableSuggestionsButton()

    /// Whether Home is on screen. Everything that costs battery — the hero's
    /// rotation timer, every video decoder in the video strip — is gated on it.
    private var isVisible = false

    override func viewDidLoad() {
        super.viewDidLoad()
        // `navigationItem.title`, NOT `title`: setting `title` on a tab root also
        // rewrites its tab bar label, so this screen would sit under a tab reading
        // "Caroullage" instead of "Home".
        navigationItem.title = "Caroullage"
        // Compact, not large. The large title's block is 168pt on an iPhone 17 —
        // a fifth of the screen spent telling a user who just opened the app what
        // the app is called, before a single section of content shows.
        //
        // Dropping to the standard bar returns 62pt to the content. The fold
        // budget in `heroAspectRatio` is built on top of that 62pt already being
        // back; choosing large titles again would push its whole budget down by
        // that much, not just the hero.
        //
        // The bar still prefers large titles for anything pushed onto it; this
        // screen opts out the way the three editors already do.
        view.backgroundColor = Theme.Color.background
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .never
        setupNavigationBar()
        setupLayout()

        // Backgrounding is not a view transition, so `viewDidDisappear` never
        // fires for it: without these two, Home would keep a rotation timer and up
        // to one video pipeline alive behind the home screen, and would come back
        // to the foreground showing a frozen last frame.
        //
        // Selector-based observers rather than the block API on purpose: the block
        // form takes a `@Sendable` closure, which cannot capture this non-Sendable
        // `@MainActor` controller under strict concurrency.
        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.addObserver(
            self, selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isVisible = true
        reload()
        refreshProButton()
        setShowcaseActive(true)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        isVisible = false
        setShowcaseActive(false)
    }

    @objc private func appDidEnterBackground() {
        setShowcaseActive(false)
    }

    @objc private func appWillEnterForeground() {
        guard isVisible else { return }
        setShowcaseActive(true)
    }

    /// Starts or stops everything that moves.
    private func setShowcaseActive(_ active: Bool) {
        heroView.setActive(active)
        for case let cell as ShowcaseVideoCell in videoStrip.visibleCells {
            if active { cell.play() } else { cell.stop() }
        }
    }

    func reload() {
        photoTemplates = showcasedPhotoTemplates()
        videoShowcases = videoShowcasesProvider?() ?? []
        carouselTemplates = showcasedCarouselTemplates()

        photoStrip.reloadData()
        videoStrip.reloadData()
        carouselStrip.reloadData()

        // A labelled strip with nothing in it is worse than no strip: it reads as
        // a load that failed. Each section carries its own header, so hiding the
        // section takes the header with it.
        photoSection?.isHidden = photoTemplates.isEmpty
        videoSection?.isHidden = videoShowcases.isEmpty
        carouselSection?.isHidden = carouselTemplates.isEmpty

        let pages = makeHeroPages()
        heroView.configure(pages: pages)
        heroSection?.isHidden = pages.isEmpty
        if isVisible { setShowcaseActive(true) }

        refreshSuggestions()
    }

    // MARK: - Showcase data

    /// The templates Home features, in the order the provider supplied them
    /// (premium last, then alphabetical — or onboarding's preferred category
    /// first).
    ///
    /// Narrowed by an authored list rather than by "everything the manifest
    /// dresses". That older rule made Home's curation a side effect of which
    /// templates happened to have sample photography, and once the Collage tab
    /// went photo-real ALL thirty-three are dressed — which would have turned
    /// this strip into the whole catalog without anyone deciding to.
    ///
    /// The list narrows but does not order: the provider's order is the one that
    /// matters here, because onboarding rewrites it to lead with the category
    /// the user said they make.
    ///
    /// Falls back to the full catalog if the manifest is missing or empty: those
    /// cards then render the schematic `thumbnail(for:)`, which is the old Home's
    /// look but still a working screen — much better than an empty one.
    private func showcasedPhotoTemplates() -> [CollageTemplate] {
        let all = featuredTemplatesProvider?() ?? []
        let featured = sampleContent.featuredTemplateIDs
        guard !featured.isEmpty else { return all }
        return all.filter { featured.contains($0.id) }
    }

    /// The carousels Home features, in the manifest's authored order.
    ///
    /// Not "every carousel the manifest dresses" any more. That rule made Home's
    /// curation a side effect of which templates happened to have sample photos,
    /// and Step 07's Carousel gallery dresses all twenty — which would have
    /// turned this strip into the whole catalog without anyone deciding to.
    ///
    /// Still no schematic fallback, deliberately: unlike a standard template, a
    /// FEATURED carousel with no photography would render as a card full of
    /// empty wells. The gallery is the surface that must never have holes, and
    /// it has `schematicCover` for exactly that.
    private func showcasedCarouselTemplates() -> [CarouselTemplate] {
        let all = carouselTemplatesProvider?() ?? []
        let dressed = Set(sampleContent.manifest?.carousels.keys.map { $0 } ?? [])
        return sampleContent.featuredCarouselIDs.compactMap { id in
            guard dressed.contains(id) else { return nil }
            return all.first { $0.id == id }
        }
    }

    /// The hero's pages, resolved from the manifest's ordered hero list against
    /// the three showcases. A reference that resolves to nothing is skipped rather
    /// than rendered as a blank page.
    private func makeHeroPages() -> [HeroShowcaseView.Page] {
        sampleContent.heroRefs.compactMap { ref -> HeroShowcaseView.Page? in
            switch ref.kind {
            case .template:
                guard let template = photoTemplates.first(where: { $0.id == ref.id })
                else { return nil }
                return HeroShowcaseView.Page(
                    title: template.name,
                    subtitle: String(localized: "Photo collage · Tap to create"),
                    identifier: "heroPage-\(template.id)",
                    preview: {
                        TemplateService.shared.showcasePreview(for: template, maxDimension: 900)
                            ?? TemplateService.shared.thumbnail(for: template)
                    },
                    onTap: { [weak self] in self?.onSelectTemplate?(template) })

            case .video:
                guard let showcase = videoShowcases.first(where: { $0.id == ref.id })
                else { return nil }
                return HeroShowcaseView.Page(
                    title: showcase.title,
                    subtitle: String(localized: "Video collage · Tap to create"),
                    identifier: "heroPage-\(showcase.id)",
                    poster: sampleContent.image(named: showcase.poster),
                    loopURL: sampleContent.videoURL(named: showcase.loop),
                    onTap: { [weak self] in self?.onSelectVideoShowcase?(showcase) })

            case .carousel:
                guard let template = carouselTemplates.first(where: { $0.id == ref.id })
                else { return nil }
                return HeroShowcaseView.Page(
                    title: template.name,
                    subtitle: String(localized: "Carousel · Tap to create"),
                    identifier: "heroPage-\(template.id)",
                    // A three-page strip fitted whole, not cropped to a sliver of
                    // its middle page.
                    presentation: .fitOnBlurredBed,
                    preview: {
                        TemplateService.shared.showcasePreview(
                            for: template, frameMaxDimension: 640)
                    },
                    onTap: { [weak self] in self?.onSelectCarouselTemplate?(template) })
            }
        }
    }

    // MARK: - Navigation bar

    private lazy var proButton = ProBadgeButton(
        title: String(localized: "Pro")
    ) { [weak self] in
        self?.presentPaywallFromHeader()
    }

    /// Brand on the leading side, the paywall on the trailing side.
    ///
    /// `navigationItem.title` stays set even though nothing draws it: the bar's
    /// accessibility identity comes from it, and every suite that waits for Home
    /// waits on `navigationBars["Caroullage"]`. An empty `titleView` suppresses
    /// the centred copy so the wordmark is not printed twice, once in the lockup
    /// and once in the middle of the bar.
    private func setupNavigationBar() {
        navigationItem.titleView = UIView()
        let brand = UIBarButtonItem(customView: BrandLockupView(title: "Caroullage"))
        let pro = UIBarButtonItem(customView: proButton)
        // iOS 26 gives every bar item its own glass capsule. That is the right
        // default for a system control and the wrong one for both of these: it
        // draws a pill around the Pro button's pill, and it makes the wordmark
        // look like something to tap. Each already carries its own shape — the
        // gradient capsule and the mark — so the shared background comes off.
        if #available(iOS 26.0, *) {
            brand.hidesSharedBackground = true
            pro.hidesSharedBackground = true
        }
        navigationItem.leftBarButtonItem = brand
        navigationItem.rightBarButtonItem = pro
        refreshProButton()
    }

    /// Premium users do not get a button to buy premium.
    ///
    /// Re-read rather than observed: `EntitlementStore` broadcasts nothing, and
    /// the two moments that can change the answer — coming back to Home, and
    /// unlocking from this very button — are both already in hand.
    private func refreshProButton() {
        proButton.isHidden = EntitlementStore.shared.isPremiumUnlocked
    }

    private func presentPaywallFromHeader() {
        presentPaywall { [weak self] in
            // Bought from here, so the button that asked has to go without
            // waiting for a trip through another tab.
            self?.refreshProButton()
        }
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
        let header = sectionHeader("Suggested For You")
        let section = UIStackView(arrangedSubviews: [
            header, enableSuggestionsButton, suggestionsStrip,
        ])
        section.axis = .vertical
        section.spacing = Theme.Spacing.sm
        section.isHidden = true
        // Matches `enableSuggestionsButton`'s intrinsic height, so this section
        // contributes the same height whichever of the two it is showing.
        suggestionsStrip.heightAnchor.constraint(
            equalToConstant: Self.suggestionsContentHeight).isActive = true
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
                widthDimension: .absolute(Self.suggestionsContentHeight),
                heightDimension: .absolute(Self.suggestionsContentHeight)),
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

        // First, deliberately. This is an editor, not a feed: the four doors into
        // a format lead, and the showcase argues its case immediately below them.
        // The order is enforced, not just described here — see
        // `testCreateNewLeadsTheScreenAboveTheHero`.
        contentStack.addArrangedSubview(makeQuickStartSection())

        let heroSection = makeHeroSection()
        self.heroSection = heroSection
        contentStack.addArrangedSubview(heroSection)
        contentStack.setCustomSpacing(Self.foldSeamSpacing, after: heroSection)

        // Personalized before generic. The three strips below are a catalog, and
        // a catalog has two tabs of its own; this is the one thing only Home has.
        let suggestionsSection = makeSuggestionsSection()
        self.suggestionsSection = suggestionsSection
        contentStack.addArrangedSubview(suggestionsSection)
        contentStack.setCustomSpacing(Self.foldSeamSpacing, after: suggestionsSection)

        let photoSection = makeStripSection(
            title: String(localized: "Photo Collages"), strip: photoStrip,
            height: Self.cardHeight, actionIdentifier: "seeAllTemplatesButton"
        ) { [weak self] in
            Haptics.tap()
            self?.onBrowseTemplates?()
        }
        self.photoSection = photoSection
        contentStack.addArrangedSubview(photoSection)

        // No "See All" for video: there is no gallery of video showcases to send
        // anyone to, and a button that goes nowhere is worse than none.
        let videoSection = makeStripSection(
            title: String(localized: "Video Collages"), strip: videoStrip,
            height: Self.cardHeight, actionIdentifier: nil, action: nil)
        self.videoSection = videoSection
        contentStack.addArrangedSubview(videoSection)

        let carouselSection = makeStripSection(
            title: String(localized: "Carousels"), strip: carouselStrip,
            height: Self.cardHeight, actionIdentifier: "seeAllCarouselsButton"
        ) { [weak self] in
            Haptics.tap()
            self?.onBrowseCarousels?()
        }
        self.carouselSection = carouselSection
        contentStack.addArrangedSubview(carouselSection)

        scrollView.addSubview(contentStack)
        view.addSubview(scrollView)
        TopFadeView.install(in: self, above: scrollView)

        NSLayoutConstraint.activate([
            // Under the nav bar, not below it. Pinned to the safe area the large
            // title became a fixed 96pt block that never collapsed — which is why
            // every one of these screens started a third of the way down.
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Tight to the title, the way a system list is: the large title's own
            // block already carries the breathing room.
            contentStack.topAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.topAnchor, constant: Theme.Spacing.xs),
            contentStack.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -Theme.Spacing.xxl),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor),
        ])
    }

    /// The hero, inset from both edges so it reads as a card on the page rather
    /// than as a banner bolted to the top of the screen.
    private func makeHeroSection() -> UIStackView {
        let section = UIStackView(arrangedSubviews: [heroView])
        section.isLayoutMarginsRelativeArrangement = true
        section.layoutMargins = UIEdgeInsets(
            top: 0, left: Theme.Spacing.md, bottom: 0, right: Theme.Spacing.md)
        section.isHidden = true
        heroView.heightAnchor.constraint(
            equalTo: heroView.widthAnchor, multiplier: Self.heroAspectRatio).isActive = true
        return section
    }

    private func makeStripSection(
        title: String, strip: UICollectionView, height: CGFloat,
        actionIdentifier: String?, action: (() -> Void)?
    ) -> UIStackView {
        let header = sectionHeader(
            title,
            actionTitle: action == nil ? nil : String(localized: "See All"),
            actionIdentifier: actionIdentifier,
            action: action)
        let section = UIStackView(arrangedSubviews: [header, strip])
        section.axis = .vertical
        section.spacing = Theme.Spacing.sm
        section.isHidden = true
        strip.heightAnchor.constraint(equalToConstant: height).isActive = true
        return section
    }

    /// The four Step 04.5 quick-start tiles, compressed into one row of chips —
    /// NOT a scrolling one; see the comment on `row` below for why. They keep
    /// their accessibility identifiers and their closures: this is the same four
    /// doors, taking a tenth of the space they used to.
    private func makeQuickStartSection() -> UIStackView {
        // "Create New" over "Start Something": the row is the four things this
        // app makes, and a section that lists them should say so plainly.
        let header = sectionHeader(String(localized: "Create New"))

        let chips = [
            QuickStartChip(
                title: String(localized: "Grid"), symbol: "square.grid.2x2.fill",
                identifier: "newProjectButton"
            ) { [weak self] in
                Haptics.tap()
                self?.onNewProject?()
            },
            QuickStartChip(
                title: String(localized: "Shapes"), symbol: "triangle.fill",
                identifier: "polygonQuickStartButton"
            ) { [weak self] in
                Haptics.tap()
                self?.onNewPolygon?()
            },
            QuickStartChip(
                title: String(localized: "Video"), symbol: "play.rectangle.fill",
                identifier: "videoCollageButton"
            ) { [weak self] in
                Haptics.tap()
                self?.onNewVideoCollage?()
            },
            // Home and the "+" sheet overlap on purpose — the app's signature
            // format has to be on both of its front doors.
            QuickStartChip(
                title: String(localized: "Carousel"),
                symbol: CollageMode.carousel.badgeSymbolName,
                identifier: "carouselQuickStartButton"
            ) { [weak self] in
                Haptics.tap()
                self?.onNewCarousel?()
            },
        ]

        // Four across, sharing the width equally — NOT a scrolling row. A row of
        // labelled pills is wider than any iPhone: laid out that way the fourth
        // door (Carousel, the app's signature format) sat off the right edge,
        // where a user has no reason to look for it and where a tap cannot land.
        // Everything on this screen scrolls sideways already; the one section
        // that is a fixed set of four choices should not.
        let row = UIStackView(arrangedSubviews: chips)
        row.axis = .horizontal
        row.spacing = Theme.Spacing.sm
        row.distribution = .fillEqually
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(
            top: 0, left: Theme.Spacing.md, bottom: 0, right: Theme.Spacing.md)
        row.accessibilityIdentifier = "quickStartChipRow"

        let section = UIStackView(arrangedSubviews: [header, row])
        section.axis = .vertical
        section.spacing = Theme.Spacing.sm
        return section
    }

    private func sectionHeader(
        _ title: String, actionTitle: String? = nil, actionIdentifier: String? = nil,
        action: (() -> Void)? = nil
    ) -> SectionHeaderView {
        SectionHeaderView(
            title: title, actionTitle: actionTitle,
            actionIdentifier: actionIdentifier, action: action)
    }

    private func makeShowcaseStrip(
        identifier: String, itemWidth: CGFloat,
        cellClass: AnyClass, reuseID: String
    ) -> UICollectionView {
        let item = NSCollectionLayoutItem(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1))
        )
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .absolute(itemWidth),
                heightDimension: .absolute(Self.cardHeight)),
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
        view.accessibilityIdentifier = identifier
        view.register(cellClass, forCellWithReuseIdentifier: reuseID)
        return view
    }
}

// MARK: - Data source & delegate

extension HomeViewController: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch collectionView {
        case photoStrip: photoTemplates.count
        case videoStrip: videoShowcases.count
        case carouselStrip: carouselTemplates.count
        default: suggestions.count
        }
    }

    func collectionView(
        _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        switch collectionView {
        case photoStrip: return photoCard(collectionView, at: indexPath)
        case videoStrip: return videoCard(collectionView, at: indexPath)
        case carouselStrip: return carouselCard(collectionView, at: indexPath)
        default: return suggestionCard(collectionView, at: indexPath)
        }
    }

    private func photoCard(
        _ collectionView: UICollectionView, at indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ShowcaseTemplateCell.reuseID, for: indexPath)
        guard let card = cell as? ShowcaseTemplateCell,
              photoTemplates.indices.contains(indexPath.item) else { return cell }
        let template = photoTemplates[indexPath.item]
        card.configure(
            name: template.name,
            identifier: "showcaseTemplate-\(template.id)",
            locked: !TemplateService.shared.canOpen(template),
            // The schematic is the fallback, not the plan: it only appears for a
            // template the manifest does not dress, which today means only when
            // the manifest itself failed to load.
            preview: {
                TemplateService.shared.showcasePreview(for: template)
                    ?? TemplateService.shared.thumbnail(for: template)
            })
        return cell
    }

    private func videoCard(
        _ collectionView: UICollectionView, at indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ShowcaseVideoCell.reuseID, for: indexPath)
        guard let card = cell as? ShowcaseVideoCell,
              videoShowcases.indices.contains(indexPath.item) else { return cell }
        let showcase = videoShowcases[indexPath.item]
        card.configure(
            name: showcase.title,
            identifier: "showcaseVideo-\(showcase.id)",
            poster: sampleContent.image(named: showcase.poster),
            loopURL: sampleContent.videoURL(named: showcase.loop))
        return cell
    }

    private func carouselCard(
        _ collectionView: UICollectionView, at indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ShowcaseTemplateCell.reuseID, for: indexPath)
        guard let card = cell as? ShowcaseTemplateCell,
              carouselTemplates.indices.contains(indexPath.item) else { return cell }
        let template = carouselTemplates[indexPath.item]
        card.configure(
            name: template.name,
            identifier: "showcaseCarousel-\(template.id)",
            // How many pages the post has is the one fact the picture cannot
            // state, and the one a user comparing carousels wants first.
            badge: String(localized: "\(template.frameCount) frames"),
            // Until Step 07 there was no `canOpen` overload to ask, so four
            // premium carousels wore no lock and opened free.
            locked: !TemplateService.shared.canOpen(template),
            preview: { TemplateService.shared.showcasePreview(for: template) })
        return cell
    }

    private func suggestionCard(
        _ collectionView: UICollectionView, at indexPath: IndexPath
    ) -> UICollectionViewCell {
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

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        Haptics.tap()

        switch collectionView {
        case photoStrip:
            guard photoTemplates.indices.contains(indexPath.item) else { return }
            onSelectTemplate?(photoTemplates[indexPath.item])
        case videoStrip:
            guard videoShowcases.indices.contains(indexPath.item) else { return }
            onSelectVideoShowcase?(videoShowcases[indexPath.item])
        case carouselStrip:
            guard carouselTemplates.indices.contains(indexPath.item) else { return }
            onSelectCarouselTemplate?(carouselTemplates[indexPath.item])
        default:
            guard suggestions.indices.contains(indexPath.item) else { return }
            onSelectSuggestedLayout?(suggestions[indexPath.item])
        }
    }

    /// Only a card that is actually on screen — and only while Home is — gets to
    /// hold a video pipeline.
    func collectionView(
        _ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        guard isVisible, let card = cell as? ShowcaseVideoCell else { return }
        card.play()
    }

    func collectionView(
        _ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        (cell as? ShowcaseVideoCell)?.stop()
    }
}

// MARK: - Quick-start chip

/// One compact door into a format: glyph, word, pill.
///
/// The full-width `QuickStartTile` still exists and is still right where it is
/// used — the "+" sheet, where the choice IS the screen. On a showcase Home the
/// same four rows took half the page to say what four chips say in one line.
@MainActor
private final class QuickStartChip: UIControl {

    private let action: () -> Void

    init(title: String, symbol: String, identifier: String, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)

        accessibilityIdentifier = identifier
        accessibilityLabel = title
        isAccessibilityElement = true
        accessibilityTraits = .button

        backgroundColor = Theme.Color.controlFill
        layer.cornerRadius = Theme.Radius.md
        layer.cornerCurve = .continuous

        let icon = UIImageView(image: UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)))
        icon.tintColor = Theme.Color.accentStrong
        icon.contentMode = .center

        let label = UILabel()
        label.text = title
        label.font = Theme.Typography.caption
        label.textColor = Theme.Color.textPrimary
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = true
        // A quarter of the width, four times over: "Carousel" is the longest word
        // and the tightest fit, so it is allowed to shrink a little before it
        // truncates.
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8

        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .vertical
        stack.spacing = Theme.Spacing.xxs
        stack.alignment = .center
        // The chip owns the touch; nothing inside it may intercept one.
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: Theme.Spacing.sm),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Theme.Spacing.sm),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.Spacing.xs),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.Spacing.xs),
        ])

        addTarget(self, action: #selector(fire), for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

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
                    ? CGAffineTransform(scaleX: 0.94, y: 0.94) : .identity
            }
        }
    }

    @objc private func fire() { action() }
}

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
            title: "No collages yet",
            subtitle: "Create your first grid collage to get started.",
            buttonTitle: "New Collage",
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
        title.textColor = Theme.Color.textPrimary
        title.textAlignment = .center

        let subtitle = UILabel()
        subtitle.text = content.subtitle
        subtitle.font = Theme.Typography.body
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
