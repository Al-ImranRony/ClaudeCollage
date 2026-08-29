//
//  HeroShowcaseView.swift
//  Caroullage
//
//  Step 07 — the thing you see first.
//
//  Home used to open on a row of empty layout schematics, which told a new user
//  what the app is BUILT of rather than what it MAKES. This card does the
//  opposite: one finished, photo-real piece of work at a time, cycling slowly, so
//  the first screen is a portfolio rather than a parts bin. Every page is a real
//  template rendered through the real renderer, and tapping one opens exactly
//  that structure with the photo zones empty — the promise is structural, not
//  aspirational.
//
//  Two decisions worth the ink:
//
//  1. The pager is a horizontally-scrolling collection view with `isPagingEnabled`
//     rather than a vertical one with an `.groupPaging` orthogonal section. An
//     orthogonal section hosts its cells in a private inner scroll view that
//     `scrollToItem` does not reliably drive and whose `scrollViewDid*` callbacks
//     never reach this view's delegate — and auto-advance needs both. A real
//     paging scroll view gives programmatic advance, drag pause/resume and page
//     sync for free.
//  2. Motion is opt-in per page. Only the page that is actually on screen — and
//     only while Home is on screen — is allowed to hold a video decoder; see
//     `updateLoopPlayback()`.
//

import UIKit

@MainActor
final class HeroShowcaseView: UIView {

    /// One full-bleed page of the hero.
    struct Page {
        /// How the preview is fitted to the card.
        ///
        /// A carousel's showcase preview is a wide three-page strip; filling the
        /// hero with it crops away everything except a sliver of the middle page,
        /// which destroys the one thing the strip exists to say (that this is a
        /// multi-page post). Those pages are fitted whole onto a blurred bed of
        /// themselves instead — the letterboxing then reads as a deliberate
        /// presentation rather than as a layout accident.
        ///
        /// The same argument turned out to apply to any artwork whose shape is
        /// far from the card's, which is what `.automatic` — the default —
        /// measures. See `HeroPageCell.fitting(for:artwork:card:)`.
        enum Presentation { case fill, fitOnBlurredBed, automatic }

        let title: String
        let subtitle: String
        let identifier: String
        var presentation: Presentation = .automatic
        /// A video page's still frame, shown instantly and kept as the permanent
        /// state whenever motion is not allowed.
        var poster: UIImage?
        /// Non-nil only for video pages.
        var loopURL: URL?
        /// Rendered lazily, off the first layout pass. A closure rather than an
        /// image so a page that scrolls away before it is drawn costs nothing.
        var preview: () -> CGImage? = { nil }
        let onTap: () -> Void
    }

    /// The hero is a card, not a band: the corner radius and shadow are the same
    /// language the gallery's cards speak.
    private lazy var collectionView = makeCollectionView()
    private let pageControl = UIPageControl()
    private var pages: [Page] = []
    private var rotation: HeroRotationController?
    /// Whether Home is on screen. Nothing rotates and nothing decodes while false.
    private var isActive = false

