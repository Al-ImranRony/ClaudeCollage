//
//  HeroShowcaseView.swift
//  Caroullage
//
//  Step 07 — the app's case, made in one card.
//
//  Home used to open on a row of empty layout schematics, which told a new user
//  what the app is BUILT of rather than what it MAKES. This card does the
//  opposite: one finished, photo-real piece of work at a time, cycling slowly, so
//  Home argues with a portfolio rather than a parts bin. Every page is a real
//  template rendered through the real renderer, and tapping one opens exactly
//  that structure with the photo zones empty — the promise is structural, not
//  aspirational.
//
//  Each page stands on the stage that presents its kind best — full bleed, a
//  story frame, a self-swiping carousel deck, a before/after wipe — with the
//  caption and position dots in the same bottom-leading place on all of them
//  (see `Page.Stage` and HeroStageViews.swift). The rotation leads with video
//  and spreads it through the run, because motion is what the eye catches.
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
//     only while Home is on screen — is allowed to hold a video decoder or run
//     its stage's animation; see `updateLoopPlayback()`.
//

import UIKit

@MainActor
final class HeroShowcaseView: UIView {

    /// One page of the hero.
    struct Page {
        /// How the page presents its artwork. See `HeroStageViews.swift`.
        enum Stage: Equatable {
            /// Edge to edge, under a scrim. Landscape and near-square work.
            case fill
            /// Tall work (a 9:16 story or reel) standing whole as a story frame
            /// on the trailing side of a lit stage. `aspect` is width / height.
            case story(aspect: CGFloat)
            /// A carousel's frames as a deck that swipes itself.
            case deck
            /// A before/after wipe. `frames` is `[before, after]`.
            case compare

            /// Fill unless the artwork is tall enough that filling the card
            /// would show a crop of it rather than it: past 3:2 portrait, a fill
            /// throws away more than half the height.
            static func resolve(aspect: CGFloat) -> Stage {
                guard aspect > 0 else { return .fill }
                return 1 / aspect >= 1.5 ? .story(aspect: aspect) : .fill
            }
        }

        let title: String
        let subtitle: String
        let identifier: String
        var stage: Stage = .fill
        /// A video page's still frame, shown instantly and kept as the permanent
        /// state whenever motion is not allowed.
        var poster: UIImage?
        /// Non-nil only for video pages.
        var loopURL: URL?
        /// The still a `fill` or `story` page shows. Rendered lazily, off the
        /// first layout pass, so a page that scrolls away before it is drawn
        /// costs nothing.
        var preview: () -> CGImage? = { nil }
        /// The images a `deck` or `compare` page deals out. Lazy for the same
        /// reason. Empty falls back to `preview`, filled.
        /// Async so the page can draw them off the main actor.
        var frames: @MainActor () async -> [UIImage] = { [] }
        let onTap: () -> Void
    }

    /// The hero is a card, not a band: the corner radius and shadow are the same
    /// language the gallery's cards speak.
    private lazy var collectionView = makeCollectionView()
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

        // No page control on the card: each page draws its own position under
        // its title (`HeroDotsView`), the one place every stage keeps dark.

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
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
            // Five seconds, not four: the stages move on their own now, and a
            // deck needs time for a couple of swipes before the page changes.
            scheduler: HeroRotationController.timerScheduler(interval: Self.dwell)
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

    /// How long each page stays up. The story frame's progress segment fills
    /// over exactly this long.
    static let dwell: TimeInterval = 5

    // MARK: - Paging

    private var currentPage: Int {
        guard collectionView.bounds.width > 0 else { return 0 }
        let raw = collectionView.contentOffset.x / collectionView.bounds.width
        return min(max(Int(raw.rounded()), 0), max(pages.count - 1, 0))
    }

    /// The timer's advance: a cross-fade, not a slide (Home retention, phase 4).
    ///
    /// `scrollToItem(animated:)` slid the whole card sideways every four
    /// seconds while the user was reading it, which is what the showcase spec
    /// asked NOT to happen. `UIView.transition(.transitionCrossDissolve)`
    /// snapshots the from-state itself, so the page moves without animation
    /// under the fade and nothing else changes: the dots still track the
    /// offset, a finger still pages the collection view directly, and the
    /// rotation controller is untouched.
    ///
    /// The visible players are stopped first: a live `AVPlayerLayer` snapshots
    /// black, and the poster underneath is a complete picture in its own right.
    /// `scrollViewDidEndScrollingAnimation` does not fire for a non-animated
    /// offset change, so playback is handed on in the completion instead.
    private func advance(to page: Int) {
        guard pages.indices.contains(page),
              let attributes = collectionView.layoutAttributesForItem(at: IndexPath(item: page, section: 0))
        else { return }
        let target = CGPoint(x: attributes.frame.minX, y: 0)

        // Off screen, or mid-drag: no fade to see, and a finger owns the offset.
        guard window != nil, !collectionView.isDragging, !collectionView.isDecelerating else {
            collectionView.setContentOffset(target, animated: false)
            updateLoopPlayback()
            return
        }

        for case let cell as HeroPageCell in collectionView.visibleCells { cell.stop() }
        UIView.transition(
            with: collectionView,
            duration: Theme.Motion.duration(Theme.Motion.slow),
            options: [.transitionCrossDissolve, .allowUserInteraction]
        ) {
            self.collectionView.setContentOffset(target, animated: false)
            self.collectionView.layoutIfNeeded()
        } completion: { _ in
            self.updateLoopPlayback()
        }
    }

