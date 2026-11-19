//
//  OptionCardStrip.swift
//  Caroullage
//
//  A horizontally scrolling strip of 60pt preview cards, grouped into captioned
//  sections — the filter looks ("Film", "Mood"…) and the drawn backgrounds
//  ("Blur", "Gradient", "Pattern"). Same card grammar as `TextStylePresetRow`
//  and the layout picker: a real preview, a caption beneath, the chosen card
//  outlined in the accent, press feedback, and a lock for a Premium option.
//
//  It knows nothing about filters or backgrounds: callers hand it ids and
//  images, and get ids back.
//

import UIKit

struct OptionCardItem {
    let id: String
    let title: String
    let isLocked: Bool
    /// Shown until (or instead of) an image — e.g. "None", or a photo-less blur.
    var placeholderSymbol: String? = nil
}

struct OptionCardSection {
    let title: String?
    let items: [OptionCardItem]
}

@MainActor
final class OptionCardStrip: UIView {

    static let cardSize: CGFloat = TextStylePresetRow.cardSize

    private var cards: [String: Card] = [:]

    init(sections: [OptionCardSection], selectedID: String?,
         accessibilityPrefix: String, onSelect: @escaping (String) -> Void) {
        super.init(frame: .zero)

        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = Theme.Spacing.md
        row.alignment = .bottom

        for section in sections {
            let cardsRow = UIStackView()
            cardsRow.axis = .horizontal
            cardsRow.spacing = Theme.Spacing.sm
            cardsRow.alignment = .top
            for item in section.items {
                let card = Card(item: item, identifier: "\(accessibilityPrefix)_\(item.id)")
                card.addAction(UIAction { [weak self, weak card] _ in
                    Haptics.selectionChanged()
                    // Read before `onSelect`, which may unlock (or present the
                    // paywall): the outline follows the state the tap landed on.
                    let wasLocked = card?.isLocked ?? item.isLocked
                    onSelect(item.id)
                    // Locked cards route to the paywall; the caller re-selects on
                    // unlock, so only an unlocked tap moves the outline here.
                    if !wasLocked { self?.setSelected(item.id) }
                }, for: .touchUpInside)
                cards[item.id] = card
                cardsRow.addArrangedSubview(card)
            }

            let column = UIStackView(arrangedSubviews: [cardsRow])
            column.axis = .vertical
            column.spacing = Theme.Spacing.xxs
            column.alignment = .leading
            if let title = section.title {
                let label = UILabel()
                label.text = title.uppercased()
                label.font = Theme.Typography.rounded(10, .semibold, .caption2)
                label.adjustsFontForContentSizeCategory = true
                label.textColor = Theme.Color.textSecondary
                label.isAccessibilityElement = false
                column.insertArrangedSubview(label, at: 0)
            }
            row.addArrangedSubview(column)
        }
        setSelected(selectedID)

        let scrollView = EditorControlScrollView()
        scrollView.showsHorizontalScrollIndicator = false
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

    /// The id currently outlined, if any.
    var selectedID: String? { cards.first(where: { $0.value.isSelected })?.key }

    /// Every id in the strip, for tests.
    var itemIDs: Set<String> { Set(cards.keys) }

    func setSelected(_ id: String?) {
        for (key, card) in cards { card.isSelected = key == id }
    }

    func setImage(_ image: UIImage?, for id: String) {
        cards[id]?.setPreview(image)
    }

    /// Re-states which cards are locked — after a purchase made while the strip
    /// is on screen, so its badges do not keep claiming Premium is needed.
    func setLocked(_ isLocked: (String) -> Bool) {
        for (id, card) in cards { card.isLocked = isLocked(id) }
    }

    // MARK: - Card

    private final class Card: UIControl {

        private let card = UIView()
        private let imageView = UIImageView()
        private let symbolView = UIImageView()
        private let caption = UILabel()
        private let lockBadge = UIImageView(image: UIImage(systemName: "lock.fill"))
        private let title: String

        var isLocked: Bool {
            didSet {
                guard isLocked != oldValue else { return }
                refreshLock()
            }
        }

        init(item: OptionCardItem, identifier: String) {
            title = item.title
            isLocked = item.isLocked
            super.init(frame: .zero)
            isAccessibilityElement = true
            accessibilityTraits = .button
            accessibilityIdentifier = identifier

            card.backgroundColor = Theme.Color.controlFill
            card.layer.cornerRadius = Theme.Radius.sm
            card.layer.cornerCurve = .continuous
            card.layer.borderWidth = 2
            card.clipsToBounds = true
            card.isUserInteractionEnabled = false

            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true

            symbolView.image = item.placeholderSymbol.flatMap { UIImage(systemName: $0) }
            symbolView.tintColor = Theme.Color.textSecondary
            symbolView.contentMode = .center
            symbolView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)

            lockBadge.tintColor = .white
            lockBadge.backgroundColor = UIColor.black.withAlphaComponent(0.55)
            lockBadge.contentMode = .center
            lockBadge.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 8, weight: .bold)
            lockBadge.layer.cornerRadius = 9

            caption.text = item.title
            caption.font = Theme.Typography.tabLabel
            caption.adjustsFontForContentSizeCategory = true
            caption.textColor = Theme.Color.textSecondary
            caption.textAlignment = .center
            caption.adjustsFontSizeToFitWidth = true
            caption.minimumScaleFactor = 0.75

            for view in [card, imageView, symbolView, lockBadge, caption] {
                view.translatesAutoresizingMaskIntoConstraints = false
            }
            addSubview(card)
            card.addSubview(imageView)
            card.addSubview(symbolView)
            card.addSubview(lockBadge)
            addSubview(caption)

            let size = OptionCardStrip.cardSize
            NSLayoutConstraint.activate([
                card.topAnchor.constraint(equalTo: topAnchor),
                card.leadingAnchor.constraint(equalTo: leadingAnchor),
                card.trailingAnchor.constraint(equalTo: trailingAnchor),
                card.widthAnchor.constraint(equalToConstant: size),
                card.heightAnchor.constraint(equalToConstant: size),
                imageView.topAnchor.constraint(equalTo: card.topAnchor),
                imageView.bottomAnchor.constraint(equalTo: card.bottomAnchor),
                imageView.leadingAnchor.constraint(equalTo: card.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: card.trailingAnchor),
                symbolView.centerXAnchor.constraint(equalTo: card.centerXAnchor),
                symbolView.centerYAnchor.constraint(equalTo: card.centerYAnchor),
                lockBadge.topAnchor.constraint(equalTo: card.topAnchor, constant: 4),
                lockBadge.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -4),
                lockBadge.widthAnchor.constraint(equalToConstant: 18),
                lockBadge.heightAnchor.constraint(equalToConstant: 18),
                caption.topAnchor.constraint(equalTo: card.bottomAnchor, constant: Theme.Spacing.xxs),
                caption.leadingAnchor.constraint(equalTo: leadingAnchor),
                caption.trailingAnchor.constraint(equalTo: trailingAnchor),
                caption.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            refreshSelectionChrome()
            refreshLock()
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (card: Self, _) in
                card.refreshSelectionChrome()
            }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        private func refreshLock() {
            lockBadge.isHidden = !isLocked
            accessibilityLabel = isLocked ? String(localized: "\(title), Premium") : title
        }

        func setPreview(_ image: UIImage?) {
            imageView.image = image
            symbolView.isHidden = image != nil
        }

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
    }
}
