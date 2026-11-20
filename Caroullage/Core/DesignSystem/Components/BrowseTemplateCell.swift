//
//  BrowseTemplateCell.swift
//  Caroullage
//
//  Step 07 — one card in a browse grid. Both browse tabs use it: the Carousel
//  tab's masonry sections and the Collage tab's uniform grid.
//
//  It started as the Carousel tab's alone. When the Collage tab went
//  photo-real it needed the same card — same artwork treatment, same lock, same
//  caption block — differing only in that a collage has no pages to dot. Two
//  copies of this file would have been two chances for the app's two browse
//  tabs to stop looking like one app, which is the whole thing a shared card is
//  for. So the differences became `Content`: a `nil` ratio for a screen whose
//  filter already fixes it, a `nil` page count for a single-canvas template.
//
//  Deliberately not `ShowcaseTemplateCell`, which is its sibling rather than its
//  base class. That cell burns the template name OVER the artwork on a scrim and
//  carries no metadata row, because Home's strips sell a picture. A browse grid
//  has a different job: you are comparing a whole catalog, so the facts that let
//  you compare — how many of your photos it wants, how many pages it makes —
//  have to be readable at a glance, and type over photography is not readable at
//  a glance. So the artwork is full-bleed and the facts sit under it on the app
//  surface, and the only things over the artwork are the two chips that have
//  nowhere else to go: the page dots and the premium lock, both in the top band
//  where no template draws.
//
//  The card's own frame carries the template's aspect ratio, CLAMPED — see
//  `MasonryLayout`, which bounds height to 0.68–1.55x width so a panorama does
//  not become a sliver. Nine of the twenty bundled templates (the 9:16s at 1.78
//  and the lone 16:9 at 0.5625) fall outside that band and are therefore cropped
//  rather than shown at true proportion. That is why the image view fills rather
//  than fits: it is filling a box that is deliberately not always its shape.
//
//  2026-11-20 — the carousel card PAGES. Its artwork is a `PagedArtworkView`
//  holding every rendered slide, swiped sideways the way SCRL's feed and the
//  finished Instagram post both page, and the dots now sit UNDER the artwork
//  and follow the page that is showing. (They were a fixed pill over the cover
//  that marked page one forever — a promise of pages the card could not show.)
//  Under, not over, for the reason they left the bottom of the art before:
//  half the catalog burns its own page label into that band.
//

import UIKit

@MainActor
final class BrowseTemplateCell: UICollectionViewCell {
    static let reuseID = "BrowseTemplateCell"

    /// What a card states. The two browse tabs differ only in this.
    struct Content {
        let name: String
        /// The canvas ratio as a word. `nil` omits it — the Collage tab's own
        /// ratio filter is a hard one, so every card there would repeat the same
        /// word, and thirty-three copies of "Square" is noise, not information.
        let ratio: String?
        let photos: Int
        /// `nil` for a single-canvas template: no page dots, no page count. A
        /// collage is one image, and a "1 page" badge on it would be answering a
        /// question nobody asked.
        let pages: Int?
        let locked: Bool
        /// The cell's `accessibilityIdentifier`. Locked and unlocked cards are
        /// told apart in UI tests by this rather than by reading a badge out of
        /// a screenshot, so the caller names them.
        let identifier: String
        /// A template the user saved (phase 4). Defaulted so the two galleries'
        /// existing call sites read unchanged.
        var saved: Bool = false
    }

    /// Room under the artwork for the name and the metadata row. Fixed, and
    /// passed to `MasonryLayout` as `captionHeight`, so captions line up across
    /// a row even though the thumbnails above them do not.
    static let captionHeight: CGFloat = 44

    /// The page-dot row under a paged card's artwork, dots plus breathing room.
    static let pageDotsRowHeight: CGFloat = 16

    /// What `MasonryLayout` must reserve under a card's artwork: the caption,
    /// plus the dot row when the card pages.
    static func captionHeight(pages: Bool) -> CGFloat {
        captionHeight + (pages ? pageDotsRowHeight : 0)
    }

    /// `CarouselService.maxFrames` is 10; every page gets a dot up to there.
    private static let maxPages = 10

    private static let lockBadgeSide: CGFloat = 24

