//
//  VideoEditorPanels.swift
//  Caroullage
//
//  Task 6 — the content views for the video editor's document and contextual
//  panels. Mirrors GridEditorPanels.swift's split: the controller was already
//  large, and each of these is a self-contained group of controls with one job.
//
//  Every slider/switch here is created and owned by the view controller (so its
//  target/action is wired exactly once in `setupRail`, not re-added on every
//  panel open) and simply handed in — these types are pure layout.
//

import UIKit

/// A labeled control row: icon + caption + trailing control. Matches
/// `GridEditorPanels.swift`'s `FramePanelView.row` layout so the two editors'
/// inline panels read the same way.
@MainActor
func makeVideoPanelRow(title: String, systemImage: String, trailing: UIView) -> UIStackView {
    let icon = UIImageView(image: UIImage(systemName: systemImage))
    icon.tintColor = Theme.Color.textSecondary
    icon.contentMode = .scaleAspectFit

    let label = UILabel()
    label.text = title
    label.font = Theme.Typography.caption
    label.textColor = Theme.Color.textSecondary

    let row = UIStackView(arrangedSubviews: [icon, label, trailing])
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

/// Vertically stacks a panel's rows with the shared left/right margin — mirrors
/// `FramePanelView`'s outer `rows` stack in `GridEditorPanels.swift`.
@MainActor
func wrapVideoPanelRows(_ rows: [UIView]) -> UIView {
    let stack = UIStackView(arrangedSubviews: rows)
    stack.axis = .vertical
    stack.spacing = Theme.Spacing.xs
    stack.isLayoutMarginsRelativeArrangement = true
    stack.layoutMargins = UIEdgeInsets(
        top: 0, left: Theme.Spacing.md, bottom: 0, right: Theme.Spacing.md)
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
}

/// Pins `content` to fill `container`'s edges. Shared by every panel view below.
@MainActor
private func fill(_ container: UIView, with content: UIView) {
    container.addSubview(content)
    NSLayoutConstraint.activate([
        content.topAnchor.constraint(equalTo: container.topAnchor),
        content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
    ])
}

/// The single Border slider for the video collage's Frame tool.
///
/// Unlike the grid editor's `FramePanelView`, there is only one row: a video
/// cell has no per-cell corner-radius concept — `VideoCanvasView`'s cell chrome
/// stays sharp-edged even when selected — so there is nothing for a Corners
/// slider to drive.
@MainActor
final class VideoFramePanelView: UIView {
    init(borderSlider: UISlider) {
        super.init(frame: .zero)
        fill(self, with: wrapVideoPanelRows([
            makeVideoPanelRow(title: "Border", systemImage: "square.dashed", trailing: borderSlider),
        ]))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// The selected clip's Trim tool: in/out sliders (bounded by the source's
/// duration), a Loop toggle, and a "More Options" escape hatch to the full
/// `VideoCellControlsSheet` — the sheet's draggable filmstrip and Replace/Remove
/// actions are not reproduced inline, so it stays reachable rather than retired.
@MainActor
final class ClipTrimPanelView: UIView {
    init(startSlider: UISlider, endSlider: UISlider, loopSwitch: UISwitch, moreButton: UIButton) {
        super.init(frame: .zero)
        fill(self, with: wrapVideoPanelRows([
            makeVideoPanelRow(title: "In", systemImage: "arrow.right.to.line", trailing: startSlider),
            makeVideoPanelRow(title: "Out", systemImage: "arrow.left.to.line", trailing: endSlider),
            makeVideoPanelRow(title: "Loop", systemImage: "repeat", trailing: loopSwitch),
            moreButton,
        ]))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// The selected clip's Volume tool: a Mute toggle plus the gain slider (the
/// slider stays interactive even while muted — the sheet's precedent — since
/// muting is reversible and shouldn't lose the previous level).
@MainActor
final class ClipVolumePanelView: UIView {
    init(volumeSlider: UISlider, muteSwitch: UISwitch) {
        super.init(frame: .zero)
        fill(self, with: wrapVideoPanelRows([
            makeVideoPanelRow(title: "Mute", systemImage: "speaker.slash", trailing: muteSwitch),
            makeVideoPanelRow(title: "Volume", systemImage: "speaker.wave.2", trailing: volumeSlider),
        ]))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// The selected clip's Transition tool: a row of style chips (built by the view
/// controller, since each chip's highlight must react to the others) plus the
/// intro-duration slider.
@MainActor
final class ClipTransitionPanelView: UIView {
    init(styleRow: UIView, durationSlider: UISlider) {
        super.init(frame: .zero)
        fill(self, with: wrapVideoPanelRows([
            styleRow,
            makeVideoPanelRow(title: "Duration", systemImage: "timer", trailing: durationSlider),
        ]))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// The selected text overlay's Timing tool. Numeric in/out entry is Task 8's
/// job — this is a placeholder so the tool is genuinely wired (it opens a real
/// panel with a real hit target) rather than a dead button, while touching
/// nothing about the overlay's actual timing.
@MainActor
final class TimingStubPanelView: UIView {
    init() {
        super.init(frame: .zero)
        let label = UILabel()
        label.text = "Numeric in/out timing arrives in a future update."
        label.font = Theme.Typography.caption
        label.textColor = Theme.Color.textSecondary
        label.numberOfLines = 0
        label.textAlignment = .center
        label.accessibilityIdentifier = "textTimingStubLabel"
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: Theme.Spacing.sm),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Theme.Spacing.sm),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.Spacing.md),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.Spacing.md),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// The Transition panel's style picker: a horizontally scrolling row of capsule
/// buttons that owns its own selected-state highlight.
///
/// Unlike the sliders and switches in this file, these buttons are created here
/// rather than handed in — there is a variable number of them and they carry no
/// state the controller needs to read back, so the controller only supplies the
/// "a style was picked" callback. It scrolls rather than filling the panel width
/// so "Slide ←" / "Slide →" keep their natural width instead of being squeezed
/// into five equal columns; mirrors `EditorToolRail`'s own scrollView + stack.
@MainActor
final class ClipTransitionStyleRow: UIView {

    static let options: [(label: String, style: CellTransition.Style?)] = [
        ("None", nil), ("Fade", .crossfade), ("Slide ←", .slideLeft),
        ("Slide →", .slideRight), ("Zoom", .zoomIn),
    ]

    private var buttons: [(button: UIButton, style: CellTransition.Style?)] = []

    init(selected: CellTransition.Style?, onSelect: @escaping (CellTransition.Style?) -> Void) {
        super.init(frame: .zero)

        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = Theme.Spacing.xs
        row.alignment = .center

        for option in Self.options {
            var config = UIButton.Configuration.tinted()
            config.title = option.label
            config.cornerStyle = .capsule   // never set layer.cornerRadius on a configured button
            let button = UIButton(configuration: config)
            button.accessibilityIdentifier = "clipTransition-\(option.label)"
            button.addAction(UIAction { [weak self] _ in
                onSelect(option.style)
                self?.refreshHighlight(option.style)
            }, for: .touchUpInside)
            buttons.append((button, option.style))
            row.addArrangedSubview(button)
        }
        refreshHighlight(selected)

        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        row.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(row)
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            row.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 44),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func refreshHighlight(_ selected: CellTransition.Style?) {
        for (button, style) in buttons {
            var config = button.configuration
            let isSelected = style == selected
            config?.baseBackgroundColor = isSelected ? Theme.Color.accent : Theme.Color.controlFill
            config?.baseForegroundColor = isSelected ? Theme.Color.textOnAccent : Theme.Color.textPrimary
            button.configuration = config
        }
    }
}
