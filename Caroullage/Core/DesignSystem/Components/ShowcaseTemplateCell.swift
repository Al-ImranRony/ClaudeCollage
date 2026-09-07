//
//  ShowcaseTemplateCell.swift
//  Caroullage
//
//  Step 07 — one card in a Home showcase strip (Photo Collages, Video Collages,
//  Carousels).
//
//  Home's old featured cell showed a template's SCHEMATIC: an empty wireframe
//  letterboxed onto the well, captioned underneath. That is honest about
//  structure and reads as a dev tool — it was deleted with the featured strip
//  once Home became a showcase. This cell is the other half of that trade: a
//  full-bleed, photo-real render of the template already dressed in its
//  bundled sample photography, with the name burned over the image instead of
//  parked below it. Nothing here is generic enough to belong to one screen — the
//  three strips and (next task) the hero card are all the same card at different
//  sizes — so it lives in the design system rather than inside HomeViewController.
//
//  It carried a text badge in its top-right corner for a while — "5 frames" over
//  a carousel's artwork. That was the wrong register for a strip whose whole
//  argument is the photograph: a card selling a picture does not want a sentence
//  stapled to it, and the fact it was stating is one every carousel UI in the
//  world states with dots. So the badge became a `UIPageControl` down beside the
//  name, which is exactly where the hero puts its own, and the type came off the
//  artwork entirely.
//

import UIKit

/// The bottom-up darkening a showcase card's caption sits on.
///
/// Split out as its own type because the hero card wants exactly this and
/// nothing else from the cell around it.
///
/// The gradient is the view's BACKING layer, never a sublayer inserted under the
/// content it darkens: an inserted gradient sublayer once hid a button's image
/// outright, and this codebase treats that as a rule rather than a war story.
@MainActor
final class ShowcaseScrimView: UIView {

    override class var layerClass: AnyClass { CAGradientLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Pure chrome. It must never take a touch away from the card under it.
        isUserInteractionEnabled = false

        guard let gradient = layer as? CAGradientLayer else { return }
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        // Fixed black in both appearances, and so not a Theme colour: this
        // darkens PHOTOGRAPHY, not an app surface, so it has no light-mode
        // counterpart to switch to — a scrim that lightened in light mode would
        // stop doing the one job it has.
        //
        // Three stops rather than two. A straight clear → 55% ramp bands
        // visibly across a card this size; the mid stop bends the falloff so
        // the transition disappears into the photo.
        gradient.locations = [0, 0.5, 1]
        gradient.colors = [
            UIColor.black.withAlphaComponent(0).cgColor,
            UIColor.black.withAlphaComponent(0.24).cgColor,
            UIColor.black.withAlphaComponent(0.55).cgColor,
        ]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

extension UILabel {

    /// The soft drop shadow every caption that floats over showcase artwork wears.
    ///
    /// The scrim alone is not enough, and Step 07's real content is what proved
    /// it: a good half of the catalog — the minimal templates, most carousel
    /// pages — is authored on a WHITE background, and 55% black over white is a
    /// light grey that white type disappears into. Darkening the scrim until it
    /// worked would drag every photographic card toward looking like a dark
    /// panel with a picture in it. A shadow is the surgical version: invisible
    /// over a dark photo, and the only thing holding the caption up over a pale
    /// one.
    func applyShowcaseCaptionShadow() {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.55
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1)
    }
}

/// A showcase card: photo-real preview, name over a bottom scrim, optional page
/// dots beside the name and an optional premium lock.
@MainActor
final class ShowcaseTemplateCell: UICollectionViewCell {
    static let reuseID = "ShowcaseTemplateCell"

    /// The share of the card's height the scrim covers. Enough to seat one line
    /// of caption with air around it; much more and the card reads as a dark
    /// panel with a photo above it rather than as a photo.
    private static let scrimHeightRatio: CGFloat = 0.38

