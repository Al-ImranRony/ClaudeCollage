//
//  VideoTimeline.swift
//  Caroullage
//
//  Task 5 — the video editor's collapsible timeline. Two states, remembered per
//  project by whoever owns this view (this file has no notion of "the project"):
//  a 56pt collapsed strip that summarises the whole composition, and a 190pt
//  expanded view with one lane per cell, a text-pill lane and a music lane, all
//  sharing one playhead.
//
//  Pure renderer, like `EditorToolRail`/`EditorPanel`: every interaction is
//  reported through a callback, and every visible change — the model, the
//  playhead, the collapsed/expanded state — arrives through a setter the owner
//  calls. This view never edits the document; the four bugs Plan 1 shipped were
//  all in views that quietly knew too much.
//
//  Geometry is `VideoTimelineGeometry`'s job, not this file's — every position
//  on screen comes from `x(forTime:duration:width:)` or `laneRect`, using this
//  view's own bounds.width as the track width. That is a deliberate
//  simplification: the geometry helper takes a single `width` standing for the
//  *entire* composition duration, which only makes sense under a proportional
//  "fit the whole timeline to the screen" model, not a zoomed/scrollable one —
//  a real pixels-per-second scrubber would need a content width independent of
//  the viewport, which isn't what `VideoTimelineGeometry` was built to hand
//  back. The collapsed strip is still hosted in a genuine (non-scrolling)
//  `UIScrollView` per the plan's note, with its own pan gesture disabled so it
//  can't fight the timeline's own gesture recognizers for touches.
//
//  Gestures are attached once, to this view (`self`), not to individual clip or
//  pill blocks: `location(in:)` is read against the timeline itself and turned
//  into a time with `VideoTimelineGeometry.time(forX:...)`, then dispatched by
//  asking which block (if any) the point falls in. Centralising it here is what
//  makes the stale-drag guard (Trap #4) a single check in one place: `setModel`
//  clears `activeDrag` unconditionally, so a trim/retime/scrub already in
//  flight when the document changes underneath it stops reporting rather than
//  continuing to act on a clip index or text id the new model may not have.
//
//  Palette: the playhead is state (`Theme.Color.accent`, indigo) because it is
//  literally "what position is current"; everything else — filled/empty clip
//  fills, text-pill chips, the ruler — is chrome (ink), because the model has
//  no notion of a *selected* clip or pill for indigo to mark.
//
//  Scope deliberately left out of this task: the design lists a play control in
//  the collapsed strip, but nothing in the given API reports it (no callback,
//  and no "isPlaying" field on the model to render its icon from), and every
//  other listed element maps cleanly onto setModel/setPlayhead/onToggleState.
//  Rather than ship a control with nowhere to report through — the exact
//  "controls that are not wired" trap this plan calls out — it is left out
//  here; VideoEditorViewController already owns a transport play button.
//  Likewise the collapsed strip only scrubs (its 32pt-tall summary track is too
//  small for reliable per-clip taps); selecting a clip or a text pill, and
//  trimming/retiming, are expanded-lanes-only interactions.
//

import UIKit

// MARK: - Model

public struct VideoTimelineModel: Equatable, Sendable {

    public struct Clip: Equatable, Sendable {
        public let index: Int
        public let start: Double
        public let duration: Double
        public let isFilled: Bool

        public init(index: Int, start: Double, duration: Double, isFilled: Bool) {
            self.index = index
            self.start = start
            self.duration = duration
            self.isFilled = isFilled
        }
    }

    public struct TextPill: Equatable, Sendable {
        public let id: UUID
        public let label: String
        public let start: Double
        public let end: Double

        public init(id: UUID, label: String, start: Double, end: Double) {
            self.id = id
            self.label = label
            self.start = start
            self.end = end
        }
    }

    public var duration: Double
    public var clips: [Clip]
    public var textPills: [TextPill]
    public var musicTitle: String?

