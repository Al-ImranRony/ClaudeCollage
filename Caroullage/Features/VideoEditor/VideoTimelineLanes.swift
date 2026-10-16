//
//  VideoTimelineLanes.swift
//  Caroullage
//
//  The views `VideoTimeline` is built from: the collapsed strip, the expanded
//  lanes, and each lane's row, plus the time ruler and the playhead. Split out
//  of VideoTimeline.swift (debt #2 in STATE-2026-09-06-editor-redesign.md);
//  they are internal only so the timeline in the other file can build them.
//
//  Every row pools its views by identity — a clip by slot, a caption by id —
//  so a model push (which arrives on every document change and every playback
//  toggle) re-aims the views that exist instead of tearing them down. That is
//  what lets a change animate, and what keeps a drag from rebuilding the very
//  block under the finger.
//

import UIKit

// MARK: - Playhead

/// The playhead: an accent bar with a soft shadow, so it reads over bright and
/// dark frames alike, optionally capped with a knob. It grows while the user
/// scrubs — the finger's confirmation that it has hold of time.
///
/// Its own frame stays `VideoTimelineLayout.playheadWidth` wide, the width the
/// geometry positions; the bar and knob draw beyond it.
final class TimelinePlayheadView: UIView {

    private let bar = UIView()
    private let knob = UIView()
    private let showsKnob: Bool

    static let barWidth: CGFloat = 3
    static let knobSize: CGFloat = 12

    init(showsKnob: Bool) {
        self.showsKnob = showsKnob
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        clipsToBounds = false

        bar.backgroundColor = Theme.Color.accent
        bar.layer.cornerRadius = Self.barWidth / 2
        bar.layer.shadowColor = UIColor.black.cgColor
        bar.layer.shadowOpacity = 0.35
        bar.layer.shadowRadius = 2
        bar.layer.shadowOffset = .zero
        addSubview(bar)

        knob.backgroundColor = Theme.Color.accent
        knob.layer.cornerRadius = Self.knobSize / 2
        knob.layer.borderWidth = 2
        knob.layer.shadowColor = UIColor.black.cgColor
        knob.layer.shadowOpacity = 0.3
        knob.layer.shadowRadius = 3
        knob.layer.shadowOffset = CGSize(width: 0, height: 1)
        knob.isHidden = !showsKnob
        addSubview(knob)

        refreshColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) {
            (view: TimelinePlayheadView, _: UITraitCollection) in view.refreshColors()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func refreshColors() {
        knob.layer.borderColor = Theme.Color.surface.resolvedColor(with: traitCollection).cgColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let knobInset = showsKnob ? Self.knobSize / 2 : 0
        bar.bounds = CGRect(x: 0, y: 0, width: Self.barWidth, height: bounds.height - knobInset)
        bar.center = CGPoint(x: bounds.midX, y: knobInset + bar.bounds.height / 2)
        knob.bounds = CGRect(x: 0, y: 0, width: Self.knobSize, height: Self.knobSize)
        knob.center = CGPoint(x: bounds.midX, y: Self.knobSize / 2)
    }

    /// Scrubbing: the bar thickens and the knob swells, springing back on release.
    func setEmphasized(_ emphasized: Bool) {
        let barScale: CGFloat = emphasized ? 1.6 : 1
        let knobScale: CGFloat = emphasized ? 1.35 : 1
        UIView.animate(
            withDuration: Theme.Motion.duration(Theme.Motion.quick), delay: 0,
            usingSpringWithDamping: Theme.Motion.effectiveSpringDamping,
            initialSpringVelocity: Theme.Motion.effectiveSpringVelocity,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.bar.transform = CGAffineTransform(scaleX: barScale, y: 1)
            self.knob.transform = CGAffineTransform(scaleX: knobScale, y: knobScale)
        }
    }

    /// Positions the playhead for `time` in a track `width` points wide,
    /// spanning `minY...maxY`. Centre-and-bounds rather than `frame`, so the
    /// emphasis transform never distorts where it sits.
    func place(atTime time: Double, duration: Double, width: CGFloat, minY: CGFloat, maxY: CGFloat) {
        let x = VideoTimelineGeometry.x(forTime: time, duration: duration, width: width)
        let w = VideoTimelineLayout.playheadWidth
        let clampedX = min(max(0, x - w / 2), max(0, width - w))
        let snappedX = VideoTimelineLayout.pixelSnapped(clampedX)
        bounds = CGRect(x: 0, y: 0, width: w, height: max(0, maxY - minY))
        center = CGPoint(x: snappedX + w / 2, y: minY + bounds.height / 2)
    }
}

// MARK: - Filmstrip tiles

/// Frames tiled across a block, picked by SOURCE time and anchored to it: a
/// tile sits where its moment falls, so trimming the leading edge uncovers
/// frames under the handle instead of sliding the whole strip along with it.
final class FilmstripTilesView: UIView {