    /// The lock badge is a circle, so its radius is half its side —
    /// `Theme.Radius.pill`'s documented "callers use height/2" contract.
    private static let lockBadgeSide: CGFloat = 24

    /// How a card seats its artwork — the same choice `HeroPageCell` makes, in
    /// the same words, because it is the same choice.
    enum Presentation {
        /// Edge to edge, cropped to the card. Right for a single canvas, whose
        /// shape is near enough the card's that the crop costs nothing.
        case fill
        /// Whole, in the band ABOVE the caption, on a blurred blow-up of itself.
        ///
        /// A carousel's preview is three pages laid side by side — a ~2.4:1
        /// strip on a 1.2:1 card — so `fill` scales it to the card's height and
        /// then throws away half its width. A five-page template arrived as one
        /// page and two slivers, which is the card failing at the one thing it
        /// is for: you cannot tell a carousel from a collage by looking at it.
        /// Fitting makes the pages small (~69 x 87pt at the current card width)
        /// but shows all three of them dressed in their sample photography, so
        /// the strip can be judged without opening it.
        case fitOnBlurredBed
    }

    private let bedImageView = UIImageView()
    // Ultra-thin, not thick, for the reason the hero documents: the bed has to
    // read as a soft out-of-focus blow-up OF THE ARTWORK, and anything heavier
    // buries it — the card comes out a dark box with a small picture in it.
    private let bedBlur = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let imageView = UIImageView()
    private let scrim = ShowcaseScrimView()
    private let nameLabel = UILabel()
    /// Bottom-trailing, opposite the name — the hero's own arrangement.
    ///
    /// A `UIPageControl` rather than the hand-rolled dot row `BrowseTemplateCell`
    /// draws: that one needs a smoked-glass pill under it because it sits on raw
    /// photography, and these dots sit on the scrim, which already IS the dark
    /// ground such a pill would have had to supply. It also shrinks its own dots
    /// past eight pages, which the hand-rolled row answers by truncating.
    private let pageControl = UIPageControl()
    private let lockBadge = UIImageView()

    private var previewTask: Task<Void, Never>?
    /// The artwork's two geometries, swapped by `apply(_:)`.
    private var edgeConstraints: [NSLayoutConstraint] = []
    private var aboveCaptionConstraints: [NSLayoutConstraint] = []

