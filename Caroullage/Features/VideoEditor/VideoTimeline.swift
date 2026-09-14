//
//  VideoTimeline.swift
//  Caroullage
//
//  Task 5 — the video editor's collapsible timeline. Two states, remembered per
//  project by whoever owns this view (this file has no notion of "the project"):
//  a 76pt collapsed strip that summarises the whole composition, and a 210pt
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
//  Palette: the playhead and a selected clip/pill are state (`Theme.Color.accent`,
//  indigo) — "what position is current" and "what is selected", respectively.
//  Everything else — unselected clip fills, unselected text-pill chips, the
//  ruler — stays chrome (ink). `VideoTimelineModel.selectedClipIndex` /
//  `selectedTextID` are what let indigo mark a choice at all.
//
//  Plan-defect fix: the approved design shows a play control with a time
//  readout (`▶ 0:03.1`) in the collapsed strip's header, but the original API
//  this file shipped against had no callback for it and no `isPlaying` field
//  on the model to render its icon from — the exact "control with nowhere to
//  report through" trap this codebase's other fixes call out, so it was left
//  unbuilt rather than shipped inert. Both gaps are now closed:
//  `VideoTimelineModel.isPlaying` drives the icon and `onTogglePlayback`
//  reports a tap, exactly like every other control here — this view still
//  never decides whether playback starts or stops, it only asks. The button
//  sits in the header, left of the time readout, matching the design; it
//  keeps the pre-existing `videoPlayButton` accessibility identifier so the
//  UI suite that already knew that name keeps finding it.
//
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
    /// The clip currently shown selected (Task 6's "Clip selected" contextual
    /// rail group). `nil` means nothing is selected.
    public var selectedClipIndex: Int?
    /// The text pill currently shown selected (Task 6's "Text selected" group).
    public var selectedTextID: UUID?
    /// Whether the composition is currently playing. The owner (the screen that
    /// actually holds the `AVPlayer`) is the single source of truth for this —
    /// this view only ever reads it, to choose the collapsed strip's play/pause
    /// icon; see `VideoTimeline.onTogglePlayback`.
    public var isPlaying: Bool

    public init(
        duration: Double = 0,
        clips: [Clip] = [],
        textPills: [TextPill] = [],
        musicTitle: String? = nil,
        selectedClipIndex: Int? = nil,
        selectedTextID: UUID? = nil,
        isPlaying: Bool = false
    ) {
        self.duration = duration
        self.clips = clips
        self.textPills = textPills
        self.musicTitle = musicTitle
        self.selectedClipIndex = selectedClipIndex
        self.selectedTextID = selectedTextID
        self.isPlaying = isPlaying
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

    /// Distinguishes a still-in-progress edit from its commit, so a caller
    /// driving undo (this codebase's `updateXInteractive` + `commitInteractive`
    /// pattern — see `VideoEditorViewModel`) can coalesce an entire drag into
    /// one undo step instead of recording one per `.changed` tick.
    public enum EditPhase: Equatable, Sendable {
        /// Fired on `.began`/`.changed`, and once more on a `.cancelled`/`.failed`
        /// gesture (see `performPanEnd`) — never treat this as a final value.
        case changed
        /// Fired exactly once, on a `.ended` gesture. Never fired for a
        /// `.cancelled` or `.failed` one.
        case committed
    }

    public var onScrub: ((Double) -> Void)?
    public var onToggleState: ((State) -> Void)?
    /// Fired when the header's play/pause control is tapped. This view never
    /// decides whether that means "start" or "stop" — it just reports the tap,
    /// exactly like `onToggleState` reports a chevron tap without applying it;
    /// the owner flips its player and calls `setModel` with the new `isPlaying`.
    public var onTogglePlayback: (() -> Void)?
    public var onSelectClip: ((Int) -> Void)?
    public var onSelectText: ((UUID) -> Void)?
    public var onTrim: ((_ clipIndex: Int, _ start: Double, _ end: Double, _ phase: EditPhase) -> Void)?
    public var onRetimeText: ((_ id: UUID, _ start: Double, _ end: Double, _ phase: EditPhase) -> Void)?

    public static let collapsedHeight: CGFloat = 76
    public static let expandedHeight: CGFloat = 210

    /// A full 44pt bar, not the 24pt strip it was: the play and chevron controls
    /// are pinned to its height, and 24 is not a hit target (phase 6.5). Both
    /// heights above grew by the same 20pt.
    private static let headerHeight: CGFloat = Theme.Layout.minimumHitTarget
    private static let chevronWidth: CGFloat = Theme.Layout.minimumHitTarget
    private static let playbackButtonWidth: CGFloat = Theme.Layout.minimumHitTarget
    /// Touch slop for grabbing a clip/pill's edge to trim/retime rather than
    /// its middle to select. `Theme.Spacing.sm` rather than a bespoke literal.
    /// This is a ceiling, not a fixed value — `edgeTolerance(for:)` scales it
    /// down for a block narrower than `2 * edgeTolerance`, or the two edge
    /// zones would overlap and swallow the whole block.
    private static let edgeTolerance: CGFloat = Theme.Spacing.sm
    /// A clip/pill can never be trimmed narrower than this, so a fast drag past
    /// the opposite edge can't invert start/end or produce a zero/negative span.
    /// The shortest window any surface will produce, for a clip's trim or a
    /// caption's in/out. `internal` rather than `private` because the Timing
    /// panel clamps to the same value — if the two disagreed, a window typed in
    /// the panel could be one a drag can never reproduce.
    static let minimumTrimDuration: Double = 0.1

    public private(set) var state: State = .collapsed

    private var model = VideoTimelineModel()
    private var playheadTime: Double = 0

    private let headerRow = UIView()
    private let timeLabel = UILabel()
    private let chevronButton = UIControl()
    private let chevronImageView = UIImageView()
    private let playbackButton = UIControl()
    private let playbackImageView = UIImageView()

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

    /// Whether `drag` still points at something the new model has. A trim needs a
    /// lane that is still FILLED — an emptied slot keeps its lane (it is still a
    /// slot you can fill) but has no trim left to drag.
    private static func dragSurviving(
        _ drag: ActiveDrag?, in newModel: VideoTimelineModel
    ) -> ActiveDrag? {
        switch drag {
        case .none:
            return nil
        case .scrub:
            // Scrubbing references no clip or caption, so nothing can invalidate it.
            return drag
        case .trimClip(let index, _, _, _):
            return newModel.clips.contains { $0.index == index && $0.isFilled } ? drag : nil
        case .retimeText(let id, _, _, _):
            return newModel.textPills.contains { $0.id == id } ? drag : nil
        }
    }

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
        updatePlaybackIcon()
        updateReadouts()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Public API

    /// Replaces the model. An in-flight drag SURVIVES this unless the thing it is
    /// holding has gone.
    ///
    /// The distinction is load-bearing, and getting it wrong broke trimming
    /// outright. This view renders a drag through its model — it never moves a
    /// block itself — so the owner is *required* to feed each `onTrim` /
    /// `onRetimeText` tick straight back here for the block to follow the finger.
    /// Cancelling on every replacement therefore cancelled every drag on its own
    /// first tick, and the `.committed` phase that ends it never arrived, so the
    /// owner's edit was left uncommitted with no undo step.
    ///
    /// What the cancellation is actually FOR is a change that arrives from
    /// somewhere else and invalidates what the drag captured at touch-down — the
    /// clip deleted, the caption removed. That is an identity question, so it is
    /// checked by identity. Deliberately NOT by geometry: a drag changes its own
    /// target's duration on every tick, so validating that would cancel the drag
    /// it is supposed to protect.
    public func setModel(_ newModel: VideoTimelineModel) {
        model = newModel
        activeDrag = Self.dragSurviving(activeDrag, in: newModel)
        collapsedContent.configure(model: model, playhead: playheadTime)
        expandedContent.configure(model: model, playhead: playheadTime)
        updatePlaybackIcon()
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

        // Left of the time readout, matching the approved design's
        // `▶ 0:03.1` header — see the class header's plan-defect note.
        playbackImageView.tintColor = Theme.Color.textSecondary
        playbackImageView.contentMode = .center
        playbackImageView.isUserInteractionEnabled = false
        playbackImageView.translatesAutoresizingMaskIntoConstraints = false
        playbackButton.addSubview(playbackImageView)

        // The pre-existing identifier from the old transport play button —
        // restoring it keeps the control discoverable to the UI suite without
        // that suite having to learn a new name.
        playbackButton.accessibilityIdentifier = "videoPlayButton"
        // A bare `UIControl` is not an accessibility element and carries no
        // `.button` trait, so VoiceOver announced this — the only way to pause
        // the preview — as an unlabelled container rather than something you can
        // press. Caught by a UI test asserting `app.buttons[…]`, which matched
        // nothing because the element was typed `Other`. Being an element also
        // collapses the inner image view, which was leaking its own SF Symbol
        // name ("go down") into the tree.
        playbackButton.isAccessibilityElement = true
        playbackButton.accessibilityTraits = .button
        playbackButton.addTarget(self, action: #selector(playbackTapped), for: .touchUpInside)
        playbackButton.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addSubview(playbackButton)

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
        // Same trap as `playbackButton` above.
        chevronButton.isAccessibilityElement = true
        chevronButton.accessibilityTraits = .button
        chevronButton.addTarget(self, action: #selector(chevronTapped), for: .touchUpInside)
        chevronButton.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addSubview(chevronButton)

        // On the container itself so a UI test can measure the real laid-out
        // height. Plan 1 shipped a zero-height tool rail that every unit test
        // passed; only a real render catches that class of bug.
        accessibilityIdentifier = "videoTimeline"

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

            // Same reasoning as the chevron button below: the image is centred
            // within the button, but the button itself is pinned top/bottom to
            // a non-zero-height ancestor (headerRow) and given an explicit
            // width — its hit-testable bounds never depend on the image
            // view's intrinsic size.
            playbackImageView.centerXAnchor.constraint(equalTo: playbackButton.centerXAnchor),
            playbackImageView.topAnchor.constraint(equalTo: playbackButton.topAnchor),
            playbackImageView.bottomAnchor.constraint(equalTo: playbackButton.bottomAnchor),

            playbackButton.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor, constant: Theme.Spacing.xs),
            playbackButton.topAnchor.constraint(equalTo: headerRow.topAnchor),
            playbackButton.bottomAnchor.constraint(equalTo: headerRow.bottomAnchor),
            playbackButton.widthAnchor.constraint(equalToConstant: Self.playbackButtonWidth),

            timeLabel.leadingAnchor.constraint(equalTo: playbackButton.trailingAnchor, constant: Theme.Spacing.xs),
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

    /// Only ever reports the tap — like `chevronTapped` above, this view never
    /// applies the toggle itself. The owner flips its player and calls back
    /// into `setModel` with the resulting `isPlaying`, which is what
    /// `updatePlaybackIcon` actually renders.
    @objc private func playbackTapped() {
        Haptics.tap()
        onTogglePlayback?()
    }

    private func updatePlaybackIcon() {
        let symbol = model.isPlaying ? "pause.fill" : "play.fill"
        playbackImageView.image = UIImage(systemName: symbol)
        playbackButton.accessibilityLabel = model.isPlaying ? "Pause" : "Play"
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

    /// The edge tolerance to use for a block `width` points wide: `edgeTolerance`
    /// as a ceiling, scaled down to a third of the width for anything narrower
    /// than `2 * edgeTolerance` (a quick-cut clip well under two seconds on a
    /// typical composition). Without the scale-down, a narrow block's two edge
    /// zones would overlap and cover the entire block, leaving no way to select
    /// its middle — and, resolved leading-first, no way to reach the trailing
    /// edge at all.
    private func edgeTolerance(for width: CGFloat) -> CGFloat {
        min(Self.edgeTolerance, width / 3)
    }

    /// Only meaningful while expanded — the collapsed strip has no per-clip or
    /// per-pill targets, only a scrub track (see the class header).
    ///
    /// Resolves to whichever edge `point` is nearer, not "leading wins": a
    /// block narrower than `2 * edgeTolerance` used to resolve entirely to its
    /// leading edge, making the trailing edge of any short clip untrimmable.
    /// A point exactly equidistant from both (only possible once the block is
    /// narrower than `2 * edgeTolerance(for:)`) resolves to leading, matching
    /// the old tie-break for a case that was already a hairline judgement call.
    private func hitTarget(at point: CGPoint) -> DragTarget {
        guard state == .expanded else { return .background }

        for (index, view) in expandedContent.clipBlockViews {
            let frame = view.convert(view.bounds, to: self)
            guard frame.contains(point) else { continue }
            let tolerance = edgeTolerance(for: frame.width)
            let toLeading = point.x - frame.minX
            let toTrailing = frame.maxX - point.x
            if toLeading <= tolerance, toLeading <= toTrailing { return .clipEdge(index, .leading) }
            if toTrailing <= tolerance { return .clipEdge(index, .trailing) }
            return .clipMiddle(index)
        }
        for (id, view) in expandedContent.textPillBlockViews {
            let frame = view.convert(view.bounds, to: self)
            guard frame.contains(point) else { continue }
            let tolerance = edgeTolerance(for: frame.width)
            let toLeading = point.x - frame.minX
            let toTrailing = frame.maxX - point.x
            if toLeading <= tolerance, toLeading <= toTrailing { return .textEdge(id, .leading) }
            if toTrailing <= tolerance { return .textEdge(id, .trailing) }
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
            performPanContinue(at: point, phase: .changed)
        case .ended:
            performPanEnd(at: point, phase: .committed)
        case .cancelled, .failed:
            // A gesture the system interrupted (an incoming call, a modal
            // taking over touches) must not be reported as committed — that
            // would bake in whatever point the touch happened to be at when
            // it was yanked away, as a real, undo-worthy edit. Report the
            // final position as one more `.changed` instead, exactly like any
            // other in-progress tick, and simply never fire `.committed`.
            performPanEnd(at: point, phase: .changed)
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
        performPanContinue(at: point, phase: .changed)
    }

    private func performPanContinue(at point: CGPoint, phase: EditPhase) {
        guard let drag = activeDrag else { return }
        let time = timeForX(point.x)

        switch drag {
        case .scrub:
            // Scrubbing has no undo step to coalesce, so `onScrub` carries no
            // phase — every tick (including the final one) reports the same way.
            setPlayhead(time)
            onScrub?(time)

        case .trimClip(let index, let edge, let start, let duration):
            let end = start + duration
            switch edge {
            case .leading:
                let newStart = clamped(time, 0, end - Self.minimumTrimDuration)
                onTrim?(index, newStart, end, phase)
            case .trailing:
                let newEnd = clamped(time, start + Self.minimumTrimDuration, model.duration)
                onTrim?(index, start, newEnd, phase)
            }

        case .retimeText(let id, let edge, let start, let end):
            switch edge {
            case .leading:
                let newStart = clamped(time, 0, end - Self.minimumTrimDuration)
                onRetimeText?(id, newStart, end, phase)
            case .trailing:
                let newEnd = clamped(time, start + Self.minimumTrimDuration, model.duration)
                onRetimeText?(id, start, newEnd, phase)
            }
        }
    }

    private func performPanEnd(at point: CGPoint, phase: EditPhase) {
        performPanContinue(at: point, phase: phase)
        activeDrag = nil
    }

    // MARK: - Test seams

    /// The chevron itself. Exposed only so tests can inspect real geometry and
    /// hit-testing; production code has no need to reach past `onToggleState`.
    /// Mirrors `EditorPanel.closeButtonForHitTesting`.
    var chevronButtonForHitTesting: UIControl { chevronButton }

    func simulateChevronTap() { chevronButton.sendActions(for: .touchUpInside) }

    /// The play/pause control itself. Exposed only so tests can inspect real
    /// geometry and hit-testing, and read the icon's current accessibility
    /// label — production code has no need to reach past `onTogglePlayback`.
    /// Mirrors `chevronButtonForHitTesting` above.
    var playbackButtonForHitTesting: UIControl { playbackButton }

    func simulatePlaybackTap() { playbackButton.sendActions(for: .touchUpInside) }

    var heightForTesting: CGFloat { heightConstraint.constant }

    /// The model this timeline was last given — so a test can assert what the
    /// OWNER built and handed over, not just what happened to render.
    var modelForTesting: VideoTimelineModel { model }

    /// The playhead's time in seconds, as opposed to `playheadXForTesting`'s
    /// rendered position.
    var playheadTimeForTesting: Double { playheadTime }

    var expandedClipLaneCount: Int { expandedContent.clipBlockViews.count }
    var expandedTextPillCount: Int { expandedContent.textPillBlockViews.count }

    /// What the music lane is currently saying — it is always present, and says
    /// so either way, so "is there a lane" is not the interesting question.
    var musicLaneTextForTesting: String? { expandedContent.musicLaneTextForTesting }
    var musicLaneIsLaidOutForTesting: Bool { expandedContent.musicLaneIsLaidOutForTesting }

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

    /// A clip block's rendered fill, for asserting the selected/unselected
    /// palette split (selected renders `Theme.Color.accent`; see `hitTarget`'s
    /// callers in `ExpandedLanesView`/`ClipRowView`) without reaching past the
    /// public model into private view internals.
    func colorForClip(at index: Int) -> UIColor? {
        expandedContent.clipBlockViews.first(where: { $0.index == index })?.view.backgroundColor
    }

    func colorForTextPill(id: UUID) -> UIColor? {
        expandedContent.textPillBlockViews.first(where: { $0.id == id })?.view.backgroundColor
    }

    /// Drives the same path a real tap does, without needing a live touch.
    /// Mirrors `EditorToolRail.simulateTap` / `EditorPanel.simulateClose`.
    func simulateTap(at point: CGPoint) { performTap(at: point) }

    func simulatePanBegan(at point: CGPoint) { performPanBegan(at: point) }
    func simulatePanChanged(at point: CGPoint) { performPanContinue(at: point, phase: .changed) }
    func simulatePanEnded(at point: CGPoint) { performPanEnd(at: point, phase: .committed) }
    /// Mirrors what `handlePan` does for a `.cancelled`/`.failed` gesture: end
    /// the drag, but only ever report `.changed`, never `.committed`.
    func simulatePanCancelled(at point: CGPoint) { performPanEnd(at: point, phase: .changed) }
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
private final class ExpandedLanesView: UIView {

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
private final class ClipRowView: UIView {

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
        block.accessibilityLabel = clip.isFilled ? "Clip \(clip.index + 1)" : "Clip \(clip.index + 1), empty"

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
private final class TextPillLaneRow: UIView {

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

    var labelTextForTesting: String? { label.text }
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