    private var filmstrip: VideoTimelineFilmstrip?
    private var sourceStart: Double = 0
    private var sourceSpan: Double = 0
    private var tiles: [UIImageView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// - Parameters:
    ///   - sourceStart: the source time at this view's leading edge.
    ///   - sourceSpan: how many source seconds the view's width covers.
    func configure(filmstrip: VideoTimelineFilmstrip?, sourceStart: Double, sourceSpan: Double) {
        guard filmstrip != self.filmstrip || sourceStart != self.sourceStart
                || sourceSpan != self.sourceSpan else { return }
        self.filmstrip = filmstrip
        self.sourceStart = sourceStart
        self.sourceSpan = sourceSpan
        setNeedsLayout()
    }

    var hasFrames: Bool { !(filmstrip?.frames.isEmpty ?? true) }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let filmstrip, !filmstrip.frames.isEmpty, sourceSpan > 0,
              bounds.width > 0, bounds.height > 0 else {
            tiles.forEach { $0.isHidden = true }
            return
        }
        let tileWidth = max(14, bounds.height * filmstrip.aspectRatio)
        let pointsPerSecond = bounds.width / sourceSpan
        let tileSeconds = Double(tileWidth / pointsPerSecond)
        guard tileSeconds > 0 else { return }

        var used = 0
        var index = Int((sourceStart / tileSeconds).rounded(.down))
        while true {
            let tileStart = Double(index) * tileSeconds
            let x = CGFloat(tileStart - sourceStart) * pointsPerSecond
            if x >= bounds.width || used > 200 { break }
            if used == tiles.count {
                let tile = UIImageView()
                tile.contentMode = .scaleAspectFill
                tile.clipsToBounds = true
                addSubview(tile)
                tiles.append(tile)
            }
            let tile = tiles[used]
            tile.isHidden = false
            tile.frame = CGRect(x: x, y: 0, width: tileWidth, height: bounds.height)
            tile.image = filmstrip.frame(at: tileStart + tileSeconds / 2)
            used += 1
            index += 1
        }
        for tile in tiles[used...] { tile.isHidden = true }
    }
}

// MARK: - Collapsed strip

/// The summary under the header: a filmstrip of the COMPOSED collage (what the
/// export will look like, moment by moment), a thin caption track beneath it,
/// and one playhead over both. Until the collage's frames arrive — or on a
/// runtime that cannot render them — the clip blocks stand in. Hosted in a
/// non-scrolling `UIScrollView`; see VideoTimeline.swift's header.
final class CollapsedStripView: UIScrollView {

    private var model = VideoTimelineModel()
    private var playheadTime: Double = 0

    private let filmstripTrack = UIView()
    private let frames = FilmstripTilesView()
    private let captionTrack = UIView()
    private let playhead = TimelinePlayheadView(showsKnob: false)

    private var clipViews: [UIView] = []
    private var pillViews: [UUID: UIView] = [:]

    private static let filmstripInset: CGFloat = 3
    private static let captionTrackHeight: CGFloat = 4
    private static let trackSpacing: CGFloat = 3

