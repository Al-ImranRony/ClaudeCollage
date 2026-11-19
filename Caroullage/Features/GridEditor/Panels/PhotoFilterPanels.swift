//
//  PhotoFilterPanels.swift
//  Caroullage
//
//  The two per-photo colour panels that replace the old "Edit Cell" form sheet:
//
//   • Filters — the `FilterLook` catalog as preview cards rendered from the
//     selected photo itself, an Intensity slider, and Apply to All.
//   • Adjust — one tool at a time: a strip of tool chips over a single slider,
//     the dial grammar of photo editors, instead of ten stacked sliders.
//
//  Both are inline `EditorPanel` content, so the canvas stays visible and every
//  change previews live on the photo it is changing.
//

import UIKit

// MARK: - Filters

@MainActor
final class FilterLookPanelView: UIView {

    static let noneID = "none"

    var onSelectLook: ((String?) -> Void)?
    /// `isFinal` is true on release — the caller commits one undo step then.
    var onIntensityChanged: ((Double, _ isFinal: Bool) -> Void)?
    var onApplyToAll: (() -> Void)?

    private(set) var strip: OptionCardStrip!
    let intensitySlider = UISlider()
    private var intensityRow: UIView!
    private var previewTask: Task<Void, Never>?

    init(filters: CellFilters, isPremiumUnlocked: Bool, offersApplyToAll: Bool) {
        super.init(frame: .zero)

        var sections = [OptionCardSection(title: nil, items: [
            OptionCardItem(id: Self.noneID, title: String(localized: "None"), isLocked: false),
        ])]
        for pack in FilterPack.allCases {
            let items = FilterLook.all.filter { $0.pack == pack }.map {
                OptionCardItem(id: $0.id, title: $0.name, isLocked: $0.isPremium && !isPremiumUnlocked)
            }
            sections.append(OptionCardSection(title: pack.title, items: items))
        }
        strip = OptionCardStrip(
            sections: sections, selectedID: filters.lookID ?? Self.noneID,
            accessibilityPrefix: "filterLook"
        ) { [weak self] id in
            self?.onSelectLook?(id == Self.noneID ? nil : id)
        }

        intensitySlider.minimumValue = 0
        intensitySlider.maximumValue = 1
        intensitySlider.value = Float(filters.lookIntensity)
        intensitySlider.accessibilityIdentifier = "filterIntensitySlider"
        intensitySlider.accessibilityLabel = String(localized: "Intensity")
        intensitySlider.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onIntensityChanged?(Double(self.intensitySlider.value), false)
        }, for: .valueChanged)
        intensitySlider.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onIntensityChanged?(Double(self.intensitySlider.value), true)
        }, for: [.touchUpInside, .touchUpOutside, .touchCancel])

        var trailing: UIView = intensitySlider
        if offersApplyToAll {
            var config = UIButton.Configuration.tinted()
            config.title = String(localized: "Apply to All")
            config.buttonSize = .small
            config.cornerStyle = .capsule
            config.baseForegroundColor = Theme.Color.accentStrong
            config.baseBackgroundColor = Theme.Color.accent
            let applyAll = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
                Haptics.tap()
                self?.onApplyToAll?()
            })
            applyAll.accessibilityIdentifier = "filterApplyAllButton"
            applyAll.setContentCompressionResistancePriority(.required, for: .horizontal)
            let pair = UIStackView(arrangedSubviews: [intensitySlider, applyAll])
            pair.spacing = Theme.Spacing.sm
            pair.alignment = .center
            trailing = pair
        }
        intensityRow = EditorPanelRow.make(
            title: String(localized: "Intensity"), systemImage: "dial.medium", trailing: trailing)
        // Always present, disabled under "None": hiding it would change the
        // panel's height on the first look tap, and the panel is sized on open.
        intensitySlider.isEnabled = filters.lookID != nil

        let stack = UIStackView(arrangedSubviews: [strip, EditorPanelRow.stack([intensityRow])])
        stack.axis = .vertical
        stack.spacing = Theme.Spacing.xs
        EditorPanelRow.fill(self, with: stack)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Re-states the lock badges after the user's Premium status changed.
    func setPremiumUnlocked(_ unlocked: Bool) {
        strip.setLocked { id in (FilterLook.look(id: id)?.isPremium ?? false) && !unlocked }
    }

    /// Re-syncs to the document (after a tap, an undo, or an unlock).
    func sync(to filters: CellFilters) {
        strip.setSelected(filters.lookID ?? Self.noneID)
        intensitySlider.isEnabled = filters.lookID != nil
        if !intensitySlider.isTracking { intensitySlider.value = Float(filters.lookIntensity) }
    }

    /// Renders every card from `source` — the user's own photo, so a card shows
    /// what the look does to THIS picture. Off the main actor through the same
    /// processor the cell uses; a thumbnail-sized source keeps it to tens of ms.
    func loadPreviews(from source: CGImage) {
        previewTask?.cancel()
        let thumbnail = SendablePreviewImage(image: Self.thumbnail(of: source, side: OptionCardStrip.cardSize * 2))
        let noneID = Self.noneID
        previewTask = Task { [weak self] in
            // Detached work is not a child of this task, so cancelling the panel's
            // task would not reach it on its own; forward the cancellation, or a
            // reopened panel stacks a second full render on top of the first.
            let render = Task.detached(priority: .userInitiated) { () -> [String: SendablePreviewImage] in
                var out: [String: SendablePreviewImage] = [noneID: thumbnail]
                for look in FilterLook.all {
                    if Task.isCancelled { break }
                    let filters = CellFilters(lookID: look.id)
                    out[look.id] = SendablePreviewImage(
                        image: ImageFilterProcessor.shared.apply(filters, to: thumbnail.image))
                }
                return out
            }
            let rendered = await withTaskCancellationHandler {
                await render.value
            } onCancel: {
                render.cancel()
            }
            guard let self, !Task.isCancelled else { return }
            for (id, image) in rendered { self.strip.setImage(UIImage(cgImage: image.image), for: id) }
        }
    }

    /// A square, centre-cropped thumbnail — the card is square.
    private static func thumbnail(of image: CGImage, side: CGFloat) -> CGImage {
        let pixels = Int(side * 2)
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let crop = min(width, height)
        guard let cropped = image.cropping(to: CGRect(x: (width - crop) / 2, y: (height - crop) / 2,
                                                      width: crop, height: crop)),
              let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        context.interpolationQuality = .medium
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        return context.makeImage() ?? image
    }
}