    /// The user's finger landed somewhere: adopt that page as the one auto-advance
    /// continues from, rather than snapping back to where the timer thought it was.
    private func settle() {
        let page = currentPage
        rotation?.noteUserMoved(to: page)
        // A fresh period from where the finger landed: otherwise the timer keeps
        // its old phase and the page the user just chose can leave a second later,
        // halfway through its story progress.
        rotation?.stop()
        if isActive { rotation?.start() }
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
            heroCell.configure(with: pages[indexPath.item], index: indexPath.item, of: pages.count)
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

/// One hero page: a stage (see `Page.Stage`), and the title, subtitle and
/// position dots that name what tapping it will make.
///
/// The caption sits bottom-leading on every stage. The stages vary a lot in
/// what they show, so the type staying in one place is what keeps the hero
/// reading as one component rather than five different cards.
@MainActor
private final class HeroPageCell: UICollectionViewCell {
    static let reuseID = "HeroPageCell"

    /// How much of the card's height the scrim covers on the full-bleed stages.
    private static let scrimHeightRatio: CGFloat = 0.5
    private static let inset = Theme.Spacing.md

    private let backdrop = HeroStageBackdropView()
    /// Hosts the shadow of a story frame; the clipping and rounding happen on
    /// `mediaView` inside it, or the clip would cut the shadow away.
    private let mediaFrame = UIView()
    private let mediaView = UIView()
    private let imageView = UIImageView()
    private let playerView = LoopingPreviewPlayerView()
    private let storyChrome = HeroStoryChromeView()
    private let deckView = HeroDeckStageView()
    private let compareView = HeroCompareStageView()
    private let scrim = ShowcaseScrimView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let dotsView = HeroDotsView()
    private let captionStack = UIStackView()

    private var stage: HeroShowcaseView.Page.Stage = .fill
    private var previewTask: Task<Void, Never>?
    /// Whether the hero wants this page moving. Content that lands after
    /// `play()` (the deck's frames, rendered lazily) starts on arrival.
    private var wantsMotion = false

    private var fillConstraints: [NSLayoutConstraint] = []
    private var storyConstraints: [NSLayoutConstraint] = []
    private var storyAspect: NSLayoutConstraint?
    private var captionWide: NSLayoutConstraint!
    private var captionBesideStory: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.backgroundColor = UIColor(white: 0.08, alpha: 1)
        contentView.clipsToBounds = true

        mediaFrame.layer.shadowColor = UIColor.black.cgColor
        mediaFrame.layer.shadowRadius = 18
        mediaFrame.layer.shadowOffset = CGSize(width: 0, height: 10)

        mediaView.clipsToBounds = true
        mediaView.layer.cornerCurve = .continuous
        mediaView.backgroundColor = Theme.Color.cellWell

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        playerView.isHidden = true

        // White in both appearances: this type never touches an app surface — it
        // always sits on the scrim or the dark stage — so the surface tokens
        // would flip it to near-black on black in light mode.
        titleLabel.font = Theme.Typography.title
        titleLabel.textColor = Theme.Color.textOnToast
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.applyShowcaseCaptionShadow()

        subtitleLabel.font = Theme.Typography.subheadline
        subtitleLabel.textColor = Theme.Color.textOnToast.withAlphaComponent(0.85)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.applyShowcaseCaptionShadow()

        captionStack.axis = .vertical
        captionStack.alignment = .leading
        captionStack.spacing = Theme.Spacing.xxs / 2
        for view in [titleLabel, subtitleLabel, dotsView] { captionStack.addArrangedSubview(view) }
        captionStack.setCustomSpacing(Theme.Spacing.sm, after: subtitleLabel)

        for subview in [imageView, playerView, storyChrome] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            mediaView.addSubview(subview)
        }
        mediaView.translatesAutoresizingMaskIntoConstraints = false
        mediaFrame.addSubview(mediaView)
        for subview in [backdrop, mediaFrame, deckView, compareView, scrim, captionStack] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(subview)
        }

