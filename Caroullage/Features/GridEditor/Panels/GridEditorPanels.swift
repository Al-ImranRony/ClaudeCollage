//
//  GridEditorPanels.swift
//  Caroullage
//
//  The content views for the collage editor's three document panels. They live
//  here rather than in the view controller because the controller was already the
//  largest file in the feature, and each of these is a self-contained group of
//  controls with one job.
//

import UIKit

/// `Grid / Shapes / Custom` over the matching picker.
@MainActor
final class LayoutPanelView: UIView {

    private let modeControl: UISegmentedControl
    private let layoutPicker: LayoutPickerView
    private let shapePicker: ShapePickerView
    private let customButton: UIButton
    private let stack: UIStackView

    init(
        modeControl: UISegmentedControl,
        layoutPicker: LayoutPickerView,
        shapePicker: ShapePickerView,
        customButton: UIButton
    ) {
        self.modeControl = modeControl
        self.layoutPicker = layoutPicker
        self.shapePicker = shapePicker
        self.customButton = customButton
        self.stack = UIStackView(arrangedSubviews: [modeControl, layoutPicker, shapePicker, customButton])
        super.init(frame: .zero)

        stack.axis = .vertical
        stack.spacing = Theme.Spacing.xs
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(
            top: 0, left: Theme.Spacing.md, bottom: 0, right: Theme.Spacing.md)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows the picker that matches the selected mode. The pickers keep their own
    /// selection state, so this only toggles visibility.
    func showPolygonControls(_ isPolygon: Bool) {
        layoutPicker.isHidden = isPolygon
        shapePicker.isHidden = !isPolygon
        customButton.isHidden = !isPolygon
    }
}

/// Spacing, Margin, Corners, Shadow and Outline — the cell frame controls.
@MainActor
final class FramePanelView: UIView {

    init(spacingSlider: UISlider, marginSlider: UISlider, cornerSlider: UISlider,
         shadowSlider: UISlider, outlineSlider: UISlider, outlineColors: UIView) {
        super.init(frame: .zero)
        EditorPanelRow.fill(self, with: EditorPanelRow.stack([
            EditorPanelRow.make(title: String(localized: "Spacing"), systemImage: "square.split.2x2",
                                trailing: spacingSlider),
            EditorPanelRow.make(title: String(localized: "Margin"), systemImage: "square.dashed",
                                trailing: marginSlider),
            EditorPanelRow.make(title: String(localized: "Corners"), systemImage: "rotate.left",
                                trailing: cornerSlider),
            EditorPanelRow.make(title: String(localized: "Shadow"), systemImage: "shadow",
                                trailing: shadowSlider),
            EditorPanelRow.make(title: String(localized: "Outline"), systemImage: "square",
                                trailing: outlineSlider),
            outlineColors,
        ]))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// A row of small colour dots for the outline colour.
@MainActor
final class OutlineColorRow: UIView {

    var onSelect: ((String) -> Void)?
    private var dots: [String: UIButton] = [:]

    init(colors: [String], selected: String) {
        super.init(frame: .zero)
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = Theme.Spacing.sm
        row.alignment = .center
        // Indented to the slider column so the dots read as the Outline row's.
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 0, left: 92, bottom: 0, right: 0)
        for hex in colors {
            let dot = OutlineDot(primaryAction: UIAction { [weak self] _ in
                Haptics.selectionChanged()
                self?.setSelected(hex)
                self?.onSelect?(hex)
            })
            dot.backgroundColor = UIColor(hex: hex)
            dot.layer.cornerRadius = 14
            dot.layer.borderColor = Theme.Color.separator.cgColor
            dot.layer.borderWidth = 1
            dot.accessibilityIdentifier = "outlineColor_\(hex)"
            dot.accessibilityLabel = Self.colorName(hex)
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 28),
                dot.heightAnchor.constraint(equalToConstant: 28),
            ])
            dots[hex] = dot
            row.addArrangedSubview(dot)
        }
        row.addArrangedSubview(UIView())
        EditorPanelRow.fill(self, with: row)
        heightAnchor.constraint(greaterThanOrEqualToConstant: Theme.Layout.minimumHitTarget).isActive = true
        setSelected(selected)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// What VoiceOver says for a swatch — a name, never a hex code.
    static func colorName(_ hex: String) -> String {
        switch hex.uppercased() {
        case "#FFFFFF": return String(localized: "White outline")
        case "#000000": return String(localized: "Black outline")
        case "#F4A7B9": return String(localized: "Pink outline")
        case "#F6D365": return String(localized: "Yellow outline")
        case "#90CAF9": return String(localized: "Blue outline")
        case "#A5D6A7": return String(localized: "Green outline")
        default: return String(localized: "Outline colour")
        }
    }