    override init(frame: CGRect) {
        super.init(frame: frame)

        // The shadow lives on this (non-clipping) view; the collection view is
        // what rounds and clips the content.
        applyCardShadow()

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(collectionView)

        // Bottom-trailing, over the scrim: the scrim is the only part of an
        // arbitrary photograph whose contrast is guaranteed, so it is the only
        // place white dots are certain to be legible.
        pageControl.currentPageIndicatorTintColor = Theme.Color.textOnToast
        pageControl.pageIndicatorTintColor = Theme.Color.textOnToast.withAlphaComponent(0.4)
        pageControl.hidesForSinglePage = true
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        pageControl.addTarget(self, action: #selector(pageControlChanged), for: .valueChanged)
        addSubview(pageControl)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),

            pageControl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.Spacing.xs),
            pageControl.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Theme.Spacing.xs),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds, cornerRadius: Theme.Radius.lg
        ).cgPath
    }

    // MARK: - Configuration

    /// Replaces the hero's contents. Hides the whole card when there is nothing
    /// to show — a hero with no pages is worse than no hero.
    func configure(pages: [Page]) {
        self.pages = pages
        isHidden = pages.isEmpty

        collectionView.reloadData()
        // A fresh set of pages starts at the first one; without this the old
        // content offset survives and the hero opens mid-page.
        collectionView.setContentOffset(.zero, animated: false)

        pageControl.numberOfPages = pages.count
        pageControl.currentPage = 0

        // A controller built for the previous page count would advance past the
        // end of the new one.
        rotation?.stop()
        guard !pages.isEmpty else {
            rotation = nil
            return
        }
        let controller = HeroRotationController(
            pageCount: pages.count,
            reduceMotion: { Theme.Motion.isReduced },
            scheduler: HeroRotationController.timerScheduler()
        )
        controller.onAdvance = { [weak self] page in self?.advance(to: page) }
        rotation = controller
        if isActive { controller.start() }
        updateLoopPlayback()
    }

    /// Home appearing / disappearing. Everything expensive hangs off this: the
    /// rotation timer and every video decoder the visible page might hold.
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            rotation?.start()
        } else {
            rotation?.stop()
        }
        updateLoopPlayback()
    }

    // MARK: - Paging

    private var currentPage: Int {
        guard collectionView.bounds.width > 0 else { return 0 }
        let raw = collectionView.contentOffset.x / collectionView.bounds.width
        return min(max(Int(raw.rounded()), 0), max(pages.count - 1, 0))
    }

    private func advance(to page: Int) {
        guard pages.indices.contains(page) else { return }
        collectionView.scrollToItem(
            at: IndexPath(item: page, section: 0), at: .centeredHorizontally, animated: true)
        pageControl.currentPage = page
    }

    @objc private func pageControlChanged() {
        let page = pageControl.currentPage
        guard pages.indices.contains(page) else { return }
        rotation?.noteUserMoved(to: page)
        collectionView.scrollToItem(
            at: IndexPath(item: page, section: 0), at: .centeredHorizontally, animated: true)
    }

    /// The user's finger landed somewhere: adopt that page as the one auto-advance
    /// continues from, rather than snapping back to where the timer thought it was.
    private func settle() {
        let page = currentPage
        pageControl.currentPage = page
        rotation?.noteUserMoved(to: page)
        rotation?.resume()
        updateLoopPlayback()
    }

    /// Exactly one page may hold a video pipeline, and only while Home is on
    /// screen. Everything else falls back to its poster, which is a complete
    /// picture in its own right.
    private func updateLoopPlayback() {
        let page = currentPage
        for cell in collectionView.visibleCells {
            guard let heroCell = cell as? HeroPageCell,
                  let indexPath = collectionView.indexPath(for: cell) else { continue }
            if isActive && indexPath.item == page {
                heroCell.play()
            } else {
                heroCell.stop()
            }
        }
    }

    private func makeCollectionView() -> UICollectionView {
        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)))
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)),
            subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.scrollDirection = .horizontal
        let layout = UICollectionViewCompositionalLayout(section: section, configuration: configuration)

        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = Theme.Color.cellWell
        view.isPagingEnabled = true
        view.showsHorizontalScrollIndicator = false
        // The hero sits inside a vertical scroll view whose own insets must not
        // shift the pages, or paging lands half a page off.
        view.contentInsetAdjustmentBehavior = .never
        view.layer.cornerRadius = Theme.Radius.lg
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        view.dataSource = self
        view.delegate = self
        view.accessibilityIdentifier = "heroShowcase"
        view.register(HeroPageCell.self, forCellWithReuseIdentifier: HeroPageCell.reuseID)
        return view
    }
}

// MARK: - Data source & delegate

extension HeroShowcaseView: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        pages.count
    }

    func collectionView(
        _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: HeroPageCell.reuseID, for: indexPath)
        if let heroCell = cell as? HeroPageCell, pages.indices.contains(indexPath.item) {
            heroCell.configure(with: pages[indexPath.item])
        }
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        updateLoopPlayback()
    }

    func collectionView(
        _ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        (cell as? HeroPageCell)?.stop()
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard pages.indices.contains(indexPath.item) else { return }
        Haptics.tap()
        pages[indexPath.item].onTap()
    }

    // A finger on the hero and a timer moving it are the same gesture arriving
    // twice; pausing for the length of the touch is cheaper than tearing the
    // scheduler down and reinstalling it (which would reset its interval).
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        rotation?.pause()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // The dot tracks the swipe rather than jumping once it ends.
        pageControl.currentPage = currentPage
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { settle() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        settle()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        // An auto-advance finished: hand the decoder to whichever page landed.
        updateLoopPlayback()
    }
}

// MARK: - Page cell

/// One hero page: a photo-real still (or a silent looping video), a scrim, and
/// the title/subtitle pair that names what tapping it will make.
@MainActor
private final class HeroPageCell: UICollectionViewCell {
    static let reuseID = "HeroPageCell"

    /// How much of the card's height the caption's scrim covers. Taller than the
    /// strip card's because the hero carries two lines of type, not one.
    private static let scrimHeightRatio: CGFloat = 0.45