    override init(frame: CGRect) {
        super.init(frame: frame)
        isScrollEnabled = false
        panGestureRecognizer.isEnabled = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        clipsToBounds = false

        filmstripTrack.clipsToBounds = true
        filmstripTrack.layer.cornerRadius = Theme.Radius.sm - 2
        filmstripTrack.layer.cornerCurve = .continuous
        filmstripTrack.backgroundColor = Theme.Color.controlFill
        addSubview(filmstripTrack)
        filmstripTrack.addSubview(frames)

        addSubview(captionTrack)
        addSubview(playhead)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(model: VideoTimelineModel, playhead time: Double) {
        self.model = model
        self.playheadTime = time
        syncClipViews()
        syncPillViews()
        setNeedsLayout()
    }

    func setCompositionFrames(_ images: [UIImage]) {
        let strip = images.isEmpty ? nil
            : VideoTimelineFilmstrip(frames: images, sourceDuration: model.duration)
        frames.configure(filmstrip: strip, sourceStart: 0, sourceSpan: model.duration)
        setNeedsLayout()
    }

    func setPlayhead(_ time: Double) {
        playheadTime = time
        placePlayhead()
    }

    func setScrubbing(_ scrubbing: Bool) { playhead.setEmphasized(scrubbing) }

    var playheadXForTesting: CGFloat { playhead.frame.midX }

    private func syncClipViews() {
        while clipViews.count < model.clips.count {
            let view = UIView()
            view.layer.borderWidth = VideoTimelineLayout.hairline
            filmstripTrack.insertSubview(view, belowSubview: frames)
            clipViews.append(view)
        }
        while clipViews.count > model.clips.count { clipViews.removeLast().removeFromSuperview() }
        for (clip, view) in zip(model.clips, clipViews) {
            view.backgroundColor = clip.isFilled ? Theme.Color.controlFill : Theme.Color.cellWell
            view.layer.borderColor = (clip.isFilled ? Theme.Color.separator : Theme.Color.cellWellOutline)
                .resolvedColor(with: traitCollection).cgColor
        }
    }

    private func syncPillViews() {
        let ids = Set(model.textPills.map(\.id))
        for (id, view) in pillViews where !ids.contains(id) {
            view.removeFromSuperview()
            pillViews[id] = nil
        }
        for pill in model.textPills {
            let view = pillViews[pill.id] ?? {
                let view = UIView()
                view.layer.cornerRadius = Self.captionTrackHeight / 2
                captionTrack.addSubview(view)
                pillViews[pill.id] = view
                return view
            }()
            view.backgroundColor = pill.id == model.selectedTextID ? Theme.Color.accent : Theme.Color.accentStrong
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentSize = bounds.size

        let filmHeight = max(0, bounds.height - Self.filmstripInset
                             - Self.captionTrackHeight - Self.trackSpacing)
        filmstripTrack.frame = CGRect(x: 0, y: Self.filmstripInset, width: bounds.width, height: filmHeight)
        frames.frame = filmstripTrack.bounds
        captionTrack.frame = CGRect(x: 0, y: filmstripTrack.frame.maxY + Self.trackSpacing,
                                    width: bounds.width, height: Self.captionTrackHeight)

        // The clip blocks only stand in while there is no picture of the collage.
        let showsBlocks = !frames.hasFrames
        for (clip, view) in zip(model.clips, clipViews) {
            view.isHidden = !showsBlocks
            view.frame = VideoTimelineLayout.pixelSnapped(VideoTimelineGeometry.laneRect(
                start: clip.start, duration: clip.duration,
                compositionDuration: model.duration, in: filmstripTrack.bounds))
        }
        for pill in model.textPills {
            pillViews[pill.id]?.frame = VideoTimelineLayout.pixelSnapped(VideoTimelineGeometry.laneRect(
                start: pill.start, duration: pill.end - pill.start,
                compositionDuration: model.duration, in: captionTrack.bounds))
        }
        placePlayhead()
    }

    private func placePlayhead() {
        playhead.place(atTime: playheadTime, duration: model.duration, width: bounds.width,
                       minY: 0, maxY: bounds.height)
    }
}

// MARK: - Expanded lanes

/// The expanded view: a fixed ruler, then a vertically scrolling stack of one
/// row per clip, a caption row and a music row, under one playhead. Vertical
/// scrolling keeps a many-slot layout legible instead of squashing every lane.
final class ExpandedLanesView: UIView {

    private let ruler = TimeRulerView()
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let textPillRow = TextPillLaneRow()
    private let musicRow = MusicLaneRow()

    var musicLaneTextForTesting: String? { musicRow.labelTextForTesting }

    /// Whether the lane is actually laid out, not merely configured. Without
    /// this, deleting the `addArrangedSubview` would leave the row object alive
    /// and still configured — the text assertion alone would pass against a
    /// timeline showing no music lane at all.
    var musicLaneIsLaidOutForTesting: Bool {
        musicRow.superview != nil && musicRow.bounds.height > 0
    }

    /// The single playhead for every expanded lane — ruler included. A
    /// non-interactive, top-level sibling of `ruler`/`scrollView` rather than a
    /// per-row tick: vertical scrolling never changes where "now" is
    /// horizontally. Placed by hand, immediately on every `setPlayhead` — a
    /// view hosting a live scroll view is not reliably re-laid-out off screen,
    /// the situation every test here runs in.
    private let playhead = TimelinePlayheadView(showsKnob: true)

    private var clipRows: [ClipRowView] = []
    private var model = VideoTimelineModel()
    private var playheadTime: Double = 0
    private var filmstrips: [Int: VideoTimelineFilmstrip] = [:]
    private var waveform: VideoTimelineWaveform?

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(ruler)

        scrollView.showsVerticalScrollIndicator = true
        scrollView.contentInsetAdjustmentBehavior = .never
        addSubview(scrollView)

        stack.axis = .vertical
        stack.spacing = Theme.Spacing.xxs
        scrollView.addSubview(stack)

        stack.addArrangedSubview(textPillRow)
        stack.addArrangedSubview(musicRow)

        addSubview(playhead)

        ruler.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            ruler.topAnchor.constraint(equalTo: topAnchor),
            ruler.leadingAnchor.constraint(equalTo: leadingAnchor),
            ruler.trailingAnchor.constraint(equalTo: trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: ruler.bottomAnchor, constant: Theme.Spacing.xxs),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// `animated`: glide blocks to their new places — for a change that arrives
    /// from elsewhere (undo, a panel), never for one the finger is making.
    func configure(model: VideoTimelineModel, playhead time: Double, animated: Bool) {
        self.model = model
        self.playheadTime = time

        ruler.configure(duration: model.duration)

        if clipRows.count != model.clips.count {
            while clipRows.count > model.clips.count {
                let row = clipRows.removeLast()
                stack.removeArrangedSubview(row)
                row.removeFromSuperview()
            }
            while clipRows.count < model.clips.count {
                let row = ClipRowView(clipIndex: model.clips[clipRows.count].index)
                stack.insertArrangedSubview(row, at: clipRows.count)
                clipRows.append(row)
            }
        }
        for (clip, row) in zip(model.clips, clipRows) {
            row.configure(clip: clip, compositionDuration: model.duration,
                          isSelected: model.selectedClipIndex == clip.index,
                          filmstrip: filmstrips[clip.index])
        }
        textPillRow.configure(pills: model.textPills, compositionDuration: model.duration,
                              selectedID: model.selectedTextID)
        musicRow.configure(title: model.musicTitle, waveform: waveform,
                           compositionDuration: model.duration)

        setNeedsLayout()
        updatePlayheadPosition()
        guard animated, window != nil, !Theme.Motion.isReduced else { return }
        UIView.animate(
            withDuration: Theme.Motion.standard, delay: 0,
            usingSpringWithDamping: 0.9, initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.layoutIfNeeded()
        }
    }

    func setMedia(filmstrips: [Int: VideoTimelineFilmstrip], waveform: VideoTimelineWaveform?) {
        self.filmstrips = filmstrips
        self.waveform = waveform
        for (clip, row) in zip(model.clips, clipRows) {
            row.setFilmstrip(filmstrips[clip.index])
        }
        musicRow.configure(title: model.musicTitle, waveform: waveform,
                           compositionDuration: model.duration)
    }

    func setPlayhead(_ time: Double) {
        playheadTime = time
        updatePlayheadPosition()
    }

    func setScrubbing(_ scrubbing: Bool) { playhead.setEmphasized(scrubbing) }

    /// Shows the scroll indicator briefly when there are more lanes than fit —
    /// the only hint that the stack scrolls.
    func revealOverflow() {
        guard scrollView.contentSize.height > scrollView.bounds.height + 1 else { return }
        scrollView.flashScrollIndicators()
    }

    var clipBlockViews: [(index: Int, view: UIView)] {
        clipRows.map { ($0.clipIndex, $0.block) }
    }

    var textPillBlockViews: [(id: UUID, view: UIView)] {
        textPillRow.interactiveBlocks
    }

    var playheadXForTesting: CGFloat { playhead.frame.midX }

    override func layoutSubviews() {
        super.layoutSubviews()
        updatePlayheadPosition()
    }

    private func updatePlayheadPosition() {
        playhead.place(atTime: playheadTime, duration: model.duration, width: bounds.width,
                       minY: 0, maxY: bounds.height)
    }
}

// MARK: - Clip row

/// One row = one slot's clip, spanning the full lane width; the clip itself
/// occupies only the `laneRect` for its own start/duration within it.
///
/// A filled clip shows its own frames with a badge (slot number · length). A
/// selected one wears the accent as a frame around them, with grab handles on
/// both edges — where a drag trims. An empty slot has no length, so no block;
/// a dashed "+" chip at the row's start marks the slot as waiting for a clip.
final class ClipRowView: UIView {

    static let rowHeight: CGFloat = 36
    private static let handleWidth: CGFloat = 12
    private static let selectedInset: CGFloat = 2

    let clipIndex: Int
    let block = UIView()

    private let tiles = FilmstripTilesView()
    private let badge = BadgeLabel()
    private let leadingHandle = UIImageView(image: UIImage(systemName: "chevron.compact.left"))
    private let trailingHandle = UIImageView(image: UIImage(systemName: "chevron.compact.right"))
    private let emptyChip = EmptySlotChip()

    private var clip = VideoTimelineModel.Clip(index: 0, start: 0, duration: 0, isFilled: false)
    private var compositionDuration: Double = 0
    private var isSelected = false
    private var filmstrip: VideoTimelineFilmstrip?

    init(clipIndex: Int) {
        self.clipIndex = clipIndex
        super.init(frame: .zero)

        block.layer.cornerRadius = Theme.Radius.sm - 2
        block.layer.cornerCurve = .continuous
        block.clipsToBounds = true
        addSubview(block)

        tiles.layer.cornerRadius = Theme.Radius.sm - 4
        tiles.layer.cornerCurve = .continuous
        block.addSubview(tiles)
        block.addSubview(badge)

        for handle in [leadingHandle, trailingHandle] {
            handle.tintColor = Theme.Color.textOnAccent
            handle.contentMode = .center
            handle.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
            handle.isUserInteractionEnabled = false
            block.addSubview(handle)
        }

        addSubview(emptyChip)

        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) {
            (row: ClipRowView, _: UITraitCollection) in row.applyStyle()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: Self.rowHeight) }

    /// `isSelected` paints the block `Theme.Color.accent` (indigo, state) —
    /// visible as the frame around the clip's frames — instead of its usual
    /// ink-neutral fill; see VideoTimeline.swift's palette note.
    func configure(clip: VideoTimelineModel.Clip, compositionDuration: Double, isSelected: Bool,
                   filmstrip: VideoTimelineFilmstrip?) {
        self.clip = clip
        self.compositionDuration = compositionDuration
        self.isSelected = isSelected
        self.filmstrip = filmstrip
        applyStyle()
        badge.text = "\(clip.index + 1) · \(VideoTimelineLayout.formatDuration(clip.duration))"

        block.isAccessibilityElement = true
        block.accessibilityLabel = clip.isFilled
            ? String(localized: "Clip \(clip.index + 1)") : String(localized: "Clip \(clip.index + 1), empty")
        block.accessibilityValue = clip.isFilled ? VideoTimelineLayout.spokenDuration(clip.duration) : nil
        setNeedsLayout()
    }

    func setFilmstrip(_ filmstrip: VideoTimelineFilmstrip?) {
        guard filmstrip != self.filmstrip else { return }
        self.filmstrip = filmstrip
        setNeedsLayout()
    }

    private func applyStyle() {
        if isSelected {
            block.backgroundColor = Theme.Color.accent
            block.layer.borderColor = Theme.Color.accent.resolvedColor(with: traitCollection).cgColor
        } else if clip.isFilled {
            block.backgroundColor = Theme.Color.controlFill
            block.layer.borderColor = Theme.Color.separator.resolvedColor(with: traitCollection).cgColor
        } else {
            block.backgroundColor = Theme.Color.cellWell
            block.layer.borderColor = Theme.Color.cellWellOutline.resolvedColor(with: traitCollection).cgColor
        }
        block.layer.borderWidth = isSelected ? 0 : VideoTimelineLayout.hairline
        leadingHandle.isHidden = !isSelected
        trailingHandle.isHidden = !isSelected
        emptyChip.isHidden = clip.isFilled
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        block.frame = VideoTimelineLayout.pixelSnapped(VideoTimelineGeometry.laneRect(
            start: clip.start, duration: clip.duration, compositionDuration: compositionDuration, in: bounds))

        let inset = isSelected
            ? UIEdgeInsets(top: Self.selectedInset, left: Self.handleWidth,
                           bottom: Self.selectedInset, right: Self.handleWidth)
            : .zero
        let tileFrame = block.bounds.inset(by: inset)
        tiles.frame = tileFrame.width > 0 ? tileFrame : .zero
        // The tiles cover the clip's window of its source: the block's width is
        // its duration, so the inset trims that window proportionally.
        let perPoint = block.bounds.width > 0 ? clip.duration / Double(block.bounds.width) : 0
        tiles.configure(filmstrip: filmstrip,
                        sourceStart: clip.sourceStart + Double(inset.left) * perPoint,
                        sourceSpan: Double(tiles.bounds.width) * perPoint)

        leadingHandle.frame = CGRect(x: 0, y: 0, width: Self.handleWidth, height: block.bounds.height)
        trailingHandle.frame = CGRect(x: block.bounds.width - Self.handleWidth, y: 0,
                                      width: Self.handleWidth, height: block.bounds.height)

        let badgeSize = badge.intrinsicContentSize
        let badgeOrigin = CGPoint(x: tileFrame.minX + Theme.Spacing.xxs,
                                  y: tileFrame.maxY - badgeSize.height - Theme.Spacing.xxs / 2)
        badge.frame = CGRect(origin: badgeOrigin, size: badgeSize)
        badge.isHidden = !clip.isFilled || badgeSize.width + Theme.Spacing.xs > tileFrame.width

        emptyChip.frame = CGRect(x: 0, y: 3, width: min(56, bounds.width), height: max(0, bounds.height - 6))
    }
}

/// Marks a slot with no clip yet: a dashed outline around a "+", the canvas's
/// own empty-slot vocabulary at lane scale. Decoration only — the block is
/// what VoiceOver reads ("Clip 2, empty").
final class EmptySlotChip: UIView {

