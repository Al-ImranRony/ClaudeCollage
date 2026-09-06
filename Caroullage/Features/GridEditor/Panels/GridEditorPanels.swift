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

/// The Border and Corners sliders.
@MainActor
final class FramePanelView: UIView {

    init(borderSlider: UISlider, cornerSlider: UISlider) {
        super.init(frame: .zero)

        let rows = UIStackView(arrangedSubviews: [
            Self.row(title: "Border", systemImage: "square.dashed", slider: borderSlider),
            Self.row(title: "Corners", systemImage: "rotate.left", slider: cornerSlider),
        ])
        rows.axis = .vertical
        rows.spacing = Theme.Spacing.xs
        rows.isLayoutMarginsRelativeArrangement = true
        rows.layoutMargins = UIEdgeInsets(
            top: 0, left: Theme.Spacing.md, bottom: 0, right: Theme.Spacing.md)
        rows.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rows)

        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: topAnchor),
            rows.bottomAnchor.constraint(equalTo: bottomAnchor),
            rows.leadingAnchor.constraint(equalTo: leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private static func row(title: String, systemImage: String, slider: UISlider) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: systemImage))
        icon.tintColor = Theme.Color.textSecondary
        icon.contentMode = .scaleAspectFit

        let label = UILabel()
        label.text = title
        label.font = Theme.Typography.caption
        label.textColor = Theme.Color.textSecondary

        let row = UIStackView(arrangedSubviews: [icon, label, slider])
        row.axis = .horizontal
        row.spacing = Theme.Spacing.xs
        row.alignment = .center
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            label.widthAnchor.constraint(equalToConstant: 62),
        ])
        return row
    }
}

/// The background swatches, with the AI generative entry as the trailing chip.
///
/// `generativeButton` is OPTIONAL on purpose. Image Playground needs Apple
/// Intelligence hardware, and where it cannot run the control must be absent
/// entirely rather than present-but-disabled — offering a premium feature the
/// device can never run would be false advertising. `MagicEraserUITests` pins this.
@MainActor
final class BackgroundPanelView: UIView {

    init(picker: BackgroundPickerView, generativeButton: UIButton?) {
        super.init(frame: .zero)

        let arranged: [UIView] = [picker] + (generativeButton.map { [$0] } ?? [])
        let row = UIStackView(arrangedSubviews: arranged)
        row.axis = .horizontal
        row.spacing = Theme.Spacing.xs
        row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(
            top: 0, left: 0, bottom: 0, right: Theme.Spacing.md)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        var constraints = [
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
        ]
        if let generativeButton {
            constraints.append(generativeButton.widthAnchor.constraint(equalToConstant: 44))
        }
        NSLayoutConstraint.activate(constraints)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