    public init(
        duration: Double = 0,
        clips: [Clip] = [],
        textPills: [TextPill] = [],
        musicTitle: String? = nil
    ) {
        self.duration = duration
        self.clips = clips
        self.textPills = textPills
        self.musicTitle = musicTitle
    }
}

// MARK: - File-scope constants

/// This codebase's hairline idiom: a flat point constant rather than a
/// `UIScreen.main.scale`-derived value (`UIScreen.main` is deprecated as of
/// iOS 26). Matches `EditorToolRail.separatorHeight` / `EditorPanel.separatorHeight`.
private let videoTimelineHairline: CGFloat = 1
private let videoTimelinePlayheadWidth: CGFloat = 2

/// Rounds a value to the nearest whole point. `VideoTimelineGeometry` returns
/// fractional points; for the same reason this file doesn't chase an exact
/// device pixel grid via `UIScreen.main.scale` (deprecated, and wrong on an
/// external display anyway), block and playhead edges are snapped to whole
/// points instead — crisper than a fractional edge on any scale, without
/// depending on which scale it is.
private func pixelSnapped(_ value: CGFloat) -> CGFloat { value.rounded() }

private func pixelSnapped(_ rect: CGRect) -> CGRect {
    let minX = pixelSnapped(rect.minX)
    let maxX = pixelSnapped(rect.minX + rect.width)
    return CGRect(x: minX, y: rect.minY, width: max(0, maxX - minX), height: rect.height)
}

private func formatTimelineTime(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded()))
    return String(format: "%d:%02d", total / 60, total % 60)
}

// MARK: - VideoTimeline

@MainActor
public final class VideoTimeline: UIView {

    public enum State: Equatable {
        case collapsed, expanded
    }

    public var onScrub: ((Double) -> Void)?
    public var onToggleState: ((State) -> Void)?
    public var onSelectClip: ((Int) -> Void)?
    public var onSelectText: ((UUID) -> Void)?
    public var onTrim: ((_ clipIndex: Int, _ start: Double, _ end: Double) -> Void)?
    public var onRetimeText: ((_ id: UUID, _ start: Double, _ end: Double) -> Void)?

    public static let collapsedHeight: CGFloat = 56
    public static let expandedHeight: CGFloat = 190

    private static let headerHeight: CGFloat = 24
    private static let chevronWidth: CGFloat = 32
    /// Touch slop for grabbing a clip/pill's edge to trim/retime rather than
    /// its middle to select. `Theme.Spacing.sm` rather than a bespoke literal.
    private static let edgeTolerance: CGFloat = Theme.Spacing.sm
    /// A clip/pill can never be trimmed narrower than this, so a fast drag past
    /// the opposite edge can't invert start/end or produce a zero/negative span.
    private static let minimumTrimDuration: Double = 0.1

    public private(set) var state: State = .collapsed

    private var model = VideoTimelineModel()
    private var playheadTime: Double = 0

    private let headerRow = UIView()
    private let timeLabel = UILabel()
    private let chevronButton = UIControl()
    private let chevronImageView = UIImageView()

    private let contentHost = UIView()
    private let collapsedContent = CollapsedStripView()
    private let expandedContent = ExpandedLanesView()

    private var heightConstraint: NSLayoutConstraint!