    private let outline = CAShapeLayer()
    private let plus = UIImageView(image: UIImage(systemName: "plus"))

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        outline.fillColor = nil
        outline.lineWidth = 1
        outline.lineDashPattern = [4, 3]
        layer.addSublayer(outline)
        plus.tintColor = Theme.Color.textSecondary
        plus.contentMode = .center
        plus.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        addSubview(plus)
        refreshColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) {
            (view: EmptySlotChip, _: UITraitCollection) in view.refreshColors()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func refreshColors() {
        outline.strokeColor = Theme.Color.textSecondary.withAlphaComponent(0.5)
            .resolvedColor(with: traitCollection).cgColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        outline.frame = bounds
        outline.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                    cornerRadius: Theme.Radius.sm - 4).cgPath
        plus.frame = bounds
    }
}

/// A small caption on a translucent dark capsule, legible over any frame.
final class BadgeLabel: UILabel {

    private static let padding = UIEdgeInsets(top: 1, left: 5, bottom: 1, right: 5)

    override init(frame: CGRect) {
        super.init(frame: frame)
        font = Theme.Typography.monospacedDigits(10, .semibold, .caption2)
        adjustsFontForContentSizeCategory = true
        maximumContentSizeCategory = .extraExtraLarge
        textColor = .white
        backgroundColor = UIColor.black.withAlphaComponent(0.55)
        layer.cornerRadius = 4
        layer.cornerCurve = .continuous
        clipsToBounds = true
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + Self.padding.left + Self.padding.right,
                      height: size.height + Self.padding.top + Self.padding.bottom)
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: Self.padding))
    }
}