        let inset = Self.inset
        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: contentView.topAnchor),
            backdrop.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            backdrop.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            mediaView.topAnchor.constraint(equalTo: mediaFrame.topAnchor),
            mediaView.leadingAnchor.constraint(equalTo: mediaFrame.leadingAnchor),
            mediaView.trailingAnchor.constraint(equalTo: mediaFrame.trailingAnchor),
            mediaView.bottomAnchor.constraint(equalTo: mediaFrame.bottomAnchor),

            imageView.topAnchor.constraint(equalTo: mediaView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: mediaView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: mediaView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: mediaView.bottomAnchor),

            playerView.topAnchor.constraint(equalTo: mediaView.topAnchor),
            playerView.leadingAnchor.constraint(equalTo: mediaView.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: mediaView.trailingAnchor),
            playerView.bottomAnchor.constraint(equalTo: mediaView.bottomAnchor),

            storyChrome.topAnchor.constraint(equalTo: mediaView.topAnchor, constant: Theme.Spacing.xs),
            storyChrome.leadingAnchor.constraint(equalTo: mediaView.leadingAnchor, constant: Theme.Spacing.xs),
            storyChrome.trailingAnchor.constraint(equalTo: mediaView.trailingAnchor, constant: -Theme.Spacing.xs),
            storyChrome.heightAnchor.constraint(equalToConstant: 3),

            // The deck stands above the caption, never behind it.
            deckView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: inset),
            deckView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            deckView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            deckView.bottomAnchor.constraint(equalTo: captionStack.topAnchor, constant: -Theme.Spacing.md),

            compareView.topAnchor.constraint(equalTo: contentView.topAnchor),
            compareView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            compareView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            compareView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            scrim.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrim.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            scrim.heightAnchor.constraint(equalTo: contentView.heightAnchor, multiplier: Self.scrimHeightRatio),

            captionStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: inset),
            captionStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -inset),
        ])

        fillConstraints = [
            mediaFrame.topAnchor.constraint(equalTo: contentView.topAnchor),
            mediaFrame.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mediaFrame.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            mediaFrame.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ]
        storyConstraints = [
            mediaFrame.topAnchor.constraint(equalTo: contentView.topAnchor, constant: inset),
            mediaFrame.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -inset),
            mediaFrame.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -inset - Theme.Spacing.xs),
        ]
        captionWide = captionStack.widthAnchor.constraint(
            lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.78)
        captionBesideStory = captionStack.trailingAnchor.constraint(
            lessThanOrEqualTo: mediaFrame.leadingAnchor, constant: -inset)
        NSLayoutConstraint.activate(fillConstraints + [captionWide])
        apply(.fill, hasVideo: false)

        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        mediaFrame.layer.shadowPath = stage == .fill ? nil : UIBezierPath(
            roundedRect: mediaFrame.bounds, cornerRadius: Theme.Radius.md).cgPath
    }

    // MARK: Configuration

    func configure(with page: HeroShowcaseView.Page, index: Int, of count: Int) {
        titleLabel.text = page.title
        // Beside a story frame the column is too narrow for "kind · Tap to
        // create" on one line, and letting it wrap breaks it mid-phrase. Break
        // it where the copy already divides it instead.
        if case .story = page.stage {
            subtitleLabel.text = page.subtitle.replacingOccurrences(of: " · ", with: "\n")
        } else {
            subtitleLabel.text = page.subtitle
        }
        dotsView.configure(count: count, current: index)
        accessibilityIdentifier = page.identifier
        accessibilityLabel = page.title
        // The position the dots show, for VoiceOver: the card has no page
        // control of its own any more.
        accessibilityValue = count > 1
            ? "\(page.subtitle), " + String(localized: "Page \(index + 1) of \(count)")
            : page.subtitle

        let isVideo = page.loopURL != nil
        playerView.isHidden = !isVideo
        imageView.isHidden = isVideo
        // Configured either way: passing nil is what releases a pipeline this
        // cell was holding for the video page it used to show.
        playerView.configure(loopURL: page.loopURL, poster: isVideo ? page.poster : nil)
        apply(page.stage, hasVideo: isVideo)
        if isVideo { light(from: page.poster?.cgImage) }

        previewTask?.cancel()
        guard !isVideo else { return }
        previewTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            var stage = page.stage
            var frames: [UIImage] = []
            var still: UIImage?
            switch stage {
            case .deck, .compare:
                frames = await page.frames()
                guard !Task.isCancelled else { return }
                let needed = stage == .compare ? 2 : 1
                if frames.count < needed {
                    // Nothing to deal out: the page is still worth showing whole.
                    stage = .fill
                    still = page.preview().map { UIImage(cgImage: $0) }
                }
            case .fill, .story:
                still = page.preview().map { UIImage(cgImage: $0) }
            }
            guard !Task.isCancelled, let self else { return }
            // A fade, not a pop: the well → photograph swap is very visible at
            // hero size. A cross-dissolve is not motion, so Reduce Motion
            // shortens it rather than removing it.
            UIView.transition(
                with: self.contentView,
                duration: Theme.Motion.duration(Theme.Motion.standard),
                options: [.transitionCrossDissolve, .allowUserInteraction]
            ) {
                self.apply(stage, hasVideo: false)
                switch stage {
                case .deck:
                    self.deckView.configure(frames: frames)
                    self.light(from: frames.first?.cgImage)
                case .compare:
                    self.compareView.configure(before: frames[0], after: frames[1])
                case .fill, .story:
                    self.imageView.image = still
                    self.light(from: still?.cgImage)
                }
                self.contentView.layoutIfNeeded()
            } completion: { _ in
                if self.wantsMotion { self.startStageMotion() }
            }
        }
    }

    /// Puts the cell into a stage's geometry and shows only what that stage uses.
    private func apply(_ stage: HeroShowcaseView.Page.Stage, hasVideo: Bool) {
        self.stage = stage
        let isStory: Bool
        if case .story = stage { isStory = true } else { isStory = false }

        storyAspect?.isActive = false
        storyAspect = nil
        NSLayoutConstraint.deactivate(fillConstraints + storyConstraints + [captionWide, captionBesideStory])
        if case .story(let aspect) = stage {
            // Clamped: a frame much narrower than 9:16 would leave the stage
            // empty, and much wider is not a story.
            let ratio = min(max(aspect, 0.45), 0.8)
            let constraint = mediaFrame.widthAnchor.constraint(equalTo: mediaFrame.heightAnchor, multiplier: ratio)
            storyAspect = constraint
            NSLayoutConstraint.activate(storyConstraints + [constraint, captionBesideStory])
        } else {
            NSLayoutConstraint.activate(fillConstraints + [captionWide])
        }

        mediaFrame.isHidden = stage == .deck || stage == .compare
        mediaView.layer.cornerRadius = isStory ? Theme.Radius.md : 0
        mediaView.layer.borderWidth = isStory ? 0.5 : 0
        mediaView.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        mediaFrame.layer.shadowOpacity = isStory ? 0.5 : 0
        storyChrome.isHidden = !isStory
        deckView.isHidden = stage != .deck
        compareView.isHidden = stage != .compare
        backdrop.isHidden = stage == .fill || stage == .compare
        scrim.isHidden = !(stage == .fill || stage == .compare)
        // Beside a story frame the column is narrow; let the type wrap rather
        // than truncate the name of the thing being sold.
        titleLabel.numberOfLines = isStory ? 2 : 1
        subtitleLabel.numberOfLines = isStory ? 2 : 1
        setNeedsLayout()
    }

    /// Lights the stage in the artwork's colour, the glow centred on where the
    /// artwork stands.
    private func light(from image: CGImage?) {
        let center: CGPoint
        switch stage {
        case .story: center = CGPoint(x: 0.78, y: 0.45)
        case .deck: center = CGPoint(x: 0.5, y: 0.32)
        case .fill, .compare: return
        }
        backdrop.apply(tint: HeroStageTint.tint(of: image), glowCenter: center)
    }

    // MARK: Motion

    func play() {
        guard !wantsMotion else { return }
        wantsMotion = true
        playerView.play()
        startStageMotion()
    }

    func stop() {
        wantsMotion = false
        playerView.stop()
        storyChrome.stop()
        deckView.stop()
        compareView.stop()
    }

    private func startStageMotion() {
        switch stage {
        // A page reached by auto-advance starts playing once its cross-fade
        // ends, which is that long into the timer's period; the segment should
        // be full as the page leaves, not cut off just short of it.
        case .story:
            storyChrome.play(duration: HeroShowcaseView.dwell - Theme.Motion.duration(Theme.Motion.slow))
        case .deck: deckView.play()
        case .compare: compareView.play()
        case .fill: break
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // A render in flight belongs to the page this cell USED to show.
        previewTask?.cancel()
        previewTask = nil
        stop()
        playerView.configure(loopURL: nil, poster: nil)
        imageView.image = nil
        deckView.configure(frames: [])
        compareView.configure(before: nil, after: nil)
        titleLabel.text = nil
        subtitleLabel.text = nil
        accessibilityValue = nil
    }
}