    func setSelected(_ hex: String) {
        for (key, dot) in dots {
            let isOn = key == hex
            dot.layer.borderWidth = isOn ? 3 : 1
            dot.layer.borderColor = (isOn ? Theme.Color.accent : Theme.Color.separator).cgColor
            if isOn { dot.accessibilityTraits.insert(.selected) } else { dot.accessibilityTraits.remove(.selected) }
        }
    }
}

/// A 28pt swatch whose touch target is the full 44pt minimum.
private final class OutlineDot: UIButton {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let grow = max(0, (Theme.Layout.minimumHitTarget - bounds.width) / 2)
        return bounds.insetBy(dx: -grow, dy: -grow).contains(point)
    }
}

/// Solid swatches over the drawn backgrounds (Blur, Gradient, Pattern), with
/// room for the AI generative entry as a trailing chip on the swatch row.
///
/// `generativeButton` is OPTIONAL on purpose. Image Playground needs Apple
/// Intelligence hardware, and where it cannot run the control must be absent
/// entirely rather than present-but-disabled — offering a premium feature the
/// device can never run would be false advertising. `MagicEraserUITests` pins this.
/// Today the editor always passes `nil`: the Image Playground sheet is unbuilt.
@MainActor
final class BackgroundPanelView: UIView {

    init(picker: BackgroundPickerView, styles: OptionCardStrip, generativeButton: UIButton?) {
        super.init(frame: .zero)

        let arranged: [UIView] = [picker] + (generativeButton.map { [$0] } ?? [])
        let row = UIStackView(arrangedSubviews: arranged)
        row.axis = .horizontal
        row.spacing = Theme.Spacing.xs
        row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(
            top: 0, left: 0, bottom: 0, right: Theme.Spacing.md)

        let stack = UIStackView(arrangedSubviews: [row, styles])
        stack.axis = .vertical
        stack.spacing = Theme.Spacing.xxs
        EditorPanelRow.fill(self, with: stack)
        if let generativeButton {
            generativeButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// Maps the drawn-background catalog to strip ids and back.
enum BackgroundCatalog {
    static let sections: [(title: String, prefix: String, options: [BackgroundOption])] = [
        (String(localized: "Blur"), "blur", BackgroundOption.blurs),
        (String(localized: "Gradient"), "grad", BackgroundOption.gradients),
        (String(localized: "Pattern"), "pat", BackgroundOption.patterns),
    ]

    static func option(id: String) -> BackgroundOption? {
        for section in sections {
            for (index, option) in section.options.enumerated() where "\(section.prefix)\(index)" == id {
                return option
            }
        }
        return nil
    }

    static func id(for background: CollageBackground) -> String? {
        for section in sections {
            if let index = section.options.firstIndex(where: { $0.background == background }) {
                return "\(section.prefix)\(index)"
            }
        }
        return nil
    }

    static func allItems() -> [(id: String, option: BackgroundOption)] {
        sections.flatMap { section in
            section.options.enumerated().map { ("\(section.prefix)\($0.offset)", $0.element) }
        }
    }
}
