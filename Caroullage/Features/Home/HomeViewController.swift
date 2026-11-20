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

    /// Asks for suggested layouts for the user's recent photos, each already
    /// rendered WITH those photos (Home retention, phase 2). Returns an empty
    /// list when access is absent or nothing is analysable.
    var suggestedLayoutsProvider: (() async -> [HomeSuggestion])?
    /// The newest projects, for "Continue editing". Empty on a first run,
    /// which hides the section and leaves the first-run fold untouched.
    var recentProjectsProvider: (() -> [ProjectSummary])?
    var onOpenProject: ((UUID) -> Void)?
    var onBrowseProjects: (() -> Void)?
    /// What Home shows below the hero today — planned by
    /// `HomeCollectionPlanner` from the bundled file, the date and the
    /// onboarding answer. Re-asked on every appearance; the sections are only
    /// rebuilt when the answer changes.
    var collectionsProvider: (() -> [HomeCollection])?
    var onBrowseCollection: ((HomeCollection) -> Void)?
    /// What the user said they make, so the hero can lead with it.
    var creatorKindProvider: (() -> CreatorKind?)?
    /// The gear in the header (Home retention, phase 3).
    var onOpenSettings: (() -> Void)?
    /// Current photo-library read access, and the request. Kept as closures so
    /// Home never imports PhotoKit itself.
    var photoAccessProvider: (() -> RecentPhotoProvider.Access)?
    var requestPhotoAccess: (() async -> RecentPhotoProvider.Access)?
    /// Build a collage from recent photos using the chosen layout.
    var onSelectSuggestedLayout: ((GridTemplate) -> Void)?

    // MARK: - Showcase geometry

    /// Collection strips size themselves from their card style — see
    /// `HomeCardStyle.artworkSize` (2026-11-20). They all sit below the fold,
    /// so none of those sizes is part of the fold budget below.
    ///
    /// "Continue editing" cards: the Projects tab's own cell at the width the
    /// strips used to have, and the height the fold budget was measured with —
    /// see `heroAspectRatio` for why 176 is the constraint, not a choice.
    private static let recentCardWidth: CGFloat = 140
    private static let recentCardHeight: CGFloat = 176

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
    ///
    /// Phase 4 of the retention work: 0.80, from 0.84. The create chips gained a
    /// one-line format hint ("1:1 post", "freeform"…), which is ~15pt of row
    /// height, and the hero is the one block above the fold with height to
    /// give — at 370 x 296 it is still the focal point, and everything below it
    /// keeps the frames measured above to the point. The first strip's header
    /// still clears the pill; `testNoSectionHeaderIsCutByTheStartEditingPill`
    /// is what holds that.
    private static let heroAspectRatio: CGFloat = 0.80

    // MARK: - State

    private let sampleContent = SampleContentCatalog.shared

    /// One planned collection on screen: the section that holds its header
    /// and strip, and the catalog entries its ids resolved to.
    private struct CollectionStrip {
        enum Items {
            case photo([CollageTemplate])
            case video([SampleContentManifest.VideoShowcase])
            case carousel([CarouselTemplate])

            var count: Int {
                switch self {
                case let .photo(items): return items.count
                case let .video(items): return items.count
                case let .carousel(items): return items.count
                }
            }
        }

        let collection: HomeCollection
        let section: UIStackView
        let strip: UICollectionView
        var items: Items
        /// `signature(of: items)` as of the last reload. Stored, not recomputed:
        /// the old items evaluated now would read the CURRENT lock and heart
        /// state, and an unlock would never register as a change.
        var shownSignature: [String] = []

        /// How this strip's cards present their artwork.
        var style: HomeCardStyle { HomeCardStyle(rawValue: collection.cardStyleName) ?? .poster }
    }

    private var strips: [CollectionStrip] = []
    /// The plan the sections were last built from. Compared against the new
    /// plan rather than against `strips`, which drops collections that resolved
    /// to nothing — comparing against those would rebuild on every appearance.
    private var lastPlanned: [HomeCollection] = []
    /// "Saved Collages" and "Saved Carousels" (phase 4): the same shape as a
    /// planned collection so the cards, taps and menus share one path.
    private var savedStrips: [CollectionStrip] = []
    private let favorites = FavoritesStore.shared
    private let menuStash = ContextMenuActionStash()
    private var recentProjects: [ProjectSummary] = []
    private var suggestions: [HomeSuggestion] = []

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    /// One section per planned collection. Rebuilt only when the plan changes
    /// (a week rolled over, onboarding was answered); reloaded otherwise.
    private let collectionsStack = UIStackView()

    private let heroView = HeroShowcaseView()
    private var heroSection: UIStackView?

    private lazy var recentsStrip = makeShowcaseStrip(
        identifier: "collectionStrip-recents", itemWidth: Self.recentCardWidth,
        height: Self.recentCardHeight, cellClass: ProjectCardCell.self,
        reuseID: ProjectCardCell.reuseID)
    private var recentsSection: UIStackView?

    private var suggestionsSection: UIStackView?
    private lazy var suggestionsStrip = makeSuggestionsStrip()
    private lazy var enableSuggestionsButton = makeEnableSuggestionsButton()

    /// Whether Home is on screen. Everything that costs battery — the hero's
    /// rotation timer, every video decoder in the video strip — is gated on it.
    private var isVisible = false

    override func viewDidLoad() {
        super.viewDidLoad()
        // Video posters are shown as-is, so decode them in the background now
        // rather than on the main thread the first time a reel card draws.
        let posters = sampleContent.videoShowcases.map(\.poster)
        Task { [sampleContent] in await sampleContent.prewarmDecoded(posters) }
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
        // A purchase or a restore made elsewhere: the Pro button goes and the
        // lock badges come off without waiting for a trip through another tab.
        center.addObserver(
            self, selector: #selector(entitlementChanged),
            name: EntitlementStore.didChangeNotification, object: nil)
        center.addObserver(
            self, selector: #selector(favouritesChanged),
            name: FavoritesStore.didChangeNotification, object: nil)
    }

    @objc private func favouritesChanged() {
        reloadSaved()
        reloadStrips()
    }

    @objc private func entitlementChanged() {
        refreshProButton()
        reloadStrips()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isVisible = true
        reload()
        refreshProButton()
        setShowcaseActive(true)
        setSettingsTileShown(true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // A second look once the transition has landed and every frame is
        // final; a no-op when nothing changed since `viewWillAppear`.
        updateViewportPlayback()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        setSettingsTileShown(false)
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
        guard active else {
            heroView.setActive(false)
            for info in strips + savedStrips {
                for case let cell as HomeCardCell in info.strip.visibleCells { cell.stop() }
            }
            playingStrips = []
            return
        }
        // Re-evaluated from scratch: whatever is in the viewport plays. Laid
        // out first, so the strips nested in the scroll view have real frames
        // to test — measured before that, every strip reads as off screen and
        // nothing would start until the first scroll.
        playingStrips = []
        view.layoutIfNeeded()
        updateViewportPlayback()
    }

    // MARK: - Viewport-aware playback

    /// Strips whose video cards are allowed to play: on screen, on a visible
    /// Home. A strip scrolled out of the viewport used to keep every visible
    /// card decoding video — CPU and memory spent on pictures nobody could see,
    /// competing with the scroll that moved them away.
    private var playingStrips: Set<ObjectIdentifier> = []

    private func isInViewport(_ view: UIView) -> Bool {
        // No `window` requirement: during a navigation transition back to
        // Home the view is not in a window yet when `viewWillAppear` asks,
        // and the answer must still be "the hero is on screen". `isVisible`
        // is what says Home is showing.
        guard !view.isHidden, scrollView.bounds.height > 0 else { return false }
        return view.convert(view.bounds, to: scrollView).intersects(scrollView.bounds)
    }

    /// Plays what entered the viewport and stops what left it — the hero and
    /// every strip. Cheap (a rect test per strip), and a no-op when nothing
    /// crossed the edge, so it is safe to call on every scroll frame.
    private func updateViewportPlayback() {
        heroView.setActive(isVisible && isInViewport(heroView))
        for info in strips + savedStrips {
            let id = ObjectIdentifier(info.strip)
            let shouldPlay = isVisible && isInViewport(info.strip)
            guard shouldPlay != playingStrips.contains(id) else { continue }
            if shouldPlay { playingStrips.insert(id) } else { playingStrips.remove(id) }
            for case let cell as HomeCardCell in info.strip.visibleCells {
                if shouldPlay { cell.play() } else { cell.stop() }
            }
        }
    }

    func reload() {
        recentProjects = recentProjectsProvider?() ?? []
        recentsStrip.reloadData()
        recentsSection?.isHidden = recentProjects.isEmpty

        rebuildCollectionsIfNeeded()
        reloadSaved()

        let pages = makeHeroPages()
        heroView.configure(pages: pages)
        heroSection?.isHidden = pages.isEmpty
        if isVisible { setShowcaseActive(true) }

        refreshSuggestions()
    }

    // MARK: - Collections

    /// Resolves a collection's ids against the catalogs, in the collection's
    /// authored order. An id that resolves to nothing is skipped rather than
    /// rendered as a hole. A photo template must also be dressed with sample
    /// photography unless the manifest failed to load outright, in which case
    /// the schematic thumbnail is the fallback — Step 07's rule, kept. A
    /// carousel has no schematic fallback for the reason given there: a
    /// featured carousel with no photography is a card full of empty wells.
    private func resolve(_ collection: HomeCollection) -> CollectionStrip.Items {
        switch collection.kind {
        case .photo:
            let all = featuredTemplatesProvider?() ?? []
            let dressed = sampleContent.manifest.map { Set($0.templates.keys) }
            return .photo(collection.itemIDs.compactMap { id in
                if let dressed, !dressed.contains(id) { return nil }
                return all.first { $0.id == id }
            })
        case .video:
            let all = videoShowcasesProvider?() ?? []
            return .video(collection.itemIDs.compactMap { id in all.first { $0.id == id } })
        case .carousel:
            let all = carouselTemplatesProvider?() ?? []
            let dressed = Set(sampleContent.manifest?.carousels.keys.map { $0 } ?? [])
            return .carousel(collection.itemIDs.compactMap { id in
                guard dressed.contains(id) else { return nil }
                return all.first { $0.id == id }
            })
        }
    }

    /// Rebuilds the sections when the plan changed; otherwise refreshes the
    /// cards in place, which is what a lock coming off needs.
    private func rebuildCollectionsIfNeeded() {
        let planned = collectionsProvider?() ?? []
        if planned == lastPlanned {
            reloadStrips()
            return
        }
        lastPlanned = planned

        for old in strips {
            collectionsStack.removeArrangedSubview(old.section)
            old.section.removeFromSuperview()
            // Forgotten with the strip: a new strip allocated at the freed
            // address would otherwise inherit "already playing".
            playingStrips.remove(ObjectIdentifier(old.strip))
        }
        strips = planned.compactMap { collection in
            let items = resolve(collection)
            // A labelled strip with nothing in it is worse than no strip: it
            // reads as a load that failed.
            guard items.count > 0 else { return nil }
            let strip = makeStrip(for: collection)
            let section = makeCollectionSection(collection, strip: strip)
            collectionsStack.addArrangedSubview(section)
            Analytics.track(.homeSectionShown(id: collection.id))
            return CollectionStrip(collection: collection, section: section, strip: strip, items: items,
                                   shownSignature: signature(of: items))
        }
        collectionsStack.isHidden = strips.isEmpty
    }

    /// Refreshes each strip only if what it shows actually changed.
    ///
    /// Home calls this on every appearance. Reloading unconditionally re-ran
    /// every visible card and, worse, stopped and restarted every playing
    /// video card — a flash across the screen each time the user came back
    /// from an editor, for a screen whose contents had not moved.
    private func reloadStrips() {
        for index in strips.indices {
            let items = resolve(strips[index].collection)
            let shown = signature(of: items)
            strips[index].items = items
            guard shown != strips[index].shownSignature else { continue }
            strips[index].shownSignature = shown
            strips[index].strip.reloadData()
        }
    }

    /// What a strip's cards state: which items, in which order, and the two
    /// facts a card can change while Home is off screen — its lock and its
    /// heart.
    private func signature(of items: CollectionStrip.Items) -> [String] {
        let service = TemplateService.shared
        switch items {
        case let .photo(templates):
            return templates.map {
                "\($0.id)|\(service.canOpen($0))|\(favorites.isSaved(.init(kind: .photo, id: $0.id)))"
            }
        case let .video(showcases):
            return showcases.map(\.id)
        case let .carousel(templates):
            return templates.map {
                "\($0.id)|\(service.canOpen($0))|\(favorites.isSaved(.init(kind: .carousel, id: $0.id)))"
            }
        }
    }

    /// The two saved strips, built once and filled from `FavoritesStore` on
    /// every reload. Hidden while empty, like every other strip.
    private func makeSavedStrips() {
        let photo = HomeCollection(
            id: "saved-photo", titleKey: "Saved Collages", kind: .photo, itemIDs: [])
        let carousel = HomeCollection(
            id: "saved-carousel", titleKey: "Saved Carousels", kind: .carousel, itemIDs: [])
        savedStrips = [photo, carousel].map { collection in
            let strip = makeStrip(for: collection)
            let style = HomeCardStyle(rawValue: collection.cardStyleName) ?? .poster
            let section = makeStripSection(
                title: collection.title, titleIdentifier: "sectionHeader-\(collection.id)",
                subtitle: String(localized: "The ones you kept"),
                strip: strip, height: style.cellSize.height, actionIdentifier: nil, action: nil)
            section.isHidden = true
            contentStack.addArrangedSubview(section)
            return CollectionStrip(collection: collection, section: section, strip: strip, items: .photo([]))
        }
    }

    private func reloadSaved() {
        for index in savedStrips.indices {
            let kind: FavoritesStore.Kind = savedStrips[index].collection.kind == .photo ? .photo : .carousel
            let ids = favorites.savedIDs(kind: kind)
            let collection = savedStrips[index].collection.with(itemIDs: ids)
            let items = resolve(collection)
            let shown = signature(of: items)
            savedStrips[index].items = items
            if shown != savedStrips[index].shownSignature {
                savedStrips[index].shownSignature = shown
                savedStrips[index].strip.reloadData()
            }
            savedStrips[index].section.isHidden = savedStrips[index].items.count == 0
        }
    }

    /// Scrolls the named collection into view — a `caroullage://collection/…`
    /// link, as a reminder about a seasonal drop carries.
    func scroll(toCollection id: String) {
        guard let section = strips.first(where: { $0.collection.id == id })?.section else { return }
        view.layoutIfNeeded()
        let target = section.convert(section.bounds, to: scrollView)
        scrollView.scrollRectToVisible(target.insetBy(dx: 0, dy: -Theme.Spacing.md), animated: true)
    }

    /// The three pillars keep the identifiers the suites have used since Step
    /// 07; every other collection is named by its kind and id.
    private func makeStrip(for collection: HomeCollection) -> UICollectionView {
        let identifier: String
        switch (collection.isPillar, collection.kind) {
        case (true, .photo): identifier = "photoShowcaseStrip"
        case (true, .video): identifier = "videoShowcaseStrip"
        case (true, .carousel): identifier = "carouselShowcaseStrip"
        default: identifier = "collectionStrip-\(collection.kind.rawValue)-\(collection.id)"
        }
        // Every collection strip is built from the one card, in the shape its
        // style names — see `HomeCardCell`.
        let size = (HomeCardStyle(rawValue: collection.cardStyleName) ?? .poster).cellSize
        return makeShowcaseStrip(
            identifier: identifier, itemWidth: size.width, height: size.height,
            cellClass: HomeCardCell.self, reuseID: HomeCardCell.reuseID,
            spacing: Theme.Spacing.md)
    }

    private func makeCollectionSection(
        _ collection: HomeCollection, strip: UICollectionView
    ) -> UIStackView {
        let actionIdentifier: String?
        let action: (() -> Void)?
        switch (collection.isPillar, collection.kind) {
        case (_, .video):
            // No "See All" for video: there is no gallery of video showcases to
            // send anyone to, and a button that goes nowhere is worse than none.
            actionIdentifier = nil
            action = nil
        case (true, .photo):
            actionIdentifier = "seeAllTemplatesButton"
            action = { [weak self] in
                Haptics.tap()
                self?.onBrowseTemplates?()
            }
        case (true, .carousel):
            actionIdentifier = "seeAllCarouselsButton"
            action = { [weak self] in
                Haptics.tap()
                self?.onBrowseCarousels?()
            }
        default:
            actionIdentifier = "collectionSeeAll-\(collection.id)"
            action = { [weak self] in
                Haptics.tap()
                Analytics.track(.collectionSeeAll(id: collection.id))
                self?.onBrowseCollection?(collection)
            }
        }
        let style = HomeCardStyle(rawValue: collection.cardStyleName) ?? .poster
        return makeStripSection(
            title: collection.title,
            titleIdentifier: "sectionHeader-\(collection.id)",
            subtitle: collection.subtitle,
            badge: collection.isNew ? String(localized: "NEW") : nil,
            strip: strip, height: style.cellSize.height,
            actionIdentifier: actionIdentifier, action: action)
    }

    /// The hero's pages, resolved from the manifest's ordered hero list against
    /// the three showcases. A reference that resolves to nothing is skipped rather
    /// than rendered as a blank page.
    ///
    /// Each page is put on the stage that presents its kind best (see
    /// `HeroShowcaseView.Page.Stage`): video and photo work fills the card or
    /// stands as a story frame by shape, carousels deal out as a swiping deck,
    /// and a before/after carousel becomes a wipe.
    private func makeHeroPages() -> [HeroShowcaseView.Page] {
        let templates = featuredTemplatesProvider?() ?? []
        let videos = videoShowcasesProvider?() ?? []
        let carousels = carouselTemplatesProvider?() ?? []
        let sampleContent = self.sampleContent
        // Leads with what the user said they make; the manifest's order
        // otherwise — see `HeroOrdering`.
        let refs = HeroOrdering.order(sampleContent.heroRefs, for: creatorKindProvider?())
        return refs.compactMap { ref -> HeroShowcaseView.Page? in
            switch ref.kind {
            case .template:
                guard let template = templates.first(where: { $0.id == ref.id })
                else { return nil }
                let canvas = CanvasSize.size(forAspectRatio: template.canvasAspectRatio)
                return HeroShowcaseView.Page(
                    title: template.name,
                    subtitle: String(localized: "Photo collage · Tap to create"),
                    identifier: "heroPage-\(template.id)",
                    stage: .resolve(aspect: canvas.width / max(canvas.height, 1)),
                    preview: {
                        await TemplateService.shared.loadShowcasePreview(for: template, maxDimension: 900)
                    },
                    onTap: { [weak self] in
                        Analytics.track(.heroTapped(id: template.id))
                        self?.onSelectTemplate?(template)
                    })

            case .video:
                guard let showcase = videos.first(where: { $0.id == ref.id })
                else { return nil }
                let poster = sampleContent.image(named: showcase.poster)
                let aspect = poster.map { $0.size.width / max($0.size.height, 1) } ?? 1
                return HeroShowcaseView.Page(
                    title: showcase.displayTitle,
                    subtitle: String(localized: "Video collage · Tap to create"),
                    identifier: "heroPage-\(showcase.id)",
                    stage: .resolve(aspect: aspect),
                    poster: poster,
                    loopURL: sampleContent.videoURL(named: showcase.loop),
                    onTap: { [weak self] in
                        Analytics.track(.heroTapped(id: showcase.id))
                        self?.onSelectVideoShowcase?(showcase)
                    })

            case .carousel:
                guard let template = carousels.first(where: { $0.id == ref.id })
                else { return nil }
                let isCompare = ref.heroStage == .compare
                return HeroShowcaseView.Page(
                    title: template.name,
                    subtitle: String(localized: "Carousel · Tap to create"),
                    identifier: "heroPage-\(template.id)",
                    stage: isCompare ? .compare : .deck,
                    // The strip, for the fallback a deck without frames takes.
                    preview: {
                        await TemplateService.shared.loadShowcaseStrip(
                            for: template, frameMaxDimension: 640)
                    },
                    frames: {
                        if isCompare {
                            // One photograph against its own unedited grade, so
                            // the wipe compares like with like.
                            let name = ref.photo
                                ?? sampleContent.manifest?.carousels[template.id]?.framePhotos.first?.first
                            guard let after = name.flatMap(sampleContent.image(named:)),
                                  let before = await HeroCompareGrade.beforeInBackground(from: after)
                            else { return [] }
                            return [before, after]
                        }
                        return await TemplateService.shared
                            .showcaseFramesInBackground(for: template, maxDimension: 480)
                            .map { UIImage(cgImage: $0) }
                    },
                    onTap: { [weak self] in
                        Analytics.track(.heroTapped(id: template.id))
                        self?.onSelectCarouselTemplate?(template)
                    })
            }
        }
    }

    // MARK: - Navigation bar

    private lazy var proButton = ProBadgeButton(
        title: String(localized: "Pro")
    ) { [weak self] in
        self?.presentPaywallFromHeader()
    }

    /// Settings and the brand on the leading side, the paywall on the trailing side.
    ///
    /// `navigationItem.title` stays set even though nothing draws it: the bar's
    /// accessibility identity comes from it, and every suite that waits for Home
    /// waits on `navigationBars["Caroullage"]`. An empty `titleView` suppresses
    /// the centred copy so the wordmark is not printed twice, once in the lockup
    /// and once in the middle of the bar.
    private func setupNavigationBar() {
        navigationItem.titleView = UIView()
        let pro = UIBarButtonItem(customView: proButton)
        // iOS 26 gives every bar item its own glass capsule. That is the right
        // default for a system control and the wrong one for both of these: it
        // draws a pill around the Pro button's pill, and it makes the wordmark
        // look like something to tap. Each already carries its own shape — the
        // gradient capsule, and plain type — so the shared background comes off.
        if #available(iOS 26.0, *) {
            pro.hidesSharedBackground = true
        }
        // Settings floats on the bar (see `installSettingsTile`); the
        // wordmark item keeps the room clear ahead of itself.
        navigationItem.leftBarButtonItem = makeBrandItem()
        navigationItem.rightBarButtonItem = pro
        refreshProButton()
    }

    /// Settings, flush against the screen's leading edge.
    ///
    /// Not a bar item: iOS 26 lays every item out inside the bar's margins and
    /// ignores `directionalLayoutMargins`, so the nearest an item can sit is
    /// 16pt in. Nudging the button out of its item would leave that 16pt strip
    /// untappable — touches only reach a view inside its superview's bounds —
    /// so the tile is the bar's own subview, pinned to its leading edge.
    ///
    /// The bar is shared with every editor pushed on top of Home, so the tile
    /// fades with Home's own appearance (`setSettingsTileShown`).
    private lazy var settingsTile = SettingsGlassTile { [weak self] in
        Analytics.track(.settingsOpened)
        self?.onOpenSettings?()
    }

    /// The wordmark's item, with room ahead of it for the Settings tile.
    ///
    /// Not a spacer item: iOS 26 holds every bar item to at least 44pt wide, so
    /// a spacer starting at the bar's 16pt margin could not end before 60. The
    /// lockup carries the inset itself instead. The bar sizes an item's view
    /// once, when the item is set, so a new inset means a new item — solved in
    /// `viewDidLayoutSubviews` against where the bar actually put it.
    private var brandLeadingInset = SettingsGlassTile.side + Theme.Spacing.sm - Theme.Spacing.md
    private var brandLockup: BrandLockupView?

    private func makeBrandItem() -> UIBarButtonItem {
        let lockup = BrandLockupView(title: "Caroullage", leadingInset: brandLeadingInset)
        brandLockup = lockup
        settingsTileCenterY?.isActive = false
        settingsTileCenterY = nil
        let item = UIBarButtonItem(customView: lockup)
        if #available(iOS 26.0, *) {
            item.hidesSharedBackground = true
        }
        return item
    }

    /// The tile rides level with the bar's items, which sit at the top of the
    /// iOS 26 bar rather than its middle — so it follows the lockup, not the bar.
    private var settingsTileCenterY: NSLayoutConstraint?

    private func installSettingsTile() {
        guard let bar = navigationController?.navigationBar,
              settingsTile.superview !== bar else { return }
        settingsTile.removeFromSuperview()
        settingsTile.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(settingsTile)
        // Level with the bar's items once there is an item to follow
        // (`viewDidLayoutSubviews`); until then, the bar's middle.
        let fallbackY = settingsTile.centerYAnchor.constraint(equalTo: bar.centerYAnchor)
        fallbackY.priority = .defaultLow
        NSLayoutConstraint.activate([
            settingsTile.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            fallbackY,
        ])
    }

    /// Fades the tile in step with Home's push and pop, and settles it from
    /// where the navigation stack actually ended up.
    ///
    /// An abandoned back swipe runs BOTH of Home's callbacks on one cancelled
    /// transition — `viewWillAppear` as the swipe starts, `viewWillDisappear` as
    /// it is cancelled — and both completions then run. Each used to undo its own
    /// change, so the second undo (of the hide) put the tile back on screen, over
    /// the editor's back button. Settling from the stack makes the two completions
    /// agree whatever order they run in.
    private func setSettingsTileShown(_ shown: Bool) {
        installSettingsTile()
        guard let coordinator = transitionCoordinator, coordinator.isAnimated else {
            applySettingsTile(visible: shown)
            return
        }
        settingsTile.isUserInteractionEnabled = shown
        settingsTile.accessibilityElementsHidden = !shown
        coordinator.animate(alongsideTransition: { [settingsTile] _ in
            settingsTile.alpha = shown ? 1 : 0
        }, completion: { [weak self] context in
            guard let self else { return }
            self.applySettingsTile(visible: context.isCancelled ? self.isTopOfVisibleStack : shown)
        })
    }

    /// Whether Home is what the shared bar is showing right now.
    private var isTopOfVisibleStack: Bool {
        isViewLoaded && view.window != nil && navigationController?.topViewController === self
    }

    private func applySettingsTile(visible: Bool) {
        settingsTile.alpha = visible ? 1 : 0
        settingsTile.isUserInteractionEnabled = visible
        settingsTile.accessibilityElementsHidden = !visible
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The first real frames arrive here, after `viewWillAppear` asked.
        updateViewportPlayback()
        guard let bar = navigationController?.navigationBar,
              let lockup = brandLockup, lockup.window != nil,
              settingsTile.superview === bar else { return }
        if settingsTileCenterY == nil {
            let centerY = settingsTile.centerYAnchor.constraint(equalTo: lockup.centerYAnchor)
            centerY.isActive = true
            settingsTileCenterY = centerY
        }
        // The lockup starts at the bar's margin; its wordmark should start one
        // gap after the tile ends, whatever that margin is on this device.
        let frame = lockup.convert(lockup.bounds, to: bar)
        let margin = bar.effectiveUserInterfaceLayoutDirection == .leftToRight
            ? frame.minX : bar.bounds.width - frame.maxX
        let inset = max(0, SettingsGlassTile.side + Theme.Spacing.sm - margin)
        guard abs(inset - brandLeadingInset) > 0.5 else { return }
        brandLeadingInset = inset
        navigationItem.leftBarButtonItem = makeBrandItem()
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
        // "From your photos", not "Suggested For You": the section now shows the
        // user's photos already in the layouts, and the header says so.
        let header = sectionHeader(
            String(localized: "From your photos"), titleIdentifier: "sectionHeader-suggestions")
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
        config.title = String(localized: "Suggest layouts from my photos")
        config.subtitle = String(localized: "Reads your recent photos on this device to pick a layout.")
        config.image = UIImage(systemName: "wand.and.stars")
        config.imagePadding = 8
        config.cornerStyle = .large
        config.baseBackgroundColor = Theme.Color.accent
        // The wash stays the indigo; the label on it is the ink — see
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
            title: String(localized: "Photo access is off"),
            message: String(localized: "Suggestions need permission to read your recent photos. You can turn it on in Settings — everything else keeps working without it."),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "Not Now"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Open Settings"), style: .default) { _ in
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
        // The showcase card, not the editor's wireframe: a suggestion is now a
        // photo-real composite of the user's own photos (`SuggestionPreviewCache`).
        view.register(ShowcaseTemplateCell.self, forCellWithReuseIdentifier: ShowcaseTemplateCell.reuseID)
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
        // Home's own scroll drives viewport-aware playback (see below). The
        // strips report their scrolls through the same delegate methods, so
        // each one checks which scroll view is talking.
        scrollView.delegate = self
        // The hero holds its page while Home is moving under the thumb.
        heroView.holdsPage = { [weak scrollView] in
            guard let scrollView else { return false }
            return scrollView.isDragging || scrollView.isDecelerating
        }

        // First, deliberately. This is an editor, not a feed: the four doors into
        // a format lead, and the showcase argues its case immediately below them.
        // The order is enforced, not just described here — see
        // `testCreateNewLeadsTheScreenAboveTheHero`.
        contentStack.addArrangedSubview(makeQuickStartSection())

        let heroSection = makeHeroSection()
        self.heroSection = heroSection
        contentStack.addArrangedSubview(heroSection)
        contentStack.setCustomSpacing(Self.foldSeamSpacing, after: heroSection)

        // Yours before ours. "Continue editing" is hidden until there is
        // something to continue, so a first run's fold is exactly the one
        // measured in `heroAspectRatio` — a hidden arranged view takes its
        // seam with it. For a returning user the strip's cards land under the
        // pill (607 → 783 against 733), which is the "scroll for more" cue the
        // budget relies on everywhere else; any shorter strip would park the
        // next header inside the pill instead.
        let recentsSection = makeStripSection(
            title: String(localized: "Continue editing"),
            titleIdentifier: "sectionHeader-recents",
            strip: recentsStrip, height: Self.recentCardHeight,
            actionIdentifier: "seeAllProjectsButton"
        ) { [weak self] in
            Haptics.tap()
            self?.onBrowseProjects?()
        }
        self.recentsSection = recentsSection
        contentStack.addArrangedSubview(recentsSection)
        contentStack.setCustomSpacing(Self.foldSeamSpacing, after: recentsSection)

        // Personalized before generic. The collections below are a catalog, and
        // a catalog has two tabs of its own; this is the one thing only Home has.
        let suggestionsSection = makeSuggestionsSection()
        self.suggestionsSection = suggestionsSection
        contentStack.addArrangedSubview(suggestionsSection)
        contentStack.setCustomSpacing(Self.foldSeamSpacing, after: suggestionsSection)

        // The planned collections, then the three pillars — filled by
        // `rebuildCollectionsIfNeeded` on every reload.
        collectionsStack.axis = .vertical
        // More air than the sections above: each strip is now a different
        // shape, and the pause is what lets each one read as its own.
        collectionsStack.spacing = Theme.Spacing.xxl
        collectionsStack.accessibilityIdentifier = "homeCollections"
        contentStack.addArrangedSubview(collectionsStack)

        // What the user saved, last: the one part of the catalog they curated.
        makeSavedStrips()

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
        title: String, titleIdentifier: String? = nil, subtitle: String? = nil,
        badge: String? = nil,
        strip: UICollectionView, height: CGFloat,
        actionIdentifier: String?, action: (() -> Void)?
    ) -> UIStackView {
        let header = sectionHeader(
            title,
            titleIdentifier: titleIdentifier,
            subtitle: subtitle,
            badge: badge,
            actionTitle: action == nil ? nil : String(localized: "See All"),
            actionIdentifier: actionIdentifier,
            action: action)
        let section = UIStackView(arrangedSubviews: [header, strip])
        section.axis = .vertical
        section.spacing = Theme.Spacing.sm
        section.isHidden = true
        strip.heightAnchor.constraint(equalToConstant: height).isActive = true
        // Collection sections are shown on creation; the recents section is
        // shown by `reload()` once there is something in it.
        section.isHidden = strip === recentsStrip
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
                title: String(localized: "Grid"), caption: String(localized: "1:1 post"),
                symbol: "square.grid.2x2.fill",
                identifier: "newProjectButton"
            ) { [weak self] in
                Haptics.tap()
                self?.onNewProject?()
            },
            QuickStartChip(
                title: String(localized: "Shapes"), caption: String(localized: "freeform"),
                symbol: "triangle.fill",
                identifier: "polygonQuickStartButton"
            ) { [weak self] in
                Haptics.tap()
                self?.onNewPolygon?()
            },
            QuickStartChip(
                title: String(localized: "Video"), caption: String(localized: "9:16 reel"),
                symbol: "play.rectangle.fill",
                identifier: "videoCollageButton"
            ) { [weak self] in
                Haptics.tap()
                self?.onNewVideoCollage?()
            },
            // Home and the "+" sheet overlap on purpose — the app's signature
            // format has to be on both of its front doors.
            QuickStartChip(
                title: String(localized: "Carousel"), caption: String(localized: "4:5 swipe"),
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
        // One row of four at standard text sizes; two rows of two at
        // accessibility sizes, where four chips abreast truncate every title.
        // The pairs stack vertically and each pair stays a row.
        let pairs = [UIStackView(arrangedSubviews: Array(chips[0..<2])),
                     UIStackView(arrangedSubviews: Array(chips[2..<4]))]
        for pair in pairs {
            pair.axis = .horizontal
            pair.spacing = Theme.Spacing.sm
            pair.distribution = .fillEqually
        }
        let row = UIStackView(arrangedSubviews: pairs)
        row.spacing = Theme.Spacing.sm
        row.distribution = .fillEqually
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(
            top: 0, left: Theme.Spacing.md, bottom: 0, right: Theme.Spacing.md)
        row.accessibilityIdentifier = "quickStartChipRow"
        row.stackVerticallyAtAccessibilitySizes(verticalAlignment: .fill, horizontalAlignment: .fill)

        let section = UIStackView(arrangedSubviews: [header, row])
        section.axis = .vertical
        section.spacing = Theme.Spacing.sm
        return section
    }

    private func sectionHeader(
        _ title: String, titleIdentifier: String? = nil, subtitle: String? = nil,
        badge: String? = nil,
        actionTitle: String? = nil, actionIdentifier: String? = nil,
        action: (() -> Void)? = nil
    ) -> SectionHeaderView {
        SectionHeaderView(
            title: title, titleIdentifier: titleIdentifier, subtitle: subtitle, badge: badge,
            actionTitle: actionTitle, actionIdentifier: actionIdentifier, action: action)
    }

    private func makeShowcaseStrip(
        identifier: String, itemWidth: CGFloat, height: CGFloat,
        cellClass: AnyClass, reuseID: String, spacing: CGFloat = Theme.Spacing.sm
    ) -> UICollectionView {
        let item = NSCollectionLayoutItem(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1))
        )
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .absolute(itemWidth),
                heightDimension: .absolute(height)),
            subitems: [item]
        )
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuous
        section.interGroupSpacing = spacing
        section.contentInsets = NSDirectionalEdgeInsets(
            top: 0, leading: Theme.Spacing.md, bottom: 0, trailing: Theme.Spacing.md)
        let layout = UICollectionViewCompositionalLayout(section: section)

        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.showsHorizontalScrollIndicator = false
        view.dataSource = self
        view.delegate = self
        // The next cards along are drawn before the strip scrolls them in.
        view.prefetchDataSource = self
        view.accessibilityIdentifier = identifier
        view.register(cellClass, forCellWithReuseIdentifier: reuseID)
        return view
    }
}