    private lazy var tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
    private lazy var panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))

    private enum Edge { case leading, trailing }

    private enum DragTarget {
        case background
        case clipMiddle(Int)
        case clipEdge(Int, Edge)
        case textMiddle(UUID)
        case textEdge(UUID, Edge)
    }

    private enum ActiveDrag {
        case scrub
        case trimClip(index: Int, edge: Edge, start: Double, duration: Double)
        case retimeText(id: UUID, edge: Edge, start: Double, end: Double)
    }

    /// Cleared unconditionally by `setModel`. That single rule is the whole of
    /// Trap #4's fix here: a drag captured an index/id from the model in effect
    /// when it began, and the moment that model is replaced, continuing the
    /// same gesture must stop reporting rather than act on a clip or text id
    /// the new model may not even have.
    private var activeDrag: ActiveDrag?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.Color.surface
        setupChrome()

        heightConstraint = heightAnchor.constraint(equalToConstant: Self.collapsedHeight)
        heightConstraint.isActive = true

        panGesture.delegate = self
        tapGesture.delegate = self
        addGestureRecognizer(panGesture)
        addGestureRecognizer(tapGesture)

        updateChevron()
        updateReadouts()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Public API

    public func setModel(_ newModel: VideoTimelineModel) {
        model = newModel
        activeDrag = nil
        collapsedContent.configure(model: model, playhead: playheadTime)
        expandedContent.configure(model: model, playhead: playheadTime)
        updateReadouts()
        setNeedsLayout()
    }

    public func setPlayhead(_ time: Double) {
        playheadTime = time
        collapsedContent.setPlayhead(time)
        expandedContent.setPlayhead(time)
        updateReadouts()
    }

    public func setState(_ newState: State, animated: Bool) {
        guard newState != state else { return }
        state = newState
        collapsedContent.isHidden = state != .collapsed
        expandedContent.isHidden = state != .expanded
        updateChevron()
        heightConstraint.constant = state == .collapsed ? Self.collapsedHeight : Self.expandedHeight

        guard animated, !Theme.Motion.isReduced else {
            applyPendingLayout()
            return
        }
        UIView.animate(withDuration: Theme.Motion.standard) { [weak self] in
            self?.applyPendingLayout()
        }
    }

    private func applyPendingLayout() {
        if let superview {
            superview.layoutIfNeeded()
        } else {
            layoutIfNeeded()
        }
    }

    // MARK: - Chrome

    private func setupChrome() {
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerRow)

        timeLabel.font = Theme.Typography.caption
        timeLabel.textColor = Theme.Color.textSecondary
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addSubview(timeLabel)

        chevronImageView.tintColor = Theme.Color.textSecondary
        chevronImageView.contentMode = .center
        chevronImageView.isUserInteractionEnabled = false
        chevronImageView.translatesAutoresizingMaskIntoConstraints = false
        chevronButton.addSubview(chevronImageView)

        chevronButton.accessibilityIdentifier = "videoTimelineChevron"
        chevronButton.addTarget(self, action: #selector(chevronTapped), for: .touchUpInside)
        chevronButton.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addSubview(chevronButton)

        contentHost.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentHost)

        collapsedContent.translatesAutoresizingMaskIntoConstraints = false
        expandedContent.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(collapsedContent)
        contentHost.addSubview(expandedContent)
        expandedContent.isHidden = true

        NSLayoutConstraint.activate([
            headerRow.topAnchor.constraint(equalTo: topAnchor),
            headerRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerRow.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerRow.heightAnchor.constraint(equalToConstant: Self.headerHeight),

            timeLabel.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor, constant: Theme.Spacing.md),
            timeLabel.centerYAnchor.constraint(equalTo: headerRow.centerYAnchor),

            // The image is centred within the button, but the button itself is
            // pinned top/bottom to a non-zero-height ancestor (headerRow) and
            // given an explicit width — the button's own hit-testable bounds
            // never depend on the image view's intrinsic size. See the class
            // header and `EditorToolRail.ToolButton`'s own regression note for
            // why a center-only pin on the CONTROL itself is the trap.
            chevronImageView.centerXAnchor.constraint(equalTo: chevronButton.centerXAnchor),
            chevronImageView.topAnchor.constraint(equalTo: chevronButton.topAnchor),
            chevronImageView.bottomAnchor.constraint(equalTo: chevronButton.bottomAnchor),

            chevronButton.trailingAnchor.constraint(equalTo: headerRow.trailingAnchor, constant: -Theme.Spacing.xs),
            chevronButton.topAnchor.constraint(equalTo: headerRow.topAnchor),
            chevronButton.bottomAnchor.constraint(equalTo: headerRow.bottomAnchor),
            chevronButton.widthAnchor.constraint(equalToConstant: Self.chevronWidth),

            contentHost.topAnchor.constraint(equalTo: headerRow.bottomAnchor),
            contentHost.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentHost.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentHost.bottomAnchor.constraint(equalTo: bottomAnchor),

            collapsedContent.topAnchor.constraint(equalTo: contentHost.topAnchor),
            collapsedContent.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            collapsedContent.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            collapsedContent.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),

            expandedContent.topAnchor.constraint(equalTo: contentHost.topAnchor),
            expandedContent.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            expandedContent.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            expandedContent.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
        ])
    }

    @objc private func chevronTapped() {
        Haptics.tap()
        onToggleState?(state == .collapsed ? .expanded : .collapsed)
    }

    private func updateChevron() {
        let symbol = state == .collapsed ? "chevron.down" : "chevron.up"
        chevronImageView.image = UIImage(systemName: symbol)
        chevronButton.accessibilityLabel = state == .collapsed ? "Expand timeline" : "Collapse timeline"
    }

    private func updateReadouts() {
        timeLabel.text = "\(formatTimelineTime(playheadTime)) / \(formatTimelineTime(model.duration))"
    }

    // MARK: - Gestures

    private func timeForX(_ x: CGFloat) -> Double {
        VideoTimelineGeometry.time(forX: x, duration: model.duration, width: bounds.width)
    }

    private func clamped(_ value: Double, _ lowerBound: Double, _ upperBound: Double) -> Double {
        guard lowerBound <= upperBound else { return lowerBound }
        return min(max(value, lowerBound), upperBound)
    }

    /// Only meaningful while expanded — the collapsed strip has no per-clip or
    /// per-pill targets, only a scrub track (see the class header).
    private func hitTarget(at point: CGPoint) -> DragTarget {
        guard state == .expanded else { return .background }

        for (index, view) in expandedContent.clipBlockViews {
            let frame = view.convert(view.bounds, to: self)
            guard frame.contains(point) else { continue }
            if point.x <= frame.minX + Self.edgeTolerance { return .clipEdge(index, .leading) }
            if point.x >= frame.maxX - Self.edgeTolerance { return .clipEdge(index, .trailing) }
            return .clipMiddle(index)
        }
        for (id, view) in expandedContent.textPillBlockViews {
            let frame = view.convert(view.bounds, to: self)
            guard frame.contains(point) else { continue }
            if point.x <= frame.minX + Self.edgeTolerance { return .textEdge(id, .leading) }
            if point.x >= frame.maxX - Self.edgeTolerance { return .textEdge(id, .trailing) }
            return .textMiddle(id)
        }
        return .background
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        performTap(at: gesture.location(in: self))
    }

    private func performTap(at point: CGPoint) {
        switch hitTarget(at: point) {
        case .clipMiddle(let index):
            Haptics.selectionChanged()
            onSelectClip?(index)
        case .textMiddle(let id):
            Haptics.selectionChanged()
            onSelectText?(id)
        case .background, .clipEdge, .textEdge:
            let time = timeForX(point.x)
            setPlayhead(time)
            onScrub?(time)
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: self)
        switch gesture.state {
        case .began:
            performPanBegan(at: point)
        case .changed:
            performPanContinue(at: point)
        case .ended, .cancelled, .failed:
            performPanEnd(at: point)
        default:
            break
        }
    }

    private func performPanBegan(at point: CGPoint) {
        switch hitTarget(at: point) {
        case .clipEdge(let index, let edge):
            guard let clip = model.clips.first(where: { $0.index == index }) else {
                activeDrag = nil
                return
            }
            activeDrag = .trimClip(index: index, edge: edge, start: clip.start, duration: clip.duration)
        case .textEdge(let id, let edge):
            guard let pill = model.textPills.first(where: { $0.id == id }) else {
                activeDrag = nil
                return
            }
            activeDrag = .retimeText(id: id, edge: edge, start: pill.start, end: pill.end)
        case .background, .clipMiddle, .textMiddle:
            // Dragging anywhere that isn't an edge handle scrubs, including
            // over a clip's middle — only a plain tap there selects.
            activeDrag = .scrub
        }
        performPanContinue(at: point)
    }

    private func performPanContinue(at point: CGPoint) {
        guard let drag = activeDrag else { return }
        let time = timeForX(point.x)

        switch drag {
        case .scrub:
            setPlayhead(time)
            onScrub?(time)

        case .trimClip(let index, let edge, let start, let duration):
            let end = start + duration
            switch edge {
            case .leading:
                let newStart = clamped(time, 0, end - Self.minimumTrimDuration)
                onTrim?(index, newStart, end)
            case .trailing:
                let newEnd = clamped(time, start + Self.minimumTrimDuration, model.duration)
                onTrim?(index, start, newEnd)
            }

        case .retimeText(let id, let edge, let start, let end):
            switch edge {
            case .leading:
                let newStart = clamped(time, 0, end - Self.minimumTrimDuration)
                onRetimeText?(id, newStart, end)
            case .trailing:
                let newEnd = clamped(time, start + Self.minimumTrimDuration, model.duration)
                onRetimeText?(id, start, newEnd)
            }
        }
    }

    private func performPanEnd(at point: CGPoint) {
        performPanContinue(at: point)
        activeDrag = nil
    }

    // MARK: - Test seams

    /// The chevron itself. Exposed only so tests can inspect real geometry and
    /// hit-testing; production code has no need to reach past `onToggleState`.
    /// Mirrors `EditorPanel.closeButtonForHitTesting`.
    var chevronButtonForHitTesting: UIControl { chevronButton }

    func simulateChevronTap() { chevronButton.sendActions(for: .touchUpInside) }

    var heightForTesting: CGFloat { heightConstraint.constant }

    var expandedClipLaneCount: Int { expandedContent.clipBlockViews.count }
    var expandedTextPillCount: Int { expandedContent.textPillBlockViews.count }

    /// The x position of the currently-visible state's playhead indicator, in
    /// this view's own coordinate space.
    var playheadXForTesting: CGFloat {
        state == .collapsed ? collapsedContent.playheadXForTesting : expandedContent.playheadXForTesting
    }

    /// A clip block's on-screen frame, converted into this view's coordinate
    /// space, for computing real edge/middle touch points in tests.
    func frameForClip(at index: Int) -> CGRect? {
        guard let entry = expandedContent.clipBlockViews.first(where: { $0.index == index }) else { return nil }
        return entry.view.convert(entry.view.bounds, to: self)
    }

    func frameForTextPill(id: UUID) -> CGRect? {
        guard let entry = expandedContent.textPillBlockViews.first(where: { $0.id == id }) else { return nil }
        return entry.view.convert(entry.view.bounds, to: self)
    }

    /// Drives the same path a real tap does, without needing a live touch.
    /// Mirrors `EditorToolRail.simulateTap` / `EditorPanel.simulateClose`.
    func simulateTap(at point: CGPoint) { performTap(at: point) }

    func simulatePanBegan(at point: CGPoint) { performPanBegan(at: point) }
    func simulatePanChanged(at point: CGPoint) { performPanContinue(at: point) }
    func simulatePanEnded(at point: CGPoint) { performPanEnd(at: point) }
}

