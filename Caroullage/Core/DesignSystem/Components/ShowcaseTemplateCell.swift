//
//  ShowcaseTemplateCell.swift
//  Caroullage
//
//  Step 07 — one card in a Home showcase strip (Photo Collages, Video Collages,
//  Carousels).
//
//  `FeaturedTemplateCell` deliberately shows a template's SCHEMATIC: an empty
//  wireframe letterboxed onto the well, captioned underneath. That is honest
//  about structure and reads as a dev tool. This cell is the other half of that
//  trade: a full-bleed, photo-real render of the template already dressed in its
//  bundled sample photography, with the name burned over the image instead of
//  parked below it. Nothing here is generic enough to belong to one screen — the
//  three strips and (next task) the hero card are all the same card at different
//  sizes — so it lives in the design system rather than inside HomeViewController.
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

/// A full-bleed showcase card: photo-real preview, name over a bottom scrim, an
/// optional top-right badge and an optional premium lock.
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

    private let imageView = UIImageView()
    private let scrim = ShowcaseScrimView()
    private let nameLabel = UILabel()
    private let badgePill = UIView()
    private let badgeLabel = UILabel()
    private let lockBadge = UIImageView()

    private var previewTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)

        // The card clips, not the image view: the scrim and the badges all have
        // to be trimmed by the same rounded rectangle, and one clipping ancestor
        // is cheaper and less error-prone than rounding each of them.
        //
        // Fill, not fit. Unlike the schematic strip — where letterboxing is what
        // keeps a template's zones symmetrical — a showcase card is selling the
        // photograph, and a photograph floating in a well does not sell.
        contentView.backgroundColor = Theme.Color.cellWell
        contentView.layer.cornerRadius = Theme.Radius.lg
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        // The same well the canvas and the exporter paint, so a card whose
        // preview has not landed yet still looks intentional rather than blank.
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
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        // "4 frames", a play glyph — a fact about the card that the picture
        // itself cannot state. Dark and translucent so it belongs to the photo
        // rather than sitting on top of it as a UI chip; `toast` is again the
        // right family (fixed dark ground, white ink, floats over anything),
        // re-alpha'd because a badge over photography wants to let the image
        // through where a toast does not.
        badgePill.backgroundColor = Theme.Color.toast.withAlphaComponent(0.55)
        badgePill.layer.cornerCurve = .continuous
        badgePill.clipsToBounds = true
        badgePill.isHidden = true
        badgePill.translatesAutoresizingMaskIntoConstraints = false

        badgeLabel.font = Theme.Typography.caption
        badgeLabel.textColor = Theme.Color.textOnToast
        badgeLabel.adjustsFontForContentSizeCategory = true
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false

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

        badgePill.addSubview(badgeLabel)
        contentView.addSubview(imageView)
        contentView.addSubview(scrim)
        contentView.addSubview(nameLabel)
        contentView.addSubview(badgePill)
        contentView.addSubview(lockBadge)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            scrim.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrim.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            scrim.heightAnchor.constraint(
                equalTo: contentView.heightAnchor, multiplier: Self.scrimHeightRatio),

            nameLabel.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: Theme.Spacing.sm),
            nameLabel.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -Theme.Spacing.sm),
            nameLabel.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor, constant: -Theme.Spacing.sm),

            badgePill.topAnchor.constraint(
                equalTo: contentView.topAnchor, constant: Theme.Spacing.xs),
            badgePill.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -Theme.Spacing.xs),

            badgeLabel.topAnchor.constraint(
                equalTo: badgePill.topAnchor, constant: Theme.Spacing.xxs),
            badgeLabel.bottomAnchor.constraint(
                equalTo: badgePill.bottomAnchor, constant: -Theme.Spacing.xxs),
            badgeLabel.leadingAnchor.constraint(
                equalTo: badgePill.leadingAnchor, constant: Theme.Spacing.xs),
            badgeLabel.trailingAnchor.constraint(
                equalTo: badgePill.trailingAnchor, constant: -Theme.Spacing.xs),

            lockBadge.topAnchor.constraint(
                equalTo: contentView.topAnchor, constant: Theme.Spacing.xs),
            lockBadge.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: Theme.Spacing.xs),
            lockBadge.widthAnchor.constraint(equalToConstant: Self.lockBadgeSide),
            lockBadge.heightAnchor.constraint(equalToConstant: Self.lockBadgeSide),
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The badge grows with Dynamic Type, so its radius cannot be a constant
        // if it is to stay a pill rather than becoming a rounded rectangle at
        // the accessibility sizes.
        badgePill.layer.cornerRadius = badgePill.bounds.height / 2
    }

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
    ///   - badge: an optional, already-localized top-right caption ("4 frames").
    ///   - locked: shows the premium lock.
    ///   - preview: the render, invoked off the first layout pass. The caller
    ///     supplies a closure rather than an image so a cold showcase render —
    ///     which composites real photographs through `CollageRenderer` — is
    ///     never paid for by a cell that has already been cancelled (recycled
    ///     or reconfigured) before it runs.
    func configure(
        name: String,
        identifier: String,
        badge: String? = nil,
        locked: Bool = false,
        preview: @escaping () -> CGImage?
    ) {
        nameLabel.text = name
        badgeLabel.text = badge
        badgePill.isHidden = badge == nil
        lockBadge.isHidden = !locked

        accessibilityIdentifier = identifier
        accessibilityLabel = name
        // The badge is a fact stated only in pixels; without this, "4 frames"
        // and the play glyph reach nobody using VoiceOver.
        accessibilityValue = badge

        previewTask?.cancel()
        previewTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            let rendered = preview()
            guard !Task.isCancelled, let self else { return }
            // Cross-dissolve rather than a hard swap: the well → photograph pop
            // is very visible on a card this size. Reduce Motion shortens it
            // through `Theme.Motion.duration` rather than removing it, since a
            // fade is not motion.
            UIView.transition(
                with: self.imageView,
                duration: Theme.Motion.duration(Theme.Motion.quick),
                options: [.transitionCrossDissolve, .allowUserInteraction]
            ) {
                self.imageView.image = rendered.map { UIImage(cgImage: $0) }
            }
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
        badgeLabel.text = nil
        badgePill.isHidden = true
        lockBadge.isHidden = true
        accessibilityValue = nil
    }
}