// MARK: - Data source & delegate

extension HomeViewController: UICollectionViewDataSource, UICollectionViewDelegate {

    private func stripInfo(for collectionView: UICollectionView) -> CollectionStrip? {
        (strips + savedStrips).first { $0.strip === collectionView }
    }

    /// The favourites item a card stands for, or nil for cards that cannot be
    /// saved (video showcases, recents, suggestions).
    private func favouriteItem(in collectionView: UICollectionView, at indexPath: IndexPath) -> FavoritesStore.Item? {
        switch stripInfo(for: collectionView)?.items {
        case let .photo(templates)?:
            guard templates.indices.contains(indexPath.item) else { return nil }
            return FavoritesStore.Item(kind: .photo, id: templates[indexPath.item].id)
        case let .carousel(templates)?:
            guard templates.indices.contains(indexPath.item) else { return nil }
            return FavoritesStore.Item(kind: .carousel, id: templates[indexPath.item].id)
        default:
            return nil
        }
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if collectionView === recentsStrip { return recentProjects.count }
        if collectionView === suggestionsStrip { return suggestions.count }
        return stripInfo(for: collectionView)?.items.count ?? 0
    }

    func collectionView(
        _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        if collectionView === recentsStrip { return recentCard(collectionView, at: indexPath) }
        if collectionView === suggestionsStrip { return suggestionCard(collectionView, at: indexPath) }
        switch stripInfo(for: collectionView)?.items {
        case let .photo(templates)?:
            return photoCard(collectionView, at: indexPath, templates: templates)
        case let .video(showcases)?:
            return videoCard(collectionView, at: indexPath, showcases: showcases)
        case let .carousel(templates)?:
            return carouselCard(collectionView, at: indexPath, templates: templates)
        case nil:
            return collectionView.dequeueReusableCell(
                withReuseIdentifier: HomeCardCell.reuseID, for: indexPath)
        }
    }

