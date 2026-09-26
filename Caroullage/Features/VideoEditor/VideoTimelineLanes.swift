//
//  VideoTimelineLanes.swift
//  Caroullage
//
//  The views `VideoTimeline` is built from: the collapsed strip, the expanded
//  lanes, and each lane's row, plus the time ruler. Split out of
//  VideoTimeline.swift (debt #2 in STATE-2026-09-06-editor-redesign.md); they
//  are internal only so the timeline in the other file can build them.
//

import UIKit

/// The 56pt-tall summary: a filmstrip track, a thin text-pill track beneath it,
/// and one playhead line over both. Hosted in a non-scrolling `UIScrollView` —
/// see VideoTimeline.swift's header for why it never actually scrolls today.
final class CollapsedStripView: UIScrollView {

    private var model = VideoTimelineModel()
    private var playheadTime: Double = 0

    private let filmstripTrack = UIView()
    private let pillTrack = UIView()
    private let playhead = UIView()

    private var clipViews: [UIView] = []
    private var pillViews: [UIView] = []

    private static let pillTrackHeight: CGFloat = Theme.Spacing.xs
    private static let trackSpacing: CGFloat = 2

    override init(frame: CGRect) {
        super.init(frame: frame)
        isScrollEnabled = false
        panGestureRecognizer.isEnabled = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never

        filmstripTrack.clipsToBounds = true
        filmstripTrack.layer.cornerRadius = Theme.Radius.sm
        filmstripTrack.layer.cornerCurve = .continuous
        filmstripTrack.backgroundColor = Theme.Color.controlFill
        addSubview(filmstripTrack)

        addSubview(pillTrack)

        playhead.backgroundColor = Theme.Color.accent
        playhead.isUserInteractionEnabled = false
        addSubview(playhead)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(model: VideoTimelineModel, playhead time: Double) {
        self.model = model
        self.playheadTime = time
        rebuildClips()
        rebuildPills()
        setNeedsLayout()
    }

    func setPlayhead(_ time: Double) {
        playheadTime = time
        setNeedsLayout()
    }

    var playheadXForTesting: CGFloat { playhead.frame.midX }

    private func rebuildClips() {
        clipViews.forEach { $0.removeFromSuperview() }
        clipViews = model.clips.map { clip in
            let view = UIView()
            if clip.isFilled {
                view.backgroundColor = Theme.Color.controlFill
                view.layer.borderColor = Theme.Color.separator.cgColor
            } else {
                view.backgroundColor = Theme.Color.cellWell
                view.layer.borderColor = Theme.Color.cellWellOutline.cgColor
            }
            view.layer.borderWidth = videoTimelineHairline
            filmstripTrack.addSubview(view)
            return view
        }
    }

    private func rebuildPills() {
        pillViews.forEach { $0.removeFromSuperview() }
        pillViews = model.textPills.map { _ in
            let view = UIView()
            view.backgroundColor = Theme.Color.accentStrong
            // Same token the equivalent expanded pill blocks use
            // (`TextPillLaneRow`); at this track's height it simply rounds
            // fully into a capsule rather than a softened rectangle.
            view.layer.cornerRadius = Theme.Radius.sm
            pillTrack.addSubview(view)
            return view
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentSize = bounds.size

        let filmHeight = max(0, bounds.height - Self.pillTrackHeight - Self.trackSpacing)
        filmstripTrack.frame = CGRect(x: 0, y: 0, width: bounds.width, height: filmHeight)
        pillTrack.frame = CGRect(
            x: 0, y: filmHeight + Self.trackSpacing, width: bounds.width, height: Self.pillTrackHeight)

        for (clip, view) in zip(model.clips, clipViews) {
            view.frame = pixelSnapped(VideoTimelineGeometry.laneRect(
                start: clip.start, duration: clip.duration,
                compositionDuration: model.duration, in: filmstripTrack.bounds))
        }
        for (pill, view) in zip(model.textPills, pillViews) {
            view.frame = pixelSnapped(VideoTimelineGeometry.laneRect(
                start: pill.start, duration: pill.end - pill.start,
                compositionDuration: model.duration, in: pillTrack.bounds))
        }

        let x = VideoTimelineGeometry.x(forTime: playheadTime, duration: model.duration, width: bounds.width)
        let clampedX = min(max(0, x - videoTimelinePlayheadWidth / 2), max(0, bounds.width - videoTimelinePlayheadWidth))
        playhead.frame = CGRect(x: pixelSnapped(clampedX), y: 0, width: videoTimelinePlayheadWidth, height: bounds.height)
    }
}

// MARK: - Expanded lanes

/// The 190pt-tall expanded view: a fixed ruler, then a vertically-scrolling
/// stack of one row per clip, a text-pill row and a music row. Vertical
/// scrolling (not mentioned by the plan) is this file's own choice, so a
/// composition with many clips degrades to "scroll for more" instead of
/// squashing every lane to illegibility inside a fixed 190pt.
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
    /// non-interactive, top-level sibling of `ruler`/`scrollView` rather than
    /// a per-row tick: vertical scrolling of the lane stack never changes
    /// where "now" is horizontally, so a fixed overlay needs no coordination
    /// with `scrollView`'s `contentOffset`/`contentSize` at all. Added last,
    /// so it paints over both the ruler and the scrolling stack beneath it.
    ///
    /// Positioned entirely by hand (`updatePlayheadPosition`), like every
    /// other playhead/tick in this file (`CollapsedStripView.playhead`,
    /// formerly the per-row ticks this replaces) — not via Auto Layout.
    ///
    /// `setPlayhead` recomputes its frame immediately rather than only
    /// calling `setNeedsLayout` and waiting for a subsequent `layoutSubviews`:
    /// `self` hosts a live `UIScrollView` (unlike `CollapsedStripView`, whose
    /// children are all plain frame-based views with none of their own
    /// constraints), and empirically, a `setPlayhead`-only invalidation — no
    /// constraint or size actually changes — was not reliably followed by
    /// another `layoutSubviews` call for a view in that shape while off-screen
    /// (no window), the situation every test here runs in. Recomputing the
    /// frame at the moment `playheadTime` changes sidesteps the question
    /// entirely; `layoutSubviews` still recomputes it too, to self-heal
    /// across a real resize/rotation the scroll view's own layout responds to.
    private let playhead = UIView()

    private var clipRows: [ClipRowView] = []
    private var model = VideoTimelineModel()
    private var playheadTime: Double = 0

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(ruler)

        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        addSubview(scrollView)

        stack.axis = .vertical
        stack.spacing = Theme.Spacing.xxs
        scrollView.addSubview(stack)

        stack.addArrangedSubview(textPillRow)
        stack.addArrangedSubview(musicRow)

        playhead.backgroundColor = Theme.Color.accent
        playhead.isUserInteractionEnabled = false
        addSubview(playhead)

        ruler.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            ruler.topAnchor.constraint(equalTo: topAnchor),
            ruler.leadingAnchor.constraint(equalTo: leadingAnchor),
            ruler.trailingAnchor.constraint(equalTo: trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: ruler.bottomAnchor),
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

    func configure(model: VideoTimelineModel, playhead time: Double) {
        self.model = model
        self.playheadTime = time

        ruler.configure(duration: model.duration)

        if clipRows.count != model.clips.count {
            clipRows.forEach {
                stack.removeArrangedSubview($0)
                $0.removeFromSuperview()
            }
            clipRows = model.clips.map { ClipRowView(clipIndex: $0.index) }
            for (offset, row) in clipRows.enumerated() {
                stack.insertArrangedSubview(row, at: offset)
            }
        }
        for (clip, row) in zip(model.clips, clipRows) {
            row.configure(clip: clip, compositionDuration: model.duration,
                          isSelected: model.selectedClipIndex == clip.index)
        }
        textPillRow.configure(pills: model.textPills, compositionDuration: model.duration,
                               selectedID: model.selectedTextID)
        musicRow.configure(title: model.musicTitle)

        setNeedsLayout()
        updatePlayheadPosition()
    }

    func setPlayhead(_ time: Double) {
        playheadTime = time
        updatePlayheadPosition()
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
        let x = VideoTimelineGeometry.x(forTime: playheadTime, duration: model.duration, width: bounds.width)
        let clampedX = min(max(0, x - videoTimelinePlayheadWidth / 2), max(0, bounds.width - videoTimelinePlayheadWidth))
        playhead.frame = CGRect(x: pixelSnapped(clampedX), y: 0, width: videoTimelinePlayheadWidth, height: bounds.height)
    }
}

/// One row = one cell's clip, spanning the full lane width; the clip itself
/// occupies only the `laneRect` for its own start/duration within that width.
final class ClipRowView: UIView {

