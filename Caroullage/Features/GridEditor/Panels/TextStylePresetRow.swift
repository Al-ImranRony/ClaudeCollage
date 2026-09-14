//
//  TextStylePresetRow.swift
//  Caroullage
//
//  The tier-2 text style presets as a strip of preview cards, shared by both
//  editors' Style panels. It lives beside `TextStyleSheet`, which the video
//  editor already borrows from here, rather than in the design system: it knows
//  what a `TextStyle.Kind` is, and the design system does not.
//
//  Each card shows "Aa" rendered through `TextRendering` — the one code path the
//  canvas and the export share — so the preview IS the treatment, not a drawing
//  of it. The previous row was six identical "Aa" buttons, which told the user
//  nothing about what any of them did.
//

import UIKit

@MainActor
final class TextStylePresetRow: UIView {

    /// The card size. Matches the layout and shape pickers' 60pt schematics so
    /// the three option strips in the editor share one card.
    static let cardSize: CGFloat = 60

    private var cards: [PresetCard] = []

    /// - Parameters:
    ///   - selected: the overlay's current style kind, outlined on open.
    ///   - onSelect: called with the tapped kind; the row re-highlights itself.
    init(selected: TextStyle.Kind?, onSelect: @escaping (TextStyle.Kind) -> Void) {
        super.init(frame: .zero)

        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = Theme.Spacing.sm
        row.alignment = .top

        for kind in TextStyle.Kind.allCases {
            let card = PresetCard(kind: kind)
            card.addAction(UIAction { [weak self] _ in
                Haptics.selectionChanged()
                // The editor applies the kind and its model change re-syncs the
                // row; outlining locally as well only covers the frame between.
                onSelect(kind)
                self?.setSelected(kind)
            }, for: .touchUpInside)
            cards.append(card)
            row.addArrangedSubview(card)
        }
        setSelected(selected)

        // Scrolls rather than squeezing six cards into the width — mirrors the
        // layout picker, which is also a strip of 60pt cards. The insets match
        // that picker's `contentInsets` so the two strips start on the same x.
        // `EditorControlScrollView` so a drag that begins on a held card still
        // scrolls: a phone clips the last card, and that drag is how it is reached.
        let scrollView = EditorControlScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        row.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(row)
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor,
                                         constant: Theme.Spacing.md),
            row.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor,
                                          constant: -Theme.Spacing.md),
            row.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The kind currently outlined, if any. Exposed so tests can assert the row
    /// opens on the overlay's own style rather than on nothing.
    var selectedKind: TextStyle.Kind? {
        cards.first(where: \.isSelected)?.kind
    }

    /// Outlines the card for `kind`, or none. The editors call this whenever the
    /// document changes so an undo that reverts the style moves the outline too.
    func setSelected(_ kind: TextStyle.Kind?) {
        for card in cards {
            card.isSelected = card.kind == kind
        }
    }

    // MARK: - Card

    /// A 60pt preview card with the preset's name beneath it. The whole thing —
    /// card and caption — is the control, so the caption is a tap target too.
    private final class PresetCard: UIControl {

        let kind: TextStyle.Kind
        private let card = UIView()
        private let preview = UILabel()
        private let pillLayer = CALayer()
        private let caption = UILabel()

        init(kind: TextStyle.Kind) {
            self.kind = kind
            super.init(frame: .zero)

            isAccessibilityElement = true
            accessibilityTraits = .button
            accessibilityIdentifier = "textStyle_\(kind.rawValue)"
            accessibilityLabel = kind.displayName

            card.backgroundColor = Theme.Color.controlFill
            card.layer.cornerRadius = Theme.Radius.sm
            card.layer.cornerCurve = .continuous
            card.layer.borderWidth = 2
            card.clipsToBounds = true
            card.isUserInteractionEnabled = false
            card.translatesAutoresizingMaskIntoConstraints = false
            addSubview(card)

            pillLayer.isHidden = true
            card.layer.addSublayer(pillLayer)

            preview.textAlignment = .center
            preview.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(preview)

            caption.text = kind.displayName
            caption.font = Theme.Typography.tabLabel
            caption.textColor = Theme.Color.textSecondary
            caption.textAlignment = .center
            caption.adjustsFontSizeToFitWidth = true
            caption.minimumScaleFactor = 0.8
            caption.translatesAutoresizingMaskIntoConstraints = false
            addSubview(caption)

            NSLayoutConstraint.activate([
                card.topAnchor.constraint(equalTo: topAnchor),
                card.leadingAnchor.constraint(equalTo: leadingAnchor),
                card.trailingAnchor.constraint(equalTo: trailingAnchor),
                card.widthAnchor.constraint(equalToConstant: TextStylePresetRow.cardSize),
                card.heightAnchor.constraint(equalToConstant: TextStylePresetRow.cardSize),

                preview.centerXAnchor.constraint(equalTo: card.centerXAnchor),
                preview.centerYAnchor.constraint(equalTo: card.centerYAnchor),

                caption.topAnchor.constraint(equalTo: card.bottomAnchor, constant: Theme.Spacing.xxs),
                caption.leadingAnchor.constraint(equalTo: leadingAnchor),
                caption.trailingAnchor.constraint(equalTo: trailingAnchor),
                caption.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            renderSample()
            refreshSelectionChrome()

            // Colours are baked into the attributed string and into the border's
            // `CGColor`, so light/dark has to re-render rather than rely on
            // dynamic `UIColor`s resolving themselves.
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (card: Self, _) in
                card.renderSample()
                card.refreshSelectionChrome()
            }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override var isSelected: Bool {
            didSet {
                guard isSelected != oldValue else { return }
                refreshSelectionChrome()
            }
        }

        private func refreshSelectionChrome() {
            card.layer.borderColor = (isSelected ? Theme.Color.accent : Theme.Color.separator)
                .resolvedColor(with: traitCollection).cgColor
            caption.textColor = isSelected ? Theme.Color.accent : Theme.Color.textSecondary
            caption.font = isSelected
                ? Theme.Typography.rounded(10, .bold, .caption2)
                : Theme.Typography.tabLabel
            if isSelected {
                accessibilityTraits.insert(.selected)
            } else {
                accessibilityTraits.remove(.selected)
            }
        }

        private func renderSample() {
            let sample = Self.sample(for: kind, traits: traitCollection)
            preview.attributedText = TextRendering.attributedString(for: sample, fontScale: 1)
            // `.pill` paints its background from the measured text, the way the
            // canvas and the export do — through the same painter, so the card
            // cannot drift from the canvas. The card's size is a constant, so
            // the rect is known here without waiting for a layout pass.
            let bounds = CGRect(
                origin: .zero,
                size: CGSize(width: TextStylePresetRow.cardSize, height: TextStylePresetRow.cardSize))
            TextRendering.paintBackground(
                TextRendering.backgroundRect(for: sample, in: bounds, fontScale: 1),
                colorHex: sample.style.colorHex,
                on: pillLayer)
        }

        override var isHighlighted: Bool {
            didSet {
                guard isHighlighted != oldValue else { return }
                setPressed(isHighlighted)
            }
        }

        /// The "Aa" each card renders. Monochrome on purpose: the treatment is
        /// painted in the body ink, so every card previews its own *shape*
        /// rather than a colour the user has not chosen yet. The glyph inverts
        /// where the ink would otherwise swallow it — under the two fills, and
        /// inside a stroke, which only reads as an outline around a hollow glyph.
        private static func sample(for kind: TextStyle.Kind, traits: UITraitCollection) -> TextOverlay {
            let ink = Theme.Color.textPrimary.resolvedColor(with: traits).hexStringRGB
            let onInk = Theme.Color.textOnAccent.resolvedColor(with: traits).hexStringRGB
            let glyph: String
            switch kind {
            case .pill, .highlight, .stroke: glyph = onInk
            case .plain, .shadow, .glow: glyph = ink
            }
            return TextOverlay(
                text: "Aa",
                fontSize: 22,
                colorHex: glyph,
                // A stroke's width is a fraction of its glyph (see
                // `TextRendering.applyStyle`), so 2 on a 22pt face is the
                // canvas default's 6 on 64 — the card shows the same weight.
                style: TextStyle(kind: kind, colorHex: ink, width: kind == .stroke ? 2 : 4))
        }
    }
}