// MARK: - Caption row

/// The single caption lane: one pill per caption, each placed by its own
/// `laneRect` and labelled with the caption's text, so a lane of captions can
/// be read rather than counted.
final class TextPillLaneRow: UIView {

    static let rowHeight: CGFloat = 26

    private(set) var pills: [VideoTimelineModel.TextPill] = []
    private var compositionDuration: Double = 0
    private var blocks: [UUID: TextPillView] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: Self.rowHeight) }

    /// The pill matching `selectedID` paints `Theme.Color.accent` (indigo,
    /// state) instead of the usual `accentStrong` ink chip.
    func configure(pills: [VideoTimelineModel.TextPill], compositionDuration: Double, selectedID: UUID?) {
        self.pills = pills
        self.compositionDuration = compositionDuration

        let ids = Set(pills.map(\.id))
        for (id, view) in blocks where !ids.contains(id) {
            view.removeFromSuperview()
            blocks[id] = nil
        }
        for pill in pills {
            let view = blocks[pill.id] ?? {
                let view = TextPillView()
                addSubview(view)
                blocks[pill.id] = view
                return view
            }()
            view.configure(label: pill.label, isSelected: pill.id == selectedID)
            view.accessibilityValue = VideoTimelineLayout.spokenRange(start: pill.start, end: pill.end)
        }
        setNeedsLayout()
    }

    var interactiveBlocks: [(id: UUID, view: UIView)] {
        pills.compactMap { pill in blocks[pill.id].map { (pill.id, $0) } }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for pill in pills {
            guard let view = blocks[pill.id] else { continue }
            // TextPill is modelled as start/end; laneRect wants start/duration.
            view.frame = VideoTimelineLayout.pixelSnapped(VideoTimelineGeometry.laneRect(
                start: pill.start, duration: pill.end - pill.start,
                compositionDuration: compositionDuration, in: bounds.insetBy(dx: 0, dy: 1)))
        }
    }
}

