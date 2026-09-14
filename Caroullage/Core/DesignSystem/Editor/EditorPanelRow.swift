//
//  EditorPanelRow.swift
//  Caroullage
//
//  The labelled control row every inline editor panel is built from — icon,
//  title, control — and the vertical stack that holds a panel's rows inside the
//  shared margins.
//
//  This existed twice before, once per editor (`FramePanelView.row` and
//  `makeVideoPanelRow`) — identical copies, with nothing to stop the next edit
//  landing in one of them. A row that lives here is a row both editors lay out
//  the same way, which is what makes a Frame slider in the collage editor and a
//  Volume slider in the video editor read as the same control in the same app.
//

import UIKit

@MainActor
public enum EditorPanelRow {

    /// The title column. Fixed rather than intrinsic so every control in a panel
    /// starts on the same x whatever its title says — "In" and "Duration" are
    /// very different widths and the sliders under them must still line up.
    private static let titleWidth: CGFloat = 64

    /// A minimum row height so the control on the row is a full hit target, and
    /// so rows stack on a consistent rhythm however tall their control is.
    private static let minimumHeight: CGFloat = Theme.Layout.minimumHitTarget

    /// One row: icon · title · control. The control takes whatever width is left.
    public static func make(title: String, systemImage: String, trailing: UIView) -> UIStackView {
        let icon = UIImageView(image: UIImage(systemName: systemImage))
        icon.tintColor = Theme.Color.textSecondary
        icon.contentMode = .scaleAspectFit
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)

        let label = UILabel()
        label.text = title
        label.font = Theme.Typography.caption
        label.textColor = Theme.Color.textPrimary
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8

        let row = UIStackView(arrangedSubviews: [icon, label, trailing])
        row.axis = .horizontal
        row.spacing = Theme.Spacing.xs
        row.alignment = .center
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
            label.widthAnchor.constraint(equalToConstant: titleWidth),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: minimumHeight),
        ])
        return row
    }

    /// Stacks a panel's rows vertically inside the panel's horizontal margins.
    /// Any view can be a row — a `make(...)` row, a chip strip, a button.
    public static func stack(_ rows: [UIView]) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: rows)
        stack.axis = .vertical
        stack.spacing = Theme.Spacing.xxs
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(
            top: 0, left: Theme.Spacing.md, bottom: 0, right: Theme.Spacing.md)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    /// Pins `content` to fill `container`'s edges. Shared by every panel view.
    public static func fill(_ container: UIView, with content: UIView) {
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }
}