/// `CGImage` is immutable; this only lets one cross into the detached task.
/// A `CGImage` carried across an isolation boundary. Safe because a `CGImage`
/// is immutable once created; CoreGraphics just does not declare it `Sendable`.
struct SendablePreviewImage: @unchecked Sendable { let image: CGImage }

// MARK: - Adjust

@MainActor
final class AdjustPanelView: UIView {

    /// One manual adjustment: the field it drives and the slider's range.
    struct Tool {
        let id: String
        let title: String
        let symbol: String
        let keyPath: WritableKeyPath<CellFilters, Double>
        let range: ClosedRange<Double>
        var neutral: Double { CellFilters()[keyPath: keyPath] }
    }

    static let tools: [Tool] = [
        Tool(id: "brightness", title: String(localized: "Brightness"), symbol: "sun.max",
             keyPath: \.brightness, range: -0.5...0.5),
        Tool(id: "contrast", title: String(localized: "Contrast"), symbol: "circle.lefthalf.filled",
             keyPath: \.contrast, range: 0.5...1.5),
        Tool(id: "saturation", title: String(localized: "Saturation"), symbol: "drop",
             keyPath: \.saturation, range: 0...2),
        Tool(id: "warmth", title: String(localized: "Warmth"), symbol: "thermometer.medium",
             keyPath: \.warmth, range: -1...1),
        Tool(id: "highlights", title: String(localized: "Highlights"), symbol: "sun.max.circle",
             keyPath: \.highlights, range: -1...1),
        Tool(id: "shadows", title: String(localized: "Shadows"), symbol: "moon.circle",
             keyPath: \.shadows, range: -1...1),
        Tool(id: "fade", title: String(localized: "Fade"), symbol: "circle.dotted",
             keyPath: \.fade, range: 0...1),
        Tool(id: "sharpness", title: String(localized: "Sharpen"), symbol: "triangle",
             keyPath: \.sharpness, range: 0...1),
        Tool(id: "vignette", title: String(localized: "Vignette"), symbol: "smallcircle.filled.circle",
             keyPath: \.vignette, range: 0...1),
        Tool(id: "grain", title: String(localized: "Grain"), symbol: "circle.grid.3x3",
             keyPath: \.grain, range: 0...1),
    ]

    /// Live value; `isFinal` on release, when the caller commits an undo step.
    var onChange: ((CellFilters, _ isFinal: Bool) -> Void)?

    let slider = UISlider()
    private let valueLabel = UILabel()
    private var chips: [String: UIButton] = [:]
    private var filters: CellFilters
    private var activeTool: Tool = AdjustPanelView.tools[0]