/// One caption's pill: a text glyph and the caption itself.
final class TextPillView: UIView {

    private let icon = UIImageView(image: UIImage(systemName: "textformat"))
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = Theme.Radius.sm - 3
        layer.cornerCurve = .continuous
        clipsToBounds = true

        icon.tintColor = Theme.Color.textOnAccent
        icon.contentMode = .scaleAspectFit
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        addSubview(icon)

        label.font = Theme.Typography.rounded(12, .semibold, .caption1)
        label.adjustsFontForContentSizeCategory = true
        label.maximumContentSizeCategory = .extraExtraLarge
        label.textColor = Theme.Color.textOnAccent
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)

        isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(label text: String, isSelected: Bool) {
        backgroundColor = isSelected ? Theme.Color.accent : Theme.Color.accentStrong
        label.text = text
        accessibilityLabel = text
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let pad: CGFloat = 6
        let iconSide: CGFloat = 12
        icon.frame = CGRect(x: pad, y: (bounds.height - iconSide) / 2, width: iconSide, height: iconSide)
        icon.isHidden = bounds.width < iconSide + pad * 2
        let labelX = icon.frame.maxX + 4
        label.frame = CGRect(x: labelX, y: 0, width: max(0, bounds.width - labelX - pad), height: bounds.height)
        label.isHidden = label.frame.width < 12
    }
}