// MARK: - UIGestureRecognizerDelegate

extension VideoTimeline: UIGestureRecognizerDelegate {
    /// The header (readouts + chevron) handles its own touches; the tap/pan
    /// recognizers on `self` must not also see them, or tapping the chevron
    /// would toggle state AND scrub/select at the same time.
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let touchView = touch.view else { return true }
        return !touchView.isDescendant(of: headerRow)
    }
}

// MARK: - Collapsed strip

/// The 56pt-tall summary: a filmstrip track, a thin text-pill track beneath it,
/// and one playhead line over both. Hosted in a non-scrolling `UIScrollView` —
/// see the file header for why it never actually scrolls today.
private final class CollapsedStripView: UIScrollView {

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
            view.layer.cornerRadius = 2
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
private final class ExpandedLanesView: UIView {

    private let ruler = TimeRulerView()
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let textPillRow = TextPillLaneRow()
    private let musicRow = MusicLaneRow()

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

    func configure(model: VideoTimelineModel, playhead: Double) {
        self.model = model
        self.playheadTime = playhead

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
            row.configure(clip: clip, compositionDuration: model.duration, playhead: playheadTime)
        }
        textPillRow.configure(pills: model.textPills, compositionDuration: model.duration, playhead: playheadTime)
        musicRow.configure(title: model.musicTitle)
    }