    private let artwork = PagedArtworkView()
    private let pageDots = PageDotsView()
    private var pageDotsHeight: NSLayoutConstraint!
    private let lockBadge = UIImageView()
    /// A heart beside the lock, for a saved template (phase 4). The two share
    /// a row so a hidden one leaves no gap.
    private let savedBadge = UIImageView()
    private let badgeRow = UIStackView()
    private let nameLabel = UILabel()
    private let metaLabel = UILabel()

    private var previewTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)

        // The artwork clips; the cell does not, so the caption below it is not
        // trimmed by the artwork's corner radius.
        artwork.layer.cornerRadius = Theme.Radius.lg
        artwork.layer.cornerCurve = .continuous
        // The same well the canvas and the exporter paint, so a card whose
        // preview has not landed yet still looks intentional rather than blank.
        artwork.backgroundColor = Theme.Color.cellWell
        // A hairline, because a good part of the catalog is authored on a WHITE
        // background — the minimal templates especially — and a white render on
        // the app's near-white ground is a card with no edge at all. Cheaper
        // and quieter than a shadow, which is what the old schematic card
        // reached for.
        artwork.layer.borderWidth = 1
        artwork.layer.borderColor = Theme.Color.separator.cgColor
        artwork.translatesAutoresizingMaskIntoConstraints = false
        artwork.onDragBegan = { [weak self] in self?.startSlides() }
        artwork.onPageChange = { [weak self] page in
            guard let self else { return }
            self.pageDots.setCurrentPage(page, animated: true)
            self.updatePageAccessibility()
        }

        pageDots.translatesAutoresizingMaskIntoConstraints = false

        lockBadge.contentMode = .center
        lockBadge.tintColor = Theme.Color.textOnAccent
        lockBadge.backgroundColor = Theme.Color.accentStrong
        lockBadge.layer.cornerRadius = Self.lockBadgeSide / 2
        lockBadge.layer.cornerCurve = .continuous
        lockBadge.clipsToBounds = true
        lockBadge.isHidden = true
        lockBadge.image = UIImage(
            systemName: "lock.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        lockBadge.translatesAutoresizingMaskIntoConstraints = false

        savedBadge.contentMode = .center
        savedBadge.tintColor = Theme.Color.textOnToast
        savedBadge.backgroundColor = Theme.Color.toast.withAlphaComponent(0.55)
        savedBadge.layer.cornerRadius = Self.lockBadgeSide / 2
        savedBadge.layer.cornerCurve = .continuous
        savedBadge.clipsToBounds = true
        savedBadge.isHidden = true
        savedBadge.image = UIImage(
            systemName: "heart.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        savedBadge.translatesAutoresizingMaskIntoConstraints = false

        badgeRow.axis = .horizontal
        badgeRow.spacing = Theme.Spacing.xxs
        badgeRow.alignment = .center
        badgeRow.translatesAutoresizingMaskIntoConstraints = false
        badgeRow.addArrangedSubview(savedBadge)
        badgeRow.addArrangedSubview(lockBadge)

        // Below the artwork, on the app surface — so these take the surface
        // tokens, unlike `ShowcaseTemplateCell`'s caption which floats over
        // photography and cannot.
        nameLabel.font = Theme.Typography.subheadline
        nameLabel.textColor = Theme.Color.textPrimary
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.numberOfLines = 1
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        metaLabel.font = Theme.Typography.caption
        metaLabel.textColor = Theme.Color.textSecondary
        metaLabel.adjustsFontForContentSizeCategory = true
        metaLabel.numberOfLines = 1
        metaLabel.lineBreakMode = .byTruncatingTail
        metaLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(artwork)
        contentView.addSubview(pageDots)
        contentView.addSubview(badgeRow)
        contentView.addSubview(nameLabel)
        contentView.addSubview(metaLabel)

        pageDotsHeight = pageDots.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            artwork.topAnchor.constraint(equalTo: contentView.topAnchor),
            artwork.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            artwork.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            // The caption block pins the bottom, and the artwork ends where the
            // dot row (or, unpaged, the caption) begins — NOT at a fixed inset
            // from the bottom.
            //
            // `captionHeight` is what `MasonryLayout` RESERVES, which is only the
            // right height at the default text size. Pinning the artwork to
            // `contentView.bottom - 44` makes that reservation load-bearing: at
            // the accessibility sizes the subheadline/caption pair needs closer
            // to 100pt, and since this cell deliberately does not clip, the
            // metadata would draw outside the card and over the card below it in
            // the masonry column. Hanging the artwork off the caption instead
            // lets growing type steal from the picture, which is the trade
            // `ProjectCardCell` makes and documents.
            artwork.bottomAnchor.constraint(equalTo: pageDots.topAnchor),

            // Centred under the artwork; zero-height (and so invisible) on a
            // card with one page.
            pageDots.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            pageDots.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            pageDotsHeight,
            nameLabel.topAnchor.constraint(
                equalTo: pageDots.bottomAnchor, constant: Theme.Spacing.xxs),

            badgeRow.topAnchor.constraint(
                equalTo: artwork.topAnchor, constant: Theme.Spacing.xs),
            badgeRow.trailingAnchor.constraint(
                equalTo: artwork.trailingAnchor, constant: -Theme.Spacing.xs),
            // The row keeps the badge height even with both badges hidden — a
            // stack with every child hidden collapses to nothing.
            badgeRow.heightAnchor.constraint(equalToConstant: Self.lockBadgeSide),
            lockBadge.widthAnchor.constraint(equalToConstant: Self.lockBadgeSide),
            lockBadge.heightAnchor.constraint(equalToConstant: Self.lockBadgeSide),
            savedBadge.widthAnchor.constraint(equalToConstant: Self.lockBadgeSide),
            savedBadge.heightAnchor.constraint(equalToConstant: Self.lockBadgeSide),

            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            metaLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            metaLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            metaLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            // Equality, not `lessThanOrEqualTo` — the same call `ProjectCardCell`
            // makes and for the same reason: with only an inequality the whole
            // chain is satisfiable by collapsing the artwork to zero height and
            // parking the labels at the top.
            metaLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button

        // `CGColor` is a snapshot, not a dynamic colour, so the hairline keeps
        // whatever shade it was born in unless it is re-resolved when light/dark
        // flips. Same registration every other component in this directory uses.
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (cell: Self, _) in
            cell.artwork.layer.borderColor = Theme.Color.separator.cgColor
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The same press feel as every other card in the app.
    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            setPressed(isHighlighted, scale: 0.96)
        }
    }

    /// A picture the card shows: what the memory cache already holds, and how
    /// to get it otherwise.
    ///
    /// The split is the whole smoothness story. `cached` is answered in
    /// `cellForItemAt` and put up in the same frame, so a card scrolled back
    /// into view — or redrawn by a reload — never flashes its well or fades
    /// in again. `load` runs only on a miss, entirely off the scroll (see
    /// `TemplateService`'s async preview pipeline), and only what it brings in
    /// late is crossfaded.
    struct Artwork {
        var cached: CGImage?
        var load: @MainActor () async -> CGImage?
    }

    /// Every slide of a paging card, split the same way.
    struct Slides {
        var cached: [CGImage]?
        var load: @MainActor () async -> [CGImage]
    }

    /// - Parameters:
    ///   - artwork: the cover (page 0).
    ///   - pages: every slide, in order, for a card that pages. Loaded after the
    ///     cover has landed, so the first screenful is never held up by slides
    ///     nobody has swiped to yet. `nil` — or a template with one page — is a
    ///     still card, as on the Collage tab.
    func configure(_ content: Content, artwork cover: Artwork, pages slides: Slides? = nil) {
        nameLabel.text = content.name

        let ratio = content.ratio
        let photos = content.photos
        let pages = content.pages
        let locked = content.locked
        // Glyphs for the two counts, the way the reference design does it.
        //
        // This started as words — "Landscape · 3 photos · 3 pages" — on the
        // argument that three inline symbols at caption size read as noise. On
        // the device that turned out to be the wrong trade: at a 170pt column
        // width the words fit for "Story" and "Portrait" and truncated for
        // "Landscape", so the longest ratio name lost its page count to an
        // ellipsis. Glyphs buy back the room, and they buy it back in every
        // language rather than only in English.
        //
        // The ratio stays a word. It is the one part a symbol cannot say, and
        // the card's shape does not say it either — `MasonryLayout` clamps, so
        // nine of the twenty are cropped rather than true to their ratio.
        metaLabel.attributedText = Self.metadata(ratio: ratio, photos: photos, pages: pages)

        lockBadge.isHidden = !locked
        savedBadge.isHidden = !content.saved

        let pageCount = resolvedPageCount(paging: slides != nil, content.pages)
        artwork.setPageCount(pageCount)
        pageDots.configure(numberOfPages: pageCount > 1 ? pageCount : 0)
        pageDotsHeight.constant = pageCount > 1 ? Self.pageDotsRowHeight : 0

        accessibilityIdentifier = content.identifier
        accessibilityLabel = content.name
        // The metadata is stated only in pixels; without this it reaches nobody
        // using VoiceOver. Spoken rather than read, so it takes commas where the
        // label takes interpuncts, and it says "premium" — the lock badge is a
        // picture and pictures do not reach a screen reader either.
        var spoken: [String] = []
        if let ratio { spoken.append(ratio) }
        spoken.append(String(localized: "\(photos) photos"))
        if let pages { spoken.append(String(localized: "\(pages) pages")) }
        if locked { spoken.append(String(localized: "premium")) }
        if content.saved { spoken.append(String(localized: "saved")) }
        baseAccessibilityValue = spoken.joined(separator: ", ")
        updatePageAccessibility()

        previewTask?.cancel()
        previewTask = nil
        slidesTask?.cancel()
        slidesTask = nil
        pendingSlides = nil

        // Whatever is already in memory goes up now, unanimated.
        if let image = cover.cached {
            artwork.setImage(UIImage(cgImage: image), at: 0, animated: false)
        }
        let cachedSlides = pageCount > 1 ? slides?.cached : nil
        if let cachedSlides {
            for (index, slide) in cachedSlides.enumerated() where index < pageCount {
                artwork.setImage(UIImage(cgImage: slide), at: index, animated: false)
            }
        }

        let needsCover = cover.cached == nil && cachedSlides == nil
        let pagesToLoad = pageCount > 1 && cachedSlides == nil ? slides : nil
        guard needsCover || pagesToLoad != nil else { return }

        if needsCover {
            previewTask = Task { @MainActor [weak self] in
                let image = await cover.load()
                guard !Task.isCancelled, let self else { return }
                self.artwork.setImage(image.map { UIImage(cgImage: $0) }, at: 0)
            }
        }
        guard let pagesToLoad else { return }
        // The other slides wait until the card has SETTLED on screen. A card a
        // fast fling only passes through is recycled inside this window, its
        // wait is cancelled, and none of its slides are ever drawn — where
        // before every card the fling touched rendered all of them. A finger
        // on the artwork skips the wait (`onDragBegan`).
        pendingSlides = (pagesToLoad, pageCount)
        slidesTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.slideSettleDelay)
            guard !Task.isCancelled else { return }
            self?.startSlides()
        }
    }

    /// How long a card must stay on screen before its other slides load.
    static let slideSettleDelay: Duration = .milliseconds(300)

    private var pendingSlides: (slides: Slides, pageCount: Int)?
    private var slidesTask: Task<Void, Never>?

    /// Loads the waiting slides now. Idempotent: only the first call loads.
    private func startSlides() {
        guard let pending = pendingSlides else { return }
        pendingSlides = nil
        slidesTask?.cancel()
        slidesTask = Task { @MainActor [weak self] in
            let loaded = await pending.slides.load()
            guard !Task.isCancelled, let self else { return }
            // Page 0 keeps the cover it already shows (the same render); the
            // rest arrive together. A slide that could not be drawn stays an
            // empty well rather than repeating another page's picture.
            for (index, slide) in loaded.enumerated() where index > 0 && index < pending.pageCount {
                self.artwork.setImage(UIImage(cgImage: slide), at: index)
            }
        }
    }

    /// How many pages the card shows: the template's page count when there is
    /// something to page through, else one.
    private func resolvedPageCount(paging: Bool, _ count: Int?) -> Int {
        guard paging, let count, count > 1 else { return 1 }
        return min(count, Self.maxPages)
    }

    /// The facts the card states, before the page it is on is added.
    private var baseAccessibilityValue = ""

    /// "Portrait, 13 photos, 4 pages, page 2 of 4". The page is spoken because
    /// a swipe changes what the card shows, and VoiceOver must hear that too.
    private func updatePageAccessibility() {
        guard artwork.pageCount > 1 else {
            accessibilityValue = baseAccessibilityValue
            return
        }
        let page = String(localized: "Page \(artwork.currentPage + 1) of \(artwork.pageCount)")
        accessibilityValue = [baseAccessibilityValue, page].joined(separator: ", ")
    }

    /// Next/previous page for VoiceOver, where there is no finger to swipe the
    /// artwork. Empty for a card that does not page; the caller appends its own
    /// actions (save) after these.
    var pagingAccessibilityActions: [UIAccessibilityCustomAction] {
        guard artwork.pageCount > 1 else { return [] }
        return [
            UIAccessibilityCustomAction(name: String(localized: "Next page")) { [weak self] _ in
                guard let self, self.artwork.currentPage < self.artwork.pageCount - 1 else { return false }
                self.artwork.scroll(to: self.artwork.currentPage + 1, animated: true)
                return true
            },
            UIAccessibilityCustomAction(name: String(localized: "Previous page")) { [weak self] _ in
                guard let self, self.artwork.currentPage > 0 else { return false }
                self.artwork.scroll(to: self.artwork.currentPage - 1, animated: true)
                return true
            },
        ]
    }

    /// The page the artwork is showing. Exposed for tests.
    var currentPage: Int { artwork.currentPage }
    /// How many pages the artwork holds. Exposed for tests.
    var pageCount: Int { artwork.pageCount }
    /// What a page shows right now. Exposed for tests.
    func pageImage(at index: Int) -> UIImage? { artwork.image(at: index) }

    /// "Portrait  ⧉5  ▤3" — ratio as a word, counts behind their glyphs.
    ///
    /// Built as an attributed string rather than assembled from `String(localized:)`
    /// because the symbols are text attachments, and a translator must be free to
    /// reorder the ratio against the counts without having to carry the images.
    private static func metadata(ratio: String?, photos: Int, pages: Int?) -> NSAttributedString {
        let font = Theme.Typography.caption
        let out = NSMutableAttributedString(
            string: ratio ?? "",
            attributes: [.font: font, .foregroundColor: Theme.Color.textSecondary])

        func append(symbol: String, count: Int) {
            let config = UIImage.SymbolConfiguration(font: font)
            guard let image = UIImage(systemName: symbol, withConfiguration: config)?
                .withTintColor(Theme.Color.textSecondary, renderingMode: .alwaysTemplate)
            else {
                // No such symbol on this OS — fall back to the word, which is
                // long but honest. Truncation beats a blank.
                out.append(NSAttributedString(
                    string: out.length > 0 ? "  \(count)" : "\(count)",
                    attributes: [.font: font, .foregroundColor: Theme.Color.textSecondary]))
                return
            }
            let attachment = NSTextAttachment()
            attachment.image = image
            // Sits the glyph on the text baseline instead of hanging it below.
            attachment.bounds = CGRect(
                x: 0, y: font.descender * 0.5,
                width: image.size.width, height: image.size.height)

            // No leading gap when the glyph is the first thing on the line,
            // which it is on a screen that omits the ratio.
            if out.length > 0 { out.append(NSAttributedString(string: "  ")) }
            out.append(NSAttributedString(attachment: attachment))
            out.append(NSAttributedString(
                string: " \(count)",
                attributes: [.font: font, .foregroundColor: Theme.Color.textSecondary]))
        }

        append(symbol: "photo", count: photos)
        if let pages { append(symbol: "square.stack", count: pages) }
        return out
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // A render in flight belongs to the template this cell USED to show;
        // letting it land would paint the wrong photograph on the new one.
        previewTask?.cancel()
        previewTask = nil
        slidesTask?.cancel()
        slidesTask = nil
        pendingSlides = nil
        artwork.reset()
        pageDots.configure(numberOfPages: 0)
        pageDotsHeight.constant = 0
        nameLabel.text = nil
        metaLabel.attributedText = nil
        lockBadge.isHidden = true
        accessibilityValue = nil
        baseAccessibilityValue = ""
        savedBadge.isHidden = true
        accessibilityCustomActions = nil
    }
}
