//
//  BrowseTemplateCell.swift
//  Caroullage
//
//  Step 07 — one card in a browse grid. Both browse tabs use it: the Carousel
//  tab's masonry sections and the Templates tab's uniform grid.
//
//  It started as the Carousel tab's alone. When the Templates tab went
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
//  surface.
//
//  The card's own frame carries the template's aspect ratio, CLAMPED — see
//  `MasonryLayout`, which bounds height to 0.68–1.55x width so a panorama does
//  not become a sliver. Nine of the twenty bundled templates (the 9:16s at 1.78
//  and the lone 16:9 at 0.5625) fall outside that band and are therefore cropped
//  rather than shown at true proportion. That is why the image view fills rather
//  than fits: it is filling a box that is deliberately not always its shape.
//

import UIKit

@MainActor
final class BrowseTemplateCell: UICollectionViewCell {
    static let reuseID = "BrowseTemplateCell"

    /// What a card states. The two browse tabs differ only in this.
    struct Content {
        let name: String
        /// The canvas ratio as a word. `nil` omits it — the Templates tab's own
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
    }

    /// Room under the artwork for the name and the metadata row. Fixed, and
    /// passed to `MasonryLayout` as `captionHeight`, so captions line up across
    /// a row even though the thumbnails above them do not.
    static let captionHeight: CGFloat = 44

    /// More dots than this and they stop being countable, so the row truncates.
    /// 7 is the longest bundled carousel (Grid Reveal 6), so nothing truncates
    /// today — this is the guard for a template authored longer later.
    private static let maxPageDots = 7

    private static let lockBadgeSide: CGFloat = 24
    private static let dotSize: CGFloat = 5

    private let imageView = UIImageView()
    private let dotsPill = UIView()
    private let dotsRow = UIStackView()
    private let lockBadge = UIImageView()
    private let nameLabel = UILabel()
    private let metaLabel = UILabel()

    private var previewTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)

        // The artwork clips; the cell does not, so the caption below it is not
        // trimmed by the artwork's corner radius.
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = Theme.Radius.lg
        imageView.layer.cornerCurve = .continuous
        // The same well the canvas and the exporter paint, so a card whose
        // preview has not landed yet still looks intentional rather than blank.
        imageView.backgroundColor = Theme.Color.cellWell
        // A hairline, because a good part of the catalog is authored on a WHITE
        // background — the minimal templates especially — and a white render on
        // the app's near-white ground is a card with no edge at all. On the
        // Carousel tab, where every cover happened to be an edge-to-edge
        // photograph, this was invisible and its absence went unnoticed; the
        // Templates tab is where it shows. Cheaper and quieter than a shadow,
        // which is what the old schematic card reached for.
        imageView.layer.borderWidth = 1
        imageView.layer.borderColor = Theme.Color.separator.cgColor
        imageView.translatesAutoresizingMaskIntoConstraints = false

        // Smoked glass rather than a UI chip, so the dots belong to the picture.
        // `toast` is the right family — fixed dark ground, white ink, floats over
        // anything — re-alpha'd because a badge over photography wants to let the
        // image through where a toast does not.
        dotsPill.backgroundColor = Theme.Color.toast.withAlphaComponent(0.55)
        dotsPill.layer.cornerCurve = .continuous
        dotsPill.clipsToBounds = true
        dotsPill.isUserInteractionEnabled = false
        dotsPill.translatesAutoresizingMaskIntoConstraints = false

        dotsRow.axis = .horizontal
        dotsRow.spacing = 4
        dotsRow.alignment = .center
        dotsRow.translatesAutoresizingMaskIntoConstraints = false

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

        dotsPill.addSubview(dotsRow)
        contentView.addSubview(imageView)
        contentView.addSubview(dotsPill)
        contentView.addSubview(lockBadge)
        contentView.addSubview(nameLabel)
        contentView.addSubview(metaLabel)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            // The caption block pins the bottom, and the artwork ends where the
            // caption begins — NOT at a fixed inset from the bottom.
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
            imageView.bottomAnchor.constraint(
                equalTo: nameLabel.topAnchor, constant: -Theme.Spacing.xxs),

            dotsPill.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            dotsPill.bottomAnchor.constraint(
                equalTo: imageView.bottomAnchor, constant: -Theme.Spacing.xs),

            dotsRow.topAnchor.constraint(equalTo: dotsPill.topAnchor, constant: 5),
            dotsRow.bottomAnchor.constraint(equalTo: dotsPill.bottomAnchor, constant: -5),
            dotsRow.leadingAnchor.constraint(equalTo: dotsPill.leadingAnchor, constant: 7),
            dotsRow.trailingAnchor.constraint(equalTo: dotsPill.trailingAnchor, constant: -7),

            lockBadge.topAnchor.constraint(
                equalTo: imageView.topAnchor, constant: Theme.Spacing.xs),
            lockBadge.trailingAnchor.constraint(
                equalTo: imageView.trailingAnchor, constant: -Theme.Spacing.xs),
            lockBadge.widthAnchor.constraint(equalToConstant: Self.lockBadgeSide),
            lockBadge.heightAnchor.constraint(equalToConstant: Self.lockBadgeSide),

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
            cell.imageView.layer.borderColor = Theme.Color.separator.cgColor
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        dotsPill.layer.cornerRadius = dotsPill.bounds.height / 2
    }



    /// The same press feel as every other card in the app.
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

    /// - Parameters:
    ///   - preview: invoked off the first layout pass. A closure rather than an
    ///     image so a cold render — which composites real photographs through
    ///     `CollageRenderer` — is never paid for by a cell that has already been
    ///     recycled before it runs.
    func configure(_ content: Content, preview: @escaping () -> CGImage?) {
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
        setPageDots(pages)

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
        accessibilityValue = spoken.joined(separator: ", ")

        previewTask?.cancel()
        previewTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            let rendered = preview()
            guard !Task.isCancelled, let self else { return }
            UIView.transition(
                with: self.imageView,
                duration: Theme.Motion.duration(Theme.Motion.quick),
                options: [.transitionCrossDissolve, .allowUserInteraction]
            ) {
                self.imageView.image = rendered.map { UIImage(cgImage: $0) }
            }
        }
    }

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

    private func setPageDots(_ count: Int?) {
        dotsRow.arrangedSubviews.forEach {
            dotsRow.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let shown = min(max(count ?? 0, 0), Self.maxPageDots)
        // One page is not a carousel, and `nil` is not a carousel at all, so in
        // both cases there is nothing for dots to say.
        dotsPill.isHidden = shown < 2
        guard shown >= 2 else { return }

        for index in 0..<shown {
            let dot = UIView()
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.backgroundColor = Theme.Color.textOnToast
                .withAlphaComponent(index == 0 ? 1 : 0.45)
            dot.layer.cornerRadius = Self.dotSize / 2
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: Self.dotSize),
                dot.heightAnchor.constraint(equalToConstant: Self.dotSize),
            ])
            dotsRow.addArrangedSubview(dot)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // A render in flight belongs to the template this cell USED to show;
        // letting it land would paint the wrong photograph on the new one.
        previewTask?.cancel()
        previewTask = nil
        imageView.image = nil
        nameLabel.text = nil
        metaLabel.attributedText = nil
        lockBadge.isHidden = true
        // Hidden here as well as re-decided in `setPageDots`. `configure` always
        // follows a dequeue today, so this is belt and braces — but a cell that
        // cleared its caption and kept the previous template's page count would
        // be a very quiet lie, and the sibling cell hides its badge here too.
        dotsPill.isHidden = true
        accessibilityValue = nil
    }
}