    func setPlayhead(_ time: Double) {
        playheadTime = time
        clipRows.forEach { $0.setPlayhead(time) }
        textPillRow.setPlayhead(time)
    }

    var clipBlockViews: [(index: Int, view: UIView)] {
        clipRows.map { ($0.clipIndex, $0.block) }
    }

    var textPillBlockViews: [(id: UUID, view: UIView)] {
        textPillRow.interactiveBlocks
    }

    var playheadXForTesting: CGFloat {
        clipRows.first?.tickXForTesting ?? textPillRow.tickXForTesting
    }
}

/// One row = one cell's clip, spanning the full lane width; the clip itself
/// occupies only the `laneRect` for its own start/duration within that width.
private final class ClipRowView: UIView {

    static let rowHeight: CGFloat = 32

    let clipIndex: Int
    let block = UIView()
    private let tick = UIView()

    private var clipStart: Double = 0
    private var clipDuration: Double = 0
    private var compositionDuration: Double = 0
    private var playheadTime: Double = 0

    init(clipIndex: Int) {
        self.clipIndex = clipIndex
        super.init(frame: .zero)
        block.layer.cornerRadius = Theme.Radius.sm
        block.layer.cornerCurve = .continuous
        addSubview(block)

        tick.backgroundColor = Theme.Color.accent
        tick.isUserInteractionEnabled = false
        addSubview(tick)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: Self.rowHeight) }

    func configure(clip: VideoTimelineModel.Clip, compositionDuration: Double, playhead: Double) {
        clipStart = clip.start
        clipDuration = clip.duration
        self.compositionDuration = compositionDuration
        playheadTime = playhead

        if clip.isFilled {
            block.backgroundColor = Theme.Color.controlFill
            block.layer.borderColor = Theme.Color.separator.cgColor
        } else {
            block.backgroundColor = Theme.Color.cellWell
            block.layer.borderColor = Theme.Color.cellWellOutline.cgColor
        }
        block.layer.borderWidth = videoTimelineHairline
        block.isAccessibilityElement = true
        block.accessibilityLabel = clip.isFilled ? "Clip \(clip.index + 1)" : "Clip \(clip.index + 1), empty"

        setNeedsLayout()
    }

    func setPlayhead(_ time: Double) {
        playheadTime = time
        setNeedsLayout()
    }

    var tickXForTesting: CGFloat { tick.frame.midX }

    override func layoutSubviews() {
        super.layoutSubviews()
        block.frame = pixelSnapped(VideoTimelineGeometry.laneRect(
            start: clipStart, duration: clipDuration, compositionDuration: compositionDuration, in: bounds))

        let x = VideoTimelineGeometry.x(forTime: playheadTime, duration: compositionDuration, width: bounds.width)
        let clampedX = min(max(0, x - videoTimelinePlayheadWidth / 2), max(0, bounds.width - videoTimelinePlayheadWidth))
        tick.frame = CGRect(x: pixelSnapped(clampedX), y: 0, width: videoTimelinePlayheadWidth, height: bounds.height)
    }
}