    override init(frame: CGRect) {
        super.init(frame: frame)

        // The card clips, not the image view: the bed, the scrim and the badges
        // all have to be trimmed by the same rounded rectangle, and one clipping
        // ancestor is cheaper and less error-prone than rounding each of them.
        //
        // Fill by default. Unlike the schematic strip — where letterboxing is what
        // keeps a template's zones symmetrical — a showcase card is selling the
        // photograph, and a photograph floating in a well does not sell.
        contentView.backgroundColor = Theme.Color.cellWell
        contentView.layer.cornerRadius = Theme.Radius.lg
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true

        // The bed is the same picture, blown up and blurred, so a fitted preview
        // sits on something that belongs to it instead of on a flat grey box.
        // Hidden until a `.fitOnBlurredBed` card asks for it.
        bedImageView.contentMode = .scaleAspectFill
        bedImageView.clipsToBounds = true
        bedImageView.isHidden = true
        bedImageView.translatesAutoresizingMaskIntoConstraints = false
        bedBlur.isHidden = true
        bedBlur.translatesAutoresizingMaskIntoConstraints = false

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        // The same well the canvas and the exporter paint, so a card whose
        // preview has not landed yet still looks intentional rather than blank.
        // `apply(_:)` clears it for a fitted card, where an opaque image view
        // would letterbox the artwork in grey and hide the bed it is sitting on.
        imageView.backgroundColor = Theme.Color.cellWell
        imageView.translatesAutoresizingMaskIntoConstraints = false

        scrim.translatesAutoresizingMaskIntoConstraints = false

        // White in BOTH themes, and so a deliberate exception to "text colours
        // come from Theme". This label never touches an app surface — it always
        // sits on the scrim, which is always dark — so `textPrimary` would flip
        // it to near-black on black in light mode. The token that fits the role
        // is the toast's ink, which exists for exactly this reason: type that
        // floats over arbitrary content and cannot borrow the surface tokens.
        nameLabel.font = Theme.Typography.subheadline
        nameLabel.textColor = Theme.Color.textOnToast
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.numberOfLines = 1
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.applyShowcaseCaptionShadow()
        // The name yields to the dots rather than pushing them off the card: at
        // a 212pt width a seven-page control and a long template name cannot
        // both have what they want, and a truncated name still identifies the
        // template where four of five dots does not identify the carousel.
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        // The same dots the hero wears, configured the same way: white at full
        // strength for the current page and at 40% for the rest, which is legible
        // over the scrim in both appearances. Not interactive — these state a
        // count, they do not page anything, and a control that swallowed the
        // touch would put a dead strip across the bottom of the card.
        pageControl.currentPageIndicatorTintColor = Theme.Color.textOnToast
        pageControl.pageIndicatorTintColor = Theme.Color.textOnToast.withAlphaComponent(0.4)
        pageControl.hidesForSinglePage = true
        pageControl.isUserInteractionEnabled = false
        pageControl.isHidden = true
        pageControl.setContentCompressionResistancePriority(.required, for: .horizontal)
        pageControl.setContentHuggingPriority(.required, for: .horizontal)
        pageControl.translatesAutoresizingMaskIntoConstraints = false

        // Premium. Accent-on-accent rather than the badge's smoked glass,
        // because this one is a *state* the user can act on, not a caption.
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

        // Order is z-order: the bed under the artwork, the scrim over both, the
        // caption and the chips over the scrim.
        contentView.addSubview(bedImageView)
        contentView.addSubview(bedBlur)
        contentView.addSubview(imageView)
        contentView.addSubview(scrim)
        contentView.addSubview(nameLabel)
        contentView.addSubview(pageControl)
        contentView.addSubview(lockBadge)

        NSLayoutConstraint.activate([
            bedImageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            bedImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bedImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bedImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            bedBlur.topAnchor.constraint(equalTo: contentView.topAnchor),
            bedBlur.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bedBlur.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bedBlur.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            scrim.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrim.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            scrim.heightAnchor.constraint(
                equalTo: contentView.heightAnchor, multiplier: Self.scrimHeightRatio),

            nameLabel.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: Theme.Spacing.sm),
            // Both caps, not one. The label stops at the dots when there are
            // dots, and at the card's edge when there are not — a hidden
            // `UIPageControl` still holds a frame, and with no pages that frame
            // is not reliably zero-width.
            nameLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: pageControl.leadingAnchor, constant: -Theme.Spacing.xxs),
            nameLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: contentView.trailingAnchor, constant: -Theme.Spacing.sm),
            nameLabel.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor, constant: -Theme.Spacing.sm),