    init(filters: CellFilters) {
        self.filters = filters
        super.init(frame: .zero)

        let chipRow = UIStackView()
        chipRow.axis = .horizontal
        chipRow.spacing = Theme.Spacing.xs
        for tool in Self.tools {
            var config = UIButton.Configuration.plain()
            config.image = UIImage(systemName: tool.symbol)
            config.title = tool.title
            config.imagePlacement = .top
            config.imagePadding = 4
            config.buttonSize = .small
            config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
            let chip = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
                Haptics.selectionChanged()
                self?.select(tool)
            })
            chip.accessibilityIdentifier = "adjust_\(tool.id)"
            chips[tool.id] = chip
            chipRow.addArrangedSubview(chip)
        }
        let scroll = EditorControlScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        chipRow.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(chipRow)
        NSLayoutConstraint.activate([
            chipRow.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            chipRow.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            chipRow.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor,
                                             constant: Theme.Spacing.sm),
            chipRow.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor,
                                              constant: -Theme.Spacing.sm),
            chipRow.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])

        slider.accessibilityIdentifier = "adjustSlider"
        slider.addAction(UIAction { [weak self] _ in self?.sliderMoved(isFinal: false) }, for: .valueChanged)
        slider.addAction(UIAction { [weak self] _ in self?.sliderMoved(isFinal: true) },
                         for: [.touchUpInside, .touchUpOutside, .touchCancel])

        valueLabel.font = Theme.Typography.rounded(13, .semibold, .caption1)
        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.textColor = Theme.Color.textPrimary
        valueLabel.textAlignment = .right
        valueLabel.isAccessibilityElement = false
        valueLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true

        var resetConfig = UIButton.Configuration.plain()
        resetConfig.image = UIImage(systemName: "arrow.counterclockwise")
        let reset = UIButton(configuration: resetConfig, primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            Haptics.tap()
            self.filters = self.filters.manualOnlyReset()
            self.refresh()
            self.onChange?(self.filters, true)
        })
        reset.accessibilityIdentifier = "adjustResetButton"
        reset.accessibilityLabel = String(localized: "Reset adjustments")

        let sliderRow = UIStackView(arrangedSubviews: [slider, valueLabel, reset])
        sliderRow.spacing = Theme.Spacing.sm
        sliderRow.alignment = .center

        let stack = UIStackView(arrangedSubviews: [scroll, EditorPanelRow.stack([sliderRow])])
        stack.axis = .vertical
        stack.spacing = Theme.Spacing.xs
        scroll.heightAnchor.constraint(equalToConstant: 58).isActive = true
        EditorPanelRow.fill(self, with: stack)
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Re-syncs to the document (after an undo, or a look changed elsewhere).
    func sync(to filters: CellFilters) {
        guard !slider.isTracking else { return }
        self.filters = filters
        refresh()
    }

    private func select(_ tool: Tool) {
        activeTool = tool
        refresh()
    }

    private func sliderMoved(isFinal: Bool) {
        var value = Double(slider.value)
        // A light detent at neutral, so "back to untouched" is easy to hit.
        let span = activeTool.range.upperBound - activeTool.range.lowerBound
        if abs(value - activeTool.neutral) < span * 0.02 { value = activeTool.neutral }
        filters[keyPath: activeTool.keyPath] = value
        updateValueLabel()
        refreshChipMarks()
        onChange?(filters, isFinal)
    }

    private func refresh() {
        slider.minimumValue = Float(activeTool.range.lowerBound)
        slider.maximumValue = Float(activeTool.range.upperBound)
        slider.value = Float(filters[keyPath: activeTool.keyPath])
        slider.accessibilityLabel = activeTool.title
        updateValueLabel()
        refreshChipMarks()
    }

    /// Shows the value as −100…100 (or 0…100), relative to neutral.
    private func updateValueLabel() {
        let value = filters[keyPath: activeTool.keyPath]
        let neutral = activeTool.neutral
        let half = value >= neutral ? activeTool.range.upperBound - neutral : neutral - activeTool.range.lowerBound
        let display = half > 0 ? Int(((value - neutral) / half * 100).rounded()) : 0
        valueLabel.text = display > 0 && activeTool.range.lowerBound < neutral ? "+\(display)" : "\(display)"
    }

    /// Active tool in ink; a tool that is off neutral gets the accent so the user
    /// can see at a glance which adjustments are in play.
    private func refreshChipMarks() {
        for tool in Self.tools {
            guard let chip = chips[tool.id] else { continue }
            let isActive = tool.id == activeTool.id
            let isChanged = filters[keyPath: tool.keyPath] != tool.neutral
            chip.configuration?.baseForegroundColor = isActive
                ? Theme.Color.accentStrong : (isChanged ? Theme.Color.accent : Theme.Color.textSecondary)
            if isActive { chip.accessibilityTraits.insert(.selected) } else { chip.accessibilityTraits.remove(.selected) }
        }
    }
}

private extension CellFilters {
    /// Clears the manual sliders but keeps the look — Reset in Adjust must not
    /// undo a choice made in Filters.
    func manualOnlyReset() -> CellFilters {
        CellFilters(lookID: lookID, lookIntensity: lookIntensity)
    }
}
