//
//  FilterMenuChip.swift
//  Caroullage
//
//  Step 06 — a compact pill that shows the current choice and opens a menu.
//
//  It replaces two full-width `UISegmentedControl`s that were each spending a
//  whole row of the screen on a choice most people set once: the gallery's
//  Recent/Oldest sort, and the template gallery's canvas ratio. A segmented
//  control has to draw every option all the time, so its cost grows with the
//  number of options and it never shrinks below the width of the widest one.
//  A menu chip costs the width of the current answer.
//
//  Deliberately not a `CategoryChipCell`. The chips in the template gallery are
//  tags — flat, multiple, all equal. This is a control that stands for a chosen
//  value, and the chevron is what says so.
//

import UIKit

final class FilterMenuChip: UIButton {

    /// - Parameters:
    ///   - symbolName: leading glyph, or `nil` for a title-only chip.
    ///   - identifier: accessibility identifier; the chip's label is the current
    ///     value, so this is what tests and VoiceOver navigate by.
    init(symbolName: String?, identifier: String, accessibilityLabel: String) {
        super.init(frame: .zero)

        var config = UIButton.Configuration.plain()
        config.cornerStyle = .capsule
        config.baseForegroundColor = Theme.Color.textPrimary
        config.background.backgroundColor = Theme.Color.controlFill
        config.background.strokeColor = Theme.Color.separator
        config.background.strokeWidth = 1
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 7, leading: Theme.Spacing.sm, bottom: 7, trailing: Theme.Spacing.sm)
        config.imagePadding = 5
        if let symbolName {
            config.image = UIImage(
                systemName: symbolName,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        }
        // `.popup` draws the trailing chevron every iOS pull-down button has.
        // It is a separate slot from `config.image`, which is what lets the chip
        // carry a leading glyph AND the chevron.
        config.indicator = .popup
        configuration = config

        // Selection is managed here rather than by `changesSelectionAsPrimaryAction`:
        // that convenience overwrites `configuration.attributedTitle`, which would
        // drop the chip's type styling and leave `accessibilityValue` stale.
        showsMenuAsPrimaryAction = true

        self.accessibilityIdentifier = identifier
        self.accessibilityLabel = accessibilityLabel
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Sets the displayed value. Kept separate from `menu` so the caller can
    /// rebuild the menu without restating the title.
    func setValue(_ title: String) {
        configuration?.attributedTitle = AttributedString(
            title,
            attributes: AttributeContainer([
                .font: Theme.Typography.subheadline,
                .foregroundColor: Theme.Color.textPrimary,
            ]))
        accessibilityValue = title
    }
}