            // `UIPageControl` carries its own touch padding, so it is inset by
            // less than the name and still lines up optically with it.
            pageControl.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -Theme.Spacing.xxs),
            pageControl.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),

            lockBadge.topAnchor.constraint(
                equalTo: contentView.topAnchor, constant: Theme.Spacing.xs),
            lockBadge.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: Theme.Spacing.xs),
            lockBadge.widthAnchor.constraint(equalToConstant: Self.lockBadgeSide),
            lockBadge.heightAnchor.constraint(equalToConstant: Self.lockBadgeSide),
        ])

        // Two geometries for one image view — the hero's own pair. The fitted
        // one hangs off the caption rather than off a share of the card's
        // height, so the artwork still clears the type at the accessibility text
        // sizes instead of sliding under a name that has grown into it.
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
                equalTo: nameLabel.topAnchor, constant: -Theme.Spacing.xs),
        ]
        NSLayoutConstraint.activate(edgeConstraints)

        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// A subtle scale-down while the card is pressed, springing back on release.
    /// The same gesture the gallery's cards use — one press feel across the app.
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
    ///   - name: shown over the scrim, and used as the accessibility label.
    ///   - identifier: the cell's `accessibilityIdentifier`, for UI tests.
    ///   - pages: how many pages the template makes, as dots beside the name.
    ///     `nil` for a single canvas — a collage is one image, and one dot on it
    ///     would be answering a question nobody asked.
    ///   - presentation: how the artwork is seated. See `Presentation`.
    ///   - locked: shows the premium lock.
    ///   - preview: the render, invoked off the first layout pass. The caller
    ///     supplies a closure rather than an image so a cold showcase render —
    ///     which composites real photographs through `CollageRenderer` — is
    ///     never paid for by a cell that has already been cancelled (recycled
    ///     or reconfigured) before it runs.
    func configure(
        name: String,
        identifier: String,
        pages: Int? = nil,
        presentation: Presentation = .fill,
        locked: Bool = false,
        preview: @escaping () -> CGImage?
    ) {
        nameLabel.text = name
        lockBadge.isHidden = !locked

        // One page is not a carousel and `nil` is not a carousel at all, so in
        // neither case is there anything for dots to say. `hidesForSinglePage`
        // covers the first; this covers the second.
        let shown = pages ?? 0
        pageControl.numberOfPages = shown
        pageControl.currentPage = 0
        pageControl.isHidden = shown < 2

        apply(presentation)

        accessibilityIdentifier = identifier
        accessibilityLabel = name
        // The page count is stated only in pixels; without this the dots reach
        // nobody using VoiceOver.
        accessibilityValue = shown >= 2 ? String(localized: "\(shown) pages") : nil

        previewTask?.cancel()
        previewTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            let rendered = preview()
            guard !Task.isCancelled, let self else { return }
            let image = rendered.map { UIImage(cgImage: $0) }
            // Cross-dissolve rather than a hard swap: the well → photograph pop
            // is very visible on a card this size. Reduce Motion shortens it
            // through `Theme.Motion.duration` rather than removing it, since a
            // fade is not motion.
            //
            // Transitioned on the contentView rather than the image view alone,
            // because a fitted card puts the same picture on the bed behind it
            // and the two have to arrive together.
            UIView.transition(
                with: self.contentView,
                duration: Theme.Motion.duration(Theme.Motion.quick),
                options: [.transitionCrossDissolve, .allowUserInteraction]
            ) {
                self.imageView.image = image
                self.bedImageView.image = presentation == .fill ? nil : image
            }
        }
    }

    /// Puts the artwork into one of the two geometries and shows or hides the
    /// blurred bed to match.
    private func apply(_ presentation: Presentation) {
        let fits = presentation == .fitOnBlurredBed
        imageView.contentMode = fits ? .scaleAspectFit : .scaleAspectFill
        // A fitted image view must not paint its own ground, or the letterbox
        // either side of the artwork comes out flat grey and the bed — the whole
        // point of the treatment — never shows.
        imageView.backgroundColor = fits ? .clear : Theme.Color.cellWell
        bedImageView.isHidden = !fits
        bedBlur.isHidden = !fits

        // Deactivate first: the two sets contradict each other, and activating
        // into a still-live set is how a card ends up with broken constraints.
        NSLayoutConstraint.deactivate(fits ? edgeConstraints : aboveCaptionConstraints)
        NSLayoutConstraint.activate(fits ? aboveCaptionConstraints : edgeConstraints)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // A render in flight belongs to the template this cell USED to show;
        // letting it land would paint the wrong photograph on the new one.
        previewTask?.cancel()
        previewTask = nil
        imageView.image = nil
        bedImageView.image = nil
        nameLabel.text = nil
        pageControl.numberOfPages = 0
        pageControl.isHidden = true
        lockBadge.isHidden = true
        accessibilityValue = nil
    }
}