    static let rowHeight: CGFloat = 32

    let clipIndex: Int
    let block = UIView()

    private var clipStart: Double = 0
    private var clipDuration: Double = 0
    private var compositionDuration: Double = 0

    init(clipIndex: Int) {
        self.clipIndex = clipIndex
        super.init(frame: .zero)
        block.layer.cornerRadius = Theme.Radius.sm
        block.layer.cornerCurve = .continuous
        addSubview(block)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: Self.rowHeight) }

    /// `isSelected` paints the block `Theme.Color.accent` (indigo, state)
    /// instead of its usual filled/empty ink fill — see the class header's
    /// palette note.
    func configure(clip: VideoTimelineModel.Clip, compositionDuration: Double, isSelected: Bool) {
        clipStart = clip.start
        clipDuration = clip.duration
        self.compositionDuration = compositionDuration

        if isSelected {
            block.backgroundColor = Theme.Color.accent
            block.layer.borderColor = Theme.Color.accent.cgColor
        } else if clip.isFilled {
            block.backgroundColor = Theme.Color.controlFill
            block.layer.borderColor = Theme.Color.separator.cgColor
        } else {
            block.backgroundColor = Theme.Color.cellWell
            block.layer.borderColor = Theme.Color.cellWellOutline.cgColor
        }
        block.layer.borderWidth = videoTimelineHairline
        block.isAccessibilityElement = true
        block.accessibilityLabel = clip.isFilled
            ? String(localized: "Clip \(clip.index + 1)") : String(localized: "Clip \(clip.index + 1), empty")

        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        block.frame = pixelSnapped(VideoTimelineGeometry.laneRect(
            start: clipStart, duration: clipDuration, compositionDuration: compositionDuration, in: bounds))
    }
}