/// The single text-pill lane: one row hosting every text pill's own block,
/// each positioned via its own `laneRect`, since pills (unlike clips) don't
/// each get a dedicated row.
private final class TextPillLaneRow: UIView {

    static let rowHeight: CGFloat = 32

    private(set) var pills: [VideoTimelineModel.TextPill] = []
    private var compositionDuration: Double = 0
    private var playheadTime: Double = 0
    private var blocks: [UUID: UIView] = [:]
    private let tick = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        tick.backgroundColor = Theme.Color.accent
        tick.isUserInteractionEnabled = false
        addSubview(tick)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: Self.rowHeight) }

    func configure(pills: [VideoTimelineModel.TextPill], compositionDuration: Double, playhead: Double) {
        self.pills = pills
        self.compositionDuration = compositionDuration
        playheadTime = playhead

        blocks.values.forEach { $0.removeFromSuperview() }
        blocks = [:]
        for pill in pills {
            let view = UIView()
            view.backgroundColor = Theme.Color.accentStrong
            view.layer.cornerRadius = Theme.Radius.sm
            view.layer.cornerCurve = .continuous
            view.isAccessibilityElement = true
            view.accessibilityLabel = pill.label
            insertSubview(view, belowSubview: tick)
            blocks[pill.id] = view
        }
        setNeedsLayout()
    }

    func setPlayhead(_ time: Double) {
        playheadTime = time
        setNeedsLayout()
    }

    var interactiveBlocks: [(id: UUID, view: UIView)] {
        pills.compactMap { pill in blocks[pill.id].map { (pill.id, $0) } }
    }

    var tickXForTesting: CGFloat { tick.frame.midX }

    override func layoutSubviews() {
        super.layoutSubviews()
        for pill in pills {
            guard let view = blocks[pill.id] else { continue }
            // TextPill is modelled as start/end; laneRect wants start/duration.
            view.frame = pixelSnapped(VideoTimelineGeometry.laneRect(
                start: pill.start, duration: pill.end - pill.start,
                compositionDuration: compositionDuration, in: bounds))
        }
        let x = VideoTimelineGeometry.x(forTime: playheadTime, duration: compositionDuration, width: bounds.width)
        let clampedX = min(max(0, x - videoTimelinePlayheadWidth / 2), max(0, bounds.width - videoTimelinePlayheadWidth))
        tick.frame = CGRect(x: pixelSnapped(clampedX), y: 0, width: videoTimelinePlayheadWidth, height: bounds.height)
    }
}

/// A quiet, display-only row — nothing in the given API reports an edit to the
/// soundtrack, so this never needs to be more than a label.
private final class MusicLaneRow: UIView {

    static let rowHeight: CGFloat = 32

    private let icon = UIImageView(image: UIImage(systemName: "music.note"))
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        icon.tintColor = Theme.Color.textSecondary
        icon.contentMode = .scaleAspectFit

        label.font = Theme.Typography.caption
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
        label.text = title ?? "No music added"
        label.textColor = title == nil ? Theme.Color.textSecondary : Theme.Color.textPrimary
    }
}

/// Five evenly-spaced timestamps (0%, 25%, 50%, 75%, 100% of the composition)
/// rather than a fixed tick interval — robust to any duration without needing
/// to decide a "sensible" seconds-per-tick for a 3-second vs. a 3-minute video.
private final class TimeRulerView: UIView {

    static let rowHeight: CGFloat = 20
    private static let tickCount = 5

    private var duration: Double = 0
    private var labels: [UILabel] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        labels = (0..<Self.tickCount).map { _ in
            let label = UILabel()
            label.font = Theme.Typography.caption
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