    private func photoCard(
        _ collectionView: UICollectionView, at indexPath: IndexPath, templates: [CollageTemplate]
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: HomeCardCell.reuseID, for: indexPath)
        guard let card = cell as? HomeCardCell,
              templates.indices.contains(indexPath.item) else { return cell }
        let template = templates[indexPath.item]
        let item = FavoritesStore.Item(kind: .photo, id: template.id)
        let photoZones = template.cells.filter { $0.zoneType == .photo }.count
        card.configure(HomeCardCell.Content(
            name: template.name,
            meta: HomeCardMeta.photos(photoZones, ratio: template.canvasAspectRatio),
            identifier: "showcaseTemplate-\(template.id)",
            style: stripInfo(for: collectionView)?.style ?? .poster,
            // The schematic is the fallback, not the plan: it only appears for a
            // template the manifest does not dress, which today means only when
            // the manifest itself failed to load.
            artwork: .still(
                cached: TemplateService.shared.cachedShowcasePreview(for: template),
                load: { await TemplateService.shared.loadShowcasePreview(for: template) }),
            locked: !TemplateService.shared.canOpen(template),
            saved: favorites.isSaved(item)))
        card.accessibilityCustomActions = [FavouriteContextMenu.customAction(for: item) {}]
        return cell
    }

    private func videoCard(
        _ collectionView: UICollectionView, at indexPath: IndexPath,
        showcases: [SampleContentManifest.VideoShowcase]
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: HomeCardCell.reuseID, for: indexPath)
        guard let card = cell as? HomeCardCell,
              showcases.indices.contains(indexPath.item) else { return cell }
        let showcase = showcases[indexPath.item]
        let poster = sampleContent.image(named: showcase.poster)
        card.configure(HomeCardCell.Content(
            name: showcase.displayTitle,
            meta: HomeCardMeta.video(size: poster?.size),
            identifier: "showcaseVideo-\(showcase.id)",
            style: .reel,
            artwork: .video(poster: poster, loop: sampleContent.videoURL(named: showcase.loop))))
        return cell
    }

    private func carouselCard(
        _ collectionView: UICollectionView, at indexPath: IndexPath, templates: [CarouselTemplate]
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: HomeCardCell.reuseID, for: indexPath)
        guard let card = cell as? HomeCardCell,
              templates.indices.contains(indexPath.item) else { return cell }
        let template = templates[indexPath.item]
        let item = FavoritesStore.Item(kind: .carousel, id: template.id)
        card.configure(HomeCardCell.Content(
            name: template.name,
            // How many pages the post has is the one fact the picture cannot
            // state, and the one a user comparing carousels wants first.
            meta: HomeCardMeta.pages(template.frameCount, ratio: template.canvasAspectRatio),
            identifier: "showcaseCarousel-\(template.id)",
            style: .deck,
            // The first three slides, each rendered at its true shape and dealt
            // as a stack — not composited into one strip and fitted on a blur.
            // Drawn off the main actor, like the hero's deck.
            artwork: .slides(
                cached: TemplateService.shared.cachedShowcaseFrames(
                    for: template, limit: 3, allowsSchematic: false),
                load: { await TemplateService.shared.showcaseFramesInBackground(for: template, limit: 3) }),
            // Until Step 07 there was no `canOpen` overload to ask, so four
            // premium carousels wore no lock and opened free.
            locked: !TemplateService.shared.canOpen(template),
            saved: favorites.isSaved(item),
            pages: template.frameCount))
        card.accessibilityCustomActions = [FavouriteContextMenu.customAction(for: item) {}]
        return cell
    }

    private func recentCard(
        _ collectionView: UICollectionView, at indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ProjectCardCell.reuseID, for: indexPath)
        if let card = cell as? ProjectCardCell, recentProjects.indices.contains(indexPath.item) {
            card.configure(with: recentProjects[indexPath.item])
        }
        return cell
    }

    private func suggestionCard(
        _ collectionView: UICollectionView, at indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ShowcaseTemplateCell.reuseID, for: indexPath)
        guard let card = cell as? ShowcaseTemplateCell,
              suggestions.indices.contains(indexPath.item) else { return cell }
        let suggestion = suggestions[indexPath.item]
        card.configure(
            name: suggestion.template.displayName,
            identifier: "suggestedLayout-\(suggestion.template.rawValue)",
            preview: { suggestion.thumbnail })
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        Haptics.tap()

        if collectionView === recentsStrip {
            guard recentProjects.indices.contains(indexPath.item) else { return }
            Analytics.track(.recentResumed)
            onOpenProject?(recentProjects[indexPath.item].id)
            return
        }
        if collectionView === suggestionsStrip {
            guard suggestions.indices.contains(indexPath.item) else { return }
            let template = suggestions[indexPath.item].template
            Analytics.track(.suggestionOpened(template: template.rawValue))
            onSelectSuggestedLayout?(template)
            return
        }
        guard let info = stripInfo(for: collectionView) else { return }
        switch info.items {
        case let .photo(templates):
            guard templates.indices.contains(indexPath.item) else { return }
            let template = templates[indexPath.item]
            Analytics.track(.templateOpened(id: template.id, source: info.collection.id))
            onSelectTemplate?(template)
        case let .video(showcases):
            guard showcases.indices.contains(indexPath.item) else { return }
            let showcase = showcases[indexPath.item]
            Analytics.track(.templateOpened(id: showcase.id, source: info.collection.id))
            onSelectVideoShowcase?(showcase)
        case let .carousel(templates):
            guard templates.indices.contains(indexPath.item) else { return }
            let template = templates[indexPath.item]
            Analytics.track(.templateOpened(id: template.id, source: info.collection.id))
            onSelectCarouselTemplate?(template)
        }
    }

    // MARK: Save on long press (phase 4)

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let item = favouriteItem(in: collectionView, at: indexPath) else { return nil }
        // The toggle announces itself; `favouritesChanged` redraws every strip.
        return FavouriteContextMenu.configuration(for: item, at: indexPath, stash: menuStash) {}
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

    /// Only a card that is actually on screen — and only while Home is — gets to
    /// hold a video pipeline.
    func collectionView(
        _ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        guard isVisible, playingStrips.contains(ObjectIdentifier(collectionView)),
              let card = cell as? HomeCardCell else { return }
        card.play()
    }

    func collectionView(
        _ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        (cell as? HomeCardCell)?.stop()
    }
}

// MARK: - Home's own scroll

extension HomeViewController {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === self.scrollView else { return }
        updateViewportPlayback()
    }

}

// MARK: - Prefetching

extension HomeViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let items = indexPaths.map(\.item)
        switch stripInfo(for: collectionView)?.items {
        case let .photo(templates)?:
            TemplateService.shared.prefetchPreviews(
                for: items.filter(templates.indices.contains).map { templates[$0] })
        case let .carousel(templates)?:
            TemplateService.shared.prefetchFrames(
                for: items.filter(templates.indices.contains).map { templates[$0] }, limit: 3)
        default:
            break
        }
    }
}