/// The single text-pill lane: one row hosting every text pill's own block,
/// each positioned via its own `laneRect`, since pills (unlike clips) don't
/// each get a dedicated row.
final class TextPillLaneRow: UIView {

    static let rowHeight: CGFloat = 32

    private(set) var pills: [VideoTimelineModel.TextPill] = []
    private var compositionDuration: Double = 0
    private var blocks: [UUID: UIView] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: Self.rowHeight) }

    /// The pill matching `selectedID` paints `Theme.Color.accent` (indigo,
    /// state) instead of the usual `accentStrong` ink chip — see the class
    /// header's palette note.
    func configure(pills: [VideoTimelineModel.TextPill], compositionDuration: Double, selectedID: UUID?) {
        self.pills = pills
        self.compositionDuration = compositionDuration

        blocks.values.forEach { $0.removeFromSuperview() }
        blocks = [:]
        for pill in pills {
            let view = UIView()
            view.backgroundColor = pill.id == selectedID ? Theme.Color.accent : Theme.Color.accentStrong
            view.layer.cornerRadius = Theme.Radius.sm
            view.layer.cornerCurve = .continuous
            view.isAccessibilityElement = true
            view.accessibilityLabel = pill.label
            addSubview(view)
            blocks[pill.id] = view
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
            view.frame = pixelSnapped(VideoTimelineGeometry.laneRect(
                start: pill.start, duration: pill.end - pill.start,
                compositionDuration: compositionDuration, in: bounds))
        }
    }
}

/// A quiet, display-only row — nothing in the given API reports an edit to the
/// soundtrack, so this never needs to be more than a label.
final class MusicLaneRow: UIView {

    static let rowHeight: CGFloat = 32

    private let icon = UIImageView(image: UIImage(systemName: "music.note"))
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        icon.tintColor = Theme.Color.textSecondary
        icon.contentMode = .scaleAspectFit

        label.font = Theme.Typography.caption
        label.adjustsFontForContentSizeCategory = true
        label.textColor = Theme.Color.textSecondary

        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = Theme.Spacing.xs
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.Spacing.sm),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Theme.Spacing.sm),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: Self.rowHeight) }

    func configure(title: String?) {
        label.text = title ?? String(localized: "No music added")
        label.textColor = title == nil ? Theme.Color.textSecondary : Theme.Color.textPrimary
    }

    var labelTextForTesting: String? { label.text }
}

/// Five evenly-spaced timestamps (0%, 25%, 50%, 75%, 100% of the composition)
/// rather than a fixed tick interval — robust to any duration without needing
/// to decide a "sensible" seconds-per-tick for a 3-second vs. a 3-minute video.
final class TimeRulerView: UIView {

    static let rowHeight: CGFloat = 20
    private static let tickCount = 5

    private var duration: Double = 0
    private var labels: [UILabel] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        labels = (0..<Self.tickCount).map { _ in
            let label = UILabel()
            label.font = Theme.Typography.caption
            label.adjustsFontForContentSizeCategory = true
            label.textColor = Theme.Color.textSecondary
            addSubview(label)
            return label
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: Self.rowHeight) }

    func configure(duration: Double) {
        self.duration = duration
        for (index, label) in labels.enumerated() {
            let fraction = Double(index) / Double(Self.tickCount - 1)
            label.text = formatTimelineTime(fraction * duration)
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for (index, label) in labels.enumerated() {
            label.sizeToFit()
            let fraction = CGFloat(index) / CGFloat(Self.tickCount - 1)
            // Deliberately not `VideoTimelineGeometry.x(forTime:duration:width:)`:
            // that guards `duration > 0` and returns 0 otherwise, which would
            // collapse all five ruler labels onto the leading edge for a
            // zero-duration (empty) composition instead of spacing them
            // evenly across the track. Do not "simplify" this to route
            // through it.
            let x = fraction * bounds.width
            var frame = label.frame
            if index == 0 {
                frame.origin.x = 0
            } else if index == Self.tickCount - 1 {
                frame.origin.x = bounds.width - frame.width
            } else {
                frame.origin.x = x - frame.width / 2
            }
            frame.origin.y = 0
            label.frame = frame
        }
    }
}