// MARK: - Music row

/// The soundtrack: a block covering the stretch of the composition the music
/// plays in, drawn as its waveform — or, with no music, a quiet line saying so.
/// Display-only: nothing in the timeline's API edits the soundtrack.
final class MusicLaneRow: UIView {

    static let rowHeight: CGFloat = 30

    private let block = UIView()
    private let waveformView = WaveformView()
    private let icon = UIImageView(image: UIImage(systemName: "music.note"))
    private let label = UILabel()

    private var hasMusic = false
    private var waveform: VideoTimelineWaveform?
    private var compositionDuration: Double = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        block.backgroundColor = Theme.Color.controlFill
        block.layer.cornerRadius = Theme.Radius.sm - 2
        block.layer.cornerCurve = .continuous
        block.clipsToBounds = true
        addSubview(block)
        block.addSubview(waveformView)

        icon.tintColor = Theme.Color.textSecondary
        icon.contentMode = .scaleAspectFit
        addSubview(icon)

        label.font = Theme.Typography.caption
        label.adjustsFontForContentSizeCategory = true
        label.textColor = Theme.Color.textSecondary
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: Self.rowHeight) }

    func configure(title: String?, waveform: VideoTimelineWaveform?, compositionDuration: Double) {
        hasMusic = title != nil
        self.waveform = waveform
        self.compositionDuration = compositionDuration
        label.text = title ?? String(localized: "No music added")
        label.textColor = title == nil ? Theme.Color.textSecondary : Theme.Color.textPrimary
        block.isHidden = !hasMusic
        waveformView.peaks = hasMusic ? (waveform?.peaks ?? []) : []
        setNeedsLayout()
    }

    var labelTextForTesting: String? { label.text }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Until the waveform is read the music is drawn across the whole lane —
        // it starts at 0:00, and most tracks outlast a collage.
        let plays = waveform?.duration ?? compositionDuration
        block.frame = VideoTimelineLayout.pixelSnapped(VideoTimelineGeometry.laneRect(
            start: 0, duration: plays, compositionDuration: compositionDuration,
            in: bounds.insetBy(dx: 0, dy: 1)))
        if block.frame.width < 1, hasMusic { block.frame = bounds.insetBy(dx: 0, dy: 1) }
        waveformView.frame = block.bounds.insetBy(dx: 0, dy: 4)

        let iconSide: CGFloat = 14
        icon.frame = CGRect(x: Theme.Spacing.xs, y: (bounds.height - iconSide) / 2, width: iconSide, height: iconSide)
        let labelX = icon.frame.maxX + Theme.Spacing.xxs
        let size = label.sizeThatFits(CGSize(width: bounds.width - labelX, height: bounds.height))
        label.frame = CGRect(x: labelX, y: (bounds.height - size.height) / 2,
                             width: min(size.width, bounds.width - labelX - Theme.Spacing.xs),
                             height: size.height)
    }
}

/// Mirrored loudness bars, one per couple of points.
final class WaveformView: UIView {

    var peaks: [Float] = [] {
        didSet { if peaks != oldValue { setNeedsLayout() } }
    }

