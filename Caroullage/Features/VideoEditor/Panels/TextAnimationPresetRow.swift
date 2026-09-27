//
//  TextAnimationPresetRow.swift
//  Caroullage
//
//  The caption animations as a strip of preview cards — the video editor's
//  Motion panel. Same card grammar as `TextStylePresetRow` (60pt card, name
//  beneath, accent outline on the chosen one), and the same honesty rule: each
//  card is drawn through `TextRendering.draw` with a `TextAnimationFrame`, the
//  exact path the export takes, frozen at the moment that best says what the
//  animation does (a word still hidden, a caption mid-rise). The canvas then
//  plays the real thing when a card is chosen.
//

import UIKit

@MainActor
final class TextAnimationPresetRow: UIView {

    private var cards: [AnimationCard] = []

    init(selected: TextAnimation?, onSelect: @escaping (TextAnimation) -> Void) {
        super.init(frame: .zero)

        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = Theme.Spacing.sm
        row.alignment = .top

        for animation in TextAnimation.allCases {
            let card = AnimationCard(animation: animation)
            card.addAction(UIAction { [weak self] _ in
                Haptics.selectionChanged()
                onSelect(animation)
                self?.setSelected(animation)
            }, for: .touchUpInside)
            cards.append(card)
            row.addArrangedSubview(card)
        }
        setSelected(selected)

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

    /// The animation currently outlined, if any.
    var selectedAnimation: TextAnimation? {
        cards.first(where: \.isSelected)?.animation
    }

    func setSelected(_ animation: TextAnimation?) {
        for card in cards {
            card.isSelected = card.animation == animation
        }
    }

    // MARK: - Card

    private final class AnimationCard: UIControl {

        let animation: TextAnimation
        private let card = UIView()
        private let preview = UIImageView()
        private let caption = UILabel()

        init(animation: TextAnimation) {
            self.animation = animation
            super.init(frame: .zero)

            isAccessibilityElement = true
            accessibilityTraits = .button
            accessibilityIdentifier = "textAnimation_\(animation.rawValue)"
            accessibilityLabel = animation.displayName

            card.backgroundColor = Theme.Color.controlFill
            card.layer.cornerRadius = Theme.Radius.sm
            card.layer.cornerCurve = .continuous
            card.layer.borderWidth = 2
            card.clipsToBounds = true
            card.isUserInteractionEnabled = false
            card.translatesAutoresizingMaskIntoConstraints = false
            addSubview(card)

            preview.contentMode = .center
            preview.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(preview)

            caption.text = animation.displayName
            caption.font = Theme.Typography.tabLabel
            caption.adjustsFontForContentSizeCategory = true
            caption.textColor = Theme.Color.textSecondary
            caption.textAlignment = .center
            caption.adjustsFontSizeToFitWidth = true
            caption.minimumScaleFactor = 0.7
            caption.translatesAutoresizingMaskIntoConstraints = false
            addSubview(caption)

            let side = TextStylePresetRow.cardSize
            NSLayoutConstraint.activate([
                card.topAnchor.constraint(equalTo: topAnchor),
                card.leadingAnchor.constraint(equalTo: leadingAnchor),
                card.trailingAnchor.constraint(equalTo: trailingAnchor),
                card.widthAnchor.constraint(equalToConstant: side),
                card.heightAnchor.constraint(equalToConstant: side),
                preview.topAnchor.constraint(equalTo: card.topAnchor),
                preview.bottomAnchor.constraint(equalTo: card.bottomAnchor),
                preview.leadingAnchor.constraint(equalTo: card.leadingAnchor),
                preview.trailingAnchor.constraint(equalTo: card.trailingAnchor),

                caption.topAnchor.constraint(equalTo: card.bottomAnchor, constant: Theme.Spacing.xxs),
                caption.leadingAnchor.constraint(equalTo: leadingAnchor),
                caption.trailingAnchor.constraint(equalTo: trailingAnchor),
                caption.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            renderSample()
            refreshSelectionChrome()

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

        override var isHighlighted: Bool {
            didSet {
                guard isHighlighted != oldValue else { return }
                setPressed(isHighlighted)
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
            preview.accessibilityIdentifier = "textAnimationPreviewSample"
            let side = TextStylePresetRow.cardSize
            let ink = Theme.Color.textPrimary.resolvedColor(with: traitCollection).hexStringRGB
            let (sample, frame) = Self.snapshot(of: animation, ink: ink)
            let format = UIGraphicsImageRendererFormat.preferred()
            format.opaque = false
            let bounds = CGRect(x: 0, y: 0, width: side, height: side)
            preview.image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
                TextRendering.draw(sample, in: bounds.insetBy(dx: 4, dy: 8), fontScale: 1,
                                   context: context.cgContext, animation: frame)
            }
        }

        /// The sample caption and the instant of its animation that best shows
        /// what the animation does. Hand-picked frames rather than sampled times,
        /// so a retuned duration can never land a card on a blank moment.
        private static func snapshot(
            of animation: TextAnimation, ink: String
        ) -> (TextOverlay, TextAnimationFrame?) {
            let text: String
            switch animation {
            case .words, .wordFade: text = "Aa Bb"
            case .typewriter: text = "Abc"
            default: text = "Aa"
            }
            let sample = TextOverlay(text: text, fontSize: animation == .words || animation == .wordFade ? 17 : 22,
                                     colorHex: ink)
            let units = animation == .typewriter
                ? TextAnimationMath.characterUnits(in: text)
                : TextAnimationMath.wordUnits(in: text)
            func reveal(_ alphas: [CGFloat]) -> [TextAnimationFrame.RangeAlpha] {
                zip(units, alphas).map { .init(location: $0.location, length: $0.length, alpha: $1) }
            }
            let frame: TextAnimationFrame?
            switch animation {
            case .none: frame = nil
            case .fade: frame = TextAnimationFrame(opacity: 0.35)
            case .slide: frame = TextAnimationFrame(opacity: 0.85, offset: CGVector(dx: 0, dy: 0.28))
            case .pop: frame = TextAnimationFrame(scale: 1.3)
            case .typewriter: frame = TextAnimationFrame(rangeAlphas: reveal([1, 1, 0]))
            case .words: frame = TextAnimationFrame(rangeAlphas: reveal([1, 0]))
            case .wordFade: frame = TextAnimationFrame(rangeAlphas: reveal([1, 0.3]))
            }
            return (sample, frame)
        }
    }
}