    /// How far a preview's proportions may stray from the card's before filling
    /// stops showing a template and starts showing a crop.
    ///
    /// The hero card is about 1 : 0.84. Filling it with `story-caption-hero` —
    /// a 9:16 template whose whole design is a photo above a caption band —
    /// shows 47% of the artwork, which on this catalog's sample photography is
    /// an extreme close-up of one face with the template's own composition
    /// cropped away entirely. The hero then reads as a photo viewer, which is
    /// the one thing it must not do. A 1:1 or 4:5 template loses only its
    /// margins under the same crop and still reads whole.
    ///
    /// The line is drawn on the RATIO between the two aspect ratios rather than
    /// on either one, so it keeps meaning the same thing if the card's
    /// proportions change: fit when the artwork is more than 1.8x as elongated
    /// as the card — equivalently, when filling would crop away more than 44%
    /// of one axis. Against the shipped catalog that puts 1:1 (1.19), 4:5
    /// (1.49) and 3:4 (1.59) on the fill side and 9:16 (2.12) and the
    /// three-page carousel strip (2.02) on the fit side, with real air either
    /// way rather than a boundary a new template could stumble across.
    private static let fitDivergenceThreshold: CGFloat = 1.8

    /// The shape a preview takes inside the card.
    private enum Fitting {
        /// Edge to edge, cropped to the card.
        case fill
        /// Whole, seated in the card's region ABOVE the caption, on a blurred
        /// blow-up of itself.
        ///
        /// Above rather than behind, for both shapes of artwork. A wide strip
        /// centred in the card would land exactly where the two lines of type
        /// go; a tall template large enough to fill the card's height puts its
        /// OWN authored caption band ("MOMENTS") under the hero's title, and two
        /// captions in the same 40pt reads as a bug rather than as a poster.
        case onBed
    }

    /// Resolves a page's declared presentation against what was actually
    /// rendered. `artwork` is `.zero` before the render lands, which is why an
    /// explicitly-fitted page still starts in the geometry it asked for.
    private static func fitting(
        for presentation: HeroShowcaseView.Page.Presentation,
        artwork: CGSize, card: CGSize
    ) -> Fitting {
        switch presentation {
        case .fill:
            return .fill
        case .fitOnBlurredBed:
            return .onBed
        case .automatic:
            guard artwork.width > 0, artwork.height > 0, card.width > 0, card.height > 0
            else { return .fill }
            let artAspect = artwork.height / artwork.width
            let cardAspect = card.height / card.width
            let divergence = max(artAspect / cardAspect, cardAspect / artAspect)
            return divergence > Self.fitDivergenceThreshold ? .onBed : .fill
        }
    }

    private let bedImageView = UIImageView()
    // Ultra-thin, not thick: the bed is meant to read as a soft, out-of-focus
    // blow-up OF THE ARTWORK. A thick material buried it — the card came out a
    // black box with a small picture floating in it.
    private let bedBlur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let imageView = UIImageView()
    private let playerView = LoopingPreviewPlayerView()
    private let scrim = ShowcaseScrimView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let captionStack = UIStackView()
    private var previewTask: Task<Void, Never>?
    /// The preview's two geometries, swapped by `apply(_:isVideo:)`.
    private var edgeConstraints: [NSLayoutConstraint] = []
    private var aboveCaptionConstraints: [NSLayoutConstraint] = []

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.backgroundColor = Theme.Color.cellWell
        contentView.clipsToBounds = true

        // The bed is the same picture, blown up and blurred, so a fitted preview
        // sits on something that belongs to it instead of on a flat grey box.
        bedImageView.contentMode = .scaleAspectFill
        bedImageView.clipsToBounds = true
        bedImageView.isHidden = true
        bedBlur.isHidden = true

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true

        playerView.isHidden = true

        titleLabel.font = Theme.Typography.title2
        // White in both appearances: this type never touches an app surface — it
        // is always over the scrim, which is always dark — so the surface tokens
        // would flip it to near-black on black in light mode. `textOnToast` is
        // the token for ink that floats over arbitrary content.
        titleLabel.textColor = Theme.Color.textOnToast
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        // Half the catalog is authored on white; the scrim alone does not hold
        // white type up over it. See `applyShowcaseCaptionShadow`.
        titleLabel.applyShowcaseCaptionShadow()

        subtitleLabel.font = Theme.Typography.subheadline
        subtitleLabel.textColor = Theme.Color.textOnToast.withAlphaComponent(0.85)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.numberOfLines = 1
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.applyShowcaseCaptionShadow()