    private let shape = CAShapeLayer()
    private static let barWidth: CGFloat = 2
    private static let barGap: CGFloat = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.addSublayer(shape)
        refreshColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) {
            (view: WaveformView, _: UITraitCollection) in view.refreshColors()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func refreshColors() {
        shape.fillColor = Theme.Color.textSecondary.withAlphaComponent(0.55)
            .resolvedColor(with: traitCollection).cgColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        shape.frame = bounds
        guard !peaks.isEmpty, bounds.width > 0, bounds.height > 0 else {
            shape.path = nil
            return
        }
        let path = UIBezierPath()
        let step = Self.barWidth + Self.barGap
        let bars = Int(bounds.width / step)
        let midY = bounds.midY
        for bar in 0 ..< bars {
            // The loudest peak in this bar's slice, so a transient is never lost
            // between two bars.
            let from = bar * peaks.count / max(1, bars)
            let to = max(from + 1, (bar + 1) * peaks.count / max(1, bars))
            let peak = peaks[min(from, peaks.count - 1) ..< min(to, peaks.count)].max() ?? 0
            let height = max(1.5, CGFloat(peak) * bounds.height)
            path.append(UIBezierPath(
                roundedRect: CGRect(x: CGFloat(bar) * step, y: midY - height / 2,
                                    width: Self.barWidth, height: height),
                cornerRadius: Self.barWidth / 2))
        }
        shape.path = path.cgPath
    }
}

// MARK: - Ruler

/// Ticks at a spacing chosen for the composition's length — a label every
/// "nice" interval (½s, 1s, 2s, 5s…) that leaves room to read it, with minor
/// ticks between — rather than five fixed labels that land on awkward times.
final class TimeRulerView: UIView {

    static let rowHeight: CGFloat = 20
    /// The narrowest a labelled interval may be drawn.
    private static let minimumLabelSpacing: CGFloat = 52

    private var duration: Double = 0
    private var labels: [UILabel] = []
    private let ticks = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        ticks.lineWidth = 1
        layer.addSublayer(ticks)
        refreshColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) {
            (view: TimeRulerView, _: UITraitCollection) in view.refreshColors()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: Self.rowHeight) }

    func configure(duration: Double) {
        guard duration != self.duration else { return }
        self.duration = duration
        setNeedsLayout()
    }

    private func refreshColors() {
        ticks.strokeColor = Theme.Color.textSecondary.withAlphaComponent(0.45)
            .resolvedColor(with: traitCollection).cgColor
    }

    /// The labelled interval, in seconds, for a track `width` points wide.
    static func majorInterval(duration: Double, width: CGFloat) -> Double {
        guard duration > 0, width > 0 else { return 1 }
        let pointsPerSecond = Double(width) / duration
        let candidates: [Double] = [0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600]
        return candidates.first { $0 * pointsPerSecond >= Double(minimumLabelSpacing) } ?? 600
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        ticks.frame = bounds
        guard duration > 0, bounds.width > 0 else {
            ticks.path = nil
            labels.forEach { $0.isHidden = true }
            return
        }
        let major = Self.majorInterval(duration: duration, width: bounds.width)
        let minor = major / (major >= 1 && major.truncatingRemainder(dividingBy: 5) == 0 ? 5 : 2)
        let path = UIBezierPath()
        var labelIndex = 0
        var tick = 0
        while true {
            let time = Double(tick) * minor
            if time > duration + 0.0001 { break }
            let x = VideoTimelineLayout.pixelSnapped(
                VideoTimelineGeometry.x(forTime: time, duration: duration, width: bounds.width)) + 0.5
            let isMajor = abs(time / major - (time / major).rounded()) < 0.0001
            let tickHeight: CGFloat = isMajor ? 6 : 3
            path.move(to: CGPoint(x: x, y: bounds.height - tickHeight))
            path.addLine(to: CGPoint(x: x, y: bounds.height))
            // No label at 0: the playhead rests there, knob and all, and the
            // start of a timeline needs no saying.
            if isMajor, tick > 0 {
                let label = labelIndex < labels.count ? labels[labelIndex] : makeLabel()
                label.isHidden = false
                label.text = VideoTimelineLayout.formatRulerTime(time, interval: major)
                label.sizeToFit()
                var frame = label.frame
                frame.origin.x = min(max(0, x - frame.width / 2), bounds.width - frame.width)
                frame.origin.y = max(0, bounds.height - tickHeight - frame.height - 1)
                label.frame = frame
                labelIndex += 1
            }
            tick += 1
            if tick > 2000 { break }
        }
        for label in labels[labelIndex...] { label.isHidden = true }
        ticks.path = path.cgPath
    }

    private func makeLabel() -> UILabel {
        let label = UILabel()
        label.font = Theme.Typography.monospacedDigits(10, .medium, .caption2)
        label.adjustsFontForContentSizeCategory = true
        label.maximumContentSizeCategory = .extraLarge
        label.textColor = Theme.Color.textSecondary
        label.isAccessibilityElement = false
        addSubview(label)
        labels.append(label)
        return label
    }
}