        // Stored rather than local now: the fitted geometry hangs off its top
        // edge, so the image view has to be able to reach it.
        captionStack.addArrangedSubview(titleLabel)
        captionStack.addArrangedSubview(subtitleLabel)
        captionStack.axis = .vertical
        captionStack.spacing = Theme.Spacing.xxs / 2

        for subview in [bedImageView, bedBlur, imageView, playerView, scrim, captionStack] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(subview)
        }

        NSLayoutConstraint.activate([
            bedImageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            bedImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bedImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bedImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            bedBlur.topAnchor.constraint(equalTo: contentView.topAnchor),
            bedBlur.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bedBlur.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bedBlur.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            playerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            playerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            playerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            scrim.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrim.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            scrim.heightAnchor.constraint(
                equalTo: contentView.heightAnchor, multiplier: Self.scrimHeightRatio),

            captionStack.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: Theme.Spacing.md),
            captionStack.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor, constant: -Theme.Spacing.md),
            // Leaves the bottom-trailing corner to the page control, which lives
            // on the hero rather than in the cell and so cannot be constrained to
            // directly.
            captionStack.widthAnchor.constraint(
                lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.68),
        ])

        // Two geometries for one image view: edge to edge, and the band above the
        // caption. The second is anchored to the caption rather than set as a
        // share of the card's height so that it still clears the type at the
        // accessibility text sizes, where the two lines are twice as tall.
        edgeConstraints = [
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ]
        aboveCaptionConstraints = [
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(
                equalTo: captionStack.topAnchor, constant: -Theme.Spacing.sm),
        ]
        NSLayoutConstraint.activate(edgeConstraints)

        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(with page: HeroShowcaseView.Page) {
        titleLabel.text = page.title
        subtitleLabel.text = page.subtitle
        accessibilityIdentifier = page.identifier
        accessibilityLabel = page.title
        accessibilityValue = page.subtitle

        let isVideo = page.loopURL != nil
        playerView.isHidden = !isVideo
        imageView.isHidden = isVideo
        // Configured either way: passing nil is what releases a pipeline this
        // cell was holding for the video page it used to show.
        playerView.configure(loopURL: page.loopURL, poster: isVideo ? page.poster : nil)

        // Nothing has been rendered yet, so this is only what the page DECLARES.
        // It is re-resolved below against the artwork that actually arrives.
        apply(
            Self.fitting(for: page.presentation, artwork: .zero, card: contentView.bounds.size),
            isVideo: isVideo)

        previewTask?.cancel()
        guard !isVideo else { return }
        previewTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            let rendered = page.preview()
            guard !Task.isCancelled, let self else { return }
            let image = rendered.map { UIImage(cgImage: $0) }
            // Measured now rather than inside the animation block, so it reads a
            // settled layout rather than one mid-transition.
            let fitting = Self.fitting(
                for: page.presentation, artwork: image?.size ?? .zero,
                card: self.contentView.bounds.size)
            // A fade, not a pop: the well → photograph swap is very visible at
            // hero size, and the geometry can change with it (a tall template
            // arriving on a card that had been laid out to fill). Reduce Motion
            // shortens it rather than removing it — a cross-dissolve is not
            // motion.
            UIView.transition(
                with: self.contentView,
                duration: Theme.Motion.duration(Theme.Motion.standard),
                options: [.transitionCrossDissolve, .allowUserInteraction]
            ) {
                self.apply(fitting, isVideo: isVideo)
                self.imageView.image = image
                self.bedImageView.image = fitting == .fill ? nil : image
                self.contentView.layoutIfNeeded()
            }
        }
    }

    /// Puts the image view into one of the two geometries and shows or hides the
    /// blurred bed to match.
    private func apply(_ fitting: Fitting, isVideo: Bool) {
        let fits = fitting != .fill
        imageView.contentMode = fits ? .scaleAspectFit : .scaleAspectFill

        NSLayoutConstraint.deactivate(fits ? edgeConstraints : aboveCaptionConstraints)
        NSLayoutConstraint.activate(fits ? aboveCaptionConstraints : edgeConstraints)

        // A video page never grows a bed: it fills by construction, and there is
        // no still to blow up behind it.
        bedImageView.isHidden = fitting == .fill || isVideo
        bedBlur.isHidden = bedImageView.isHidden
    }

    func play() { playerView.play() }
    func stop() { playerView.stop() }

    override func prepareForReuse() {
        super.prepareForReuse()
        // A render in flight belongs to the page this cell USED to show.
        previewTask?.cancel()
        previewTask = nil
        playerView.stop()
        playerView.configure(loopURL: nil, poster: nil)
        imageView.image = nil
        bedImageView.image = nil
        titleLabel.text = nil
        subtitleLabel.text = nil
        accessibilityValue = nil
    }
}
