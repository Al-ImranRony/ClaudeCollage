//
//  VideoTimeline.swift
//  Caroullage
//
//  Task 5 — the video editor's collapsible timeline. Two states, remembered per
//  project by whoever owns this view (this file has no notion of "the project"):
//  an 84pt collapsed strip — a filmstrip of the composed collage — and a 210pt
//  expanded view with one lane per cell (each showing its own frames), a
//  caption lane and a music lane drawn as its waveform, all sharing one
//  playhead. The pictures arrive through `setMedia`, produced by the owner's
//  `VideoTimelineMediaLoader`; this view never touches an asset.
//
//  Feel, which is most of what a timeline is: the playhead runs at display
//  rate between the owner's 10 Hz reports (`clockTicked`), a scrub or an edge
//  drag snaps to the meaningful times near it with a haptic tick, an edit that
//  meets a limit says so with a firmer one, and blocks glide to a change that
//  did not come from the finger.
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
        /// Where in its SOURCE the clip's window begins — its trim in-point. What
        /// lets a lane pick the right frames out of a whole-source filmstrip, so
        /// the frames stay put under a trim handle instead of sliding with it.
        public let sourceStart: Double

        public init(index: Int, start: Double, duration: Double, isFilled: Bool, sourceStart: Double = 0) {
            self.index = index
            self.start = start
            self.duration = duration
            self.isFilled = isFilled
            self.sourceStart = sourceStart
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

// MARK: - Shared with the lanes (VideoTimelineLanes.swift)

/// The layout constants and helpers the timeline and its lane views share —
/// a namespace rather than free functions, so splitting the lanes into their
/// own file did not put `pixelSnapped` into the whole module's scope.
enum VideoTimelineLayout {

    /// This codebase's hairline idiom: a flat point constant rather than a
    /// `UIScreen.main.scale`-derived value (`UIScreen.main` is deprecated as of
    /// iOS 26). Matches `EditorToolRail.separatorHeight` / `EditorPanel.separatorHeight`.
    static let hairline: CGFloat = 1
    static let playheadWidth: CGFloat = 2

    /// Rounds a value to the nearest whole point. `VideoTimelineGeometry` returns
    /// fractional points; for the same reason this file doesn't chase an exact
    /// device pixel grid via `UIScreen.main.scale` (deprecated, and wrong on an
    /// external display anyway), block and playhead edges are snapped to whole
    /// points instead — crisper than a fractional edge on any scale, without
    /// depending on which scale it is.
    static func pixelSnapped(_ value: CGFloat) -> CGFloat { value.rounded() }

    static func pixelSnapped(_ rect: CGRect) -> CGRect {
        let minX = pixelSnapped(rect.minX)
        let maxX = pixelSnapped(rect.minX + rect.width)
        return CGRect(x: minX, y: rect.minY, width: max(0, maxX - minX), height: rect.height)
    }

    static func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // Everything below formats through Foundation's `Duration` styles, which
    // localise digits, separators and unit words themselves — the timeline
    // adds no strings of its own to the catalog.

    /// `0:03.2` — the header readout, to the tenth, so the playhead visibly
    /// moves under the finger even on a short clip.
    static func formatPreciseTime(_ seconds: Double) -> String {
        let tenths = (max(0, seconds.isFinite ? seconds : 0) * 10).rounded(.down) / 10
        return Duration.milliseconds(Int64(tenths * 1000))
            .formatted(.time(pattern: .minuteSecond(padMinuteToLength: 1, fractionalSecondsLength: 1)))
    }

    /// `3.2s` — a clip's length on its badge.
    static func formatDuration(_ seconds: Double) -> String {
        Duration.milliseconds(Int64((max(0, seconds) * 1000).rounded()))
            .formatted(.units(allowed: [.seconds], width: .narrow,
                              fractionalPart: .show(length: 1, rounded: .toNearestOrEven)))
    }

    /// A ruler label: `5s` while the whole composition is under a minute, then
    /// `1:30`. Half-second ticks keep their fraction.
    static func formatRulerTime(_ seconds: Double, interval: Double) -> String {
        let value = Duration.milliseconds(Int64((max(0, seconds) * 1000).rounded()))
        if interval < 60, seconds < 60 {
            let fraction = interval < 1 ? 1 : 0
            return value.formatted(.units(allowed: [.seconds], width: .narrow,
                                          fractionalPart: .show(length: fraction)))
        }
        return value.formatted(.time(pattern: .minuteSecond))
    }

    /// "3.2 seconds" — a lane's length as VoiceOver reads it.
    static func spokenDuration(_ seconds: Double) -> String {
        Duration.milliseconds(Int64((max(0, seconds) * 1000).rounded()))
            .formatted(.units(allowed: [.minutes, .seconds], width: .wide,
                              fractionalPart: .show(length: 1, rounded: .toNearestOrEven)))
    }

    /// "0:01.0 – 0:03.5" — a caption's window as VoiceOver reads it.
    static func spokenRange(start: Double, end: Double) -> String {
        "\(formatPreciseTime(start)) – \(formatPreciseTime(end))"
    }
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

    /// The header plus a 40pt strip: a filmstrip of the collage tall enough to
    /// read, with the caption track under it.
    public static let collapsedHeight: CGFloat = 84
    public static let expandedHeight: CGFloat = 210

    /// A full 44pt bar: the play and chevron controls are pinned to its
    /// height, and anything shorter is not a hit target (phase 6.5).
    private static let headerHeight: CGFloat = Theme.Layout.minimumHitTarget
    private static let chevronWidth: CGFloat = Theme.Layout.minimumHitTarget
    private static let playbackButtonWidth: CGFloat = Theme.Layout.minimumHitTarget
    /// The ink disc drawn inside the play control's 44pt target.
    private static let playbackChipSize: CGFloat = 30
    /// Touch slop for grabbing a clip/pill's edge to trim/retime rather than
    /// its middle to select. `Theme.Spacing.sm` rather than a bespoke literal —
    /// and the width of a selected clip's drawn handles, so what you see is
    /// what you can grab. A ceiling, not a fixed value: `edgeTolerance(for:)`
    /// scales it down for a block narrower than `2 * edgeTolerance`, or the two
    /// edge zones would overlap and swallow the whole block.
    private static let edgeTolerance: CGFloat = Theme.Spacing.sm
    /// How close (in points) a drag must come to a meaningful time — a clip's
    /// edge, a caption's, the playhead — before it snaps there.
    private static let snapDistance: CGFloat = 8
    /// A clip/pill can never be trimmed narrower than this, so a fast drag past
    /// the opposite edge can't invert start/end or produce a zero/negative span.
    /// The shortest window any surface will produce, for a clip's trim or a
    /// caption's in/out. `internal` rather than `private` because the Timing
    /// panel clamps to the same value — if the two disagreed, a window typed in
    /// the panel could be one a drag can never reproduce.
    static let minimumTrimDuration: Double = 0.1

    public private(set) var state: State = .collapsed

    private var model = VideoTimelineModel()
    /// The last time the owner reported — the player's truth.
    private var playheadTime: Double = 0
    /// Where the playhead is DRAWN: the report, or where the playback clock
    /// has carried it since. What a model push re-draws the lanes with, so an
    /// edit during playback never pulls the playhead back to the last report.
    private var displayedPlayhead: Double = 0

    private let headerRow = UIView()
    private let timeLabel = UILabel()
    private let chevronButton = UIControl()
    private let chevronImageView = UIImageView()
    private let playbackButton = UIControl()
    private let playbackChip = UIView()
    private let playbackImageView = UIImageView()

    private let contentHost = UIView()
    private let collapsedContent = CollapsedStripView()
    private let expandedContent = ExpandedLanesView()

    private var heightConstraint: NSLayoutConstraint!

    private lazy var tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
    private lazy var panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))

    // Media the owner hands over (see `setMedia`).
    private var clipFilmstrips: [Int: VideoTimelineFilmstrip] = [:]
    private var compositionFrames: [UIImage] = []
    private var musicWaveform: VideoTimelineWaveform?

    // The playback clock: the owner reports the player's time ten times a
    // second, which moved the playhead in visible jumps. Between reports the
    // playhead runs on from the last one at real time, per display frame, and
    // each report quietly corrects it. Only while playing, never mid-drag.
    private var clock: CADisplayLink?
    private var playheadReportedAt: CFTimeInterval = 0
    /// How far the playhead may run on without a fresh report — a stalled
    /// player must not leave it gliding off on its own.
    private static let clockRunOn: CFTimeInterval = 0.5
    private var readout = ""

    // Drag feedback state.
    private var snappedTime: Double?
    private var isAtEditLimit = false

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

    /// The drag in flight, if any — see `setModel` for when a model push ends it.
    private var activeDrag: ActiveDrag? {
        didSet { updateClock() }
    }

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

        updateChevron(animated: false)
        updatePlaybackIcon()
        updateReadouts()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
            (timeline: VideoTimeline, _: UITraitCollection) in
            timeline.readout = ""
            timeline.updateReadouts()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        updateClock()
    }

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
    ///
    /// A change that moves blocks while no drag is running — an undo, a trim
    /// typed into a panel — glides them there; one the finger is making follows
    /// the finger exactly.
    public func setModel(_ newModel: VideoTimelineModel) {
        let previous = model
        model = newModel
        activeDrag = Self.dragSurviving(activeDrag, in: newModel)
        let moved = previous.clips != newModel.clips || previous.textPills != newModel.textPills
            || previous.duration != newModel.duration
        collapsedContent.configure(model: model, playhead: displayedPlayhead)
        if previous.duration != newModel.duration {
            collapsedContent.setCompositionFrames(compositionFrames)
        }
        expandedContent.configure(model: model, playhead: displayedPlayhead,
                                  animated: moved && activeDrag == nil)
        updatePlaybackIcon()
        updateReadouts(at: displayedPlayhead)
        updateClock()
        setNeedsLayout()
    }

    /// The pictures the lanes draw — frames of each clip (by slot), frames of
    /// the composed collage, and the soundtrack's shape. Produced by the owner
    /// (`VideoTimelineMediaLoader`); this view only draws what it is given.
    public func setMedia(clipFilmstrips: [Int: VideoTimelineFilmstrip],
                         compositionFrames: [UIImage],
                         musicWaveform: VideoTimelineWaveform?) {
        if !compositionFrames.isIdentical(to: self.compositionFrames) {
            self.compositionFrames = compositionFrames
            collapsedContent.setCompositionFrames(compositionFrames)
        }
        guard clipFilmstrips != self.clipFilmstrips || musicWaveform != self.musicWaveform else { return }
        self.clipFilmstrips = clipFilmstrips
        self.musicWaveform = musicWaveform
        expandedContent.setMedia(filmstrips: clipFilmstrips, waveform: musicWaveform)
    }

    /// A new report of where the player is. The owner also re-pushes its last
    /// report on every document change; while the clock runs, such a repeat is
    /// not news — restamping it would restart the clock from a time up to a
    /// tenth of a second old and pull the playhead back on every edit.
    public func setPlayhead(_ time: Double) {
        if clock != nil, time == playheadTime { return }
        playheadTime = time
        playheadReportedAt = CACurrentMediaTime()
        showPlayhead(at: time)
    }

    public func setState(_ newState: State, animated: Bool) {
        guard newState != state else { return }
        state = newState
        let incoming: UIView = state == .expanded ? expandedContent : collapsedContent
        let outgoing: UIView = state == .expanded ? collapsedContent : expandedContent
        heightConstraint.constant = state == .collapsed ? Self.collapsedHeight : Self.expandedHeight
        let isAnimated = animated && !Theme.Motion.isReduced
        updateChevron(animated: isAnimated)

        guard isAnimated else {
            incoming.isHidden = false
            incoming.alpha = 1
            outgoing.isHidden = true
            outgoing.alpha = 1
            applyPendingLayout()
            if state == .expanded { expandedContent.revealOverflow() }
            return
        }
        // The two views crossfade while the height moves, instead of one
        // blinking out and the other in at the start of the resize.
        incoming.isHidden = false
        incoming.alpha = 0
        let target = state
        UIView.animate(
            withDuration: Theme.Motion.standard, delay: 0,
            usingSpringWithDamping: 0.92, initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) { [weak self] in
            incoming.alpha = 1
            outgoing.alpha = 0
            self?.applyPendingLayout()
        } completion: { [weak self] _ in
            guard let self, self.state == target else { return }
            outgoing.isHidden = true
            outgoing.alpha = 1
            if target == .expanded { self.expandedContent.revealOverflow() }
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
        // `▶ 0:03.1` header — see the class header's plan-defect note. Drawn as
        // an ink disc — the app's primary-control chrome — inside the full 44pt
        // target, so the one control that starts playback reads as primary.
        playbackChip.backgroundColor = Theme.Color.accentStrong
        playbackChip.layer.cornerRadius = Self.playbackChipSize / 2
        playbackChip.isUserInteractionEnabled = false
        playbackChip.translatesAutoresizingMaskIntoConstraints = false
        playbackButton.addSubview(playbackChip)

        playbackImageView.tintColor = Theme.Color.textOnAccent
        playbackImageView.contentMode = .center
        playbackImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
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
        playbackButton.addTarget(self, action: #selector(playbackPressed), for: [.touchDown, .touchDragEnter])
        playbackButton.addTarget(self, action: #selector(playbackReleased),
                                 for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
        playbackButton.translatesAutoresizingMaskIntoConstraints = false
        playbackButton.showsLargeContentViewer = true
        headerRow.addSubview(playbackButton)

        timeLabel.font = Theme.Typography.monospacedDigits(13, .semibold, .caption1)
        timeLabel.adjustsFontForContentSizeCategory = true
        timeLabel.textColor = Theme.Color.textSecondary
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addSubview(timeLabel)

        chevronImageView.tintColor = Theme.Color.textSecondary
        chevronImageView.contentMode = .center
        chevronImageView.image = UIImage(systemName: "chevron.down")
        chevronImageView.isUserInteractionEnabled = false
        chevronImageView.translatesAutoresizingMaskIntoConstraints = false
        chevronButton.addSubview(chevronImageView)

        chevronButton.accessibilityIdentifier = "videoTimelineChevron"
        // Same trap as `playbackButton` above.
        chevronButton.isAccessibilityElement = true
        chevronButton.accessibilityTraits = .button
        chevronButton.addTarget(self, action: #selector(chevronTapped), for: .touchUpInside)
        chevronButton.translatesAutoresizingMaskIntoConstraints = false
        chevronButton.showsLargeContentViewer = true
        headerRow.addSubview(chevronButton)
        // The header's two glyph controls offer the large content viewer, as
        // the tool rail's do (phase 6.5).
        headerRow.addInteraction(UILargeContentViewerInteraction())

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

            // The glyph and its disc are centred within the button, but the
            // button itself is pinned top/bottom to a non-zero-height ancestor
            // (headerRow) and given an explicit width — its hit-testable bounds
            // never depend on the image view's intrinsic size.
            playbackChip.centerXAnchor.constraint(equalTo: playbackButton.centerXAnchor),
            playbackChip.centerYAnchor.constraint(equalTo: playbackButton.centerYAnchor),
            playbackChip.widthAnchor.constraint(equalToConstant: Self.playbackChipSize),
            playbackChip.heightAnchor.constraint(equalToConstant: Self.playbackChipSize),
            playbackImageView.centerXAnchor.constraint(equalTo: playbackButton.centerXAnchor),
            playbackImageView.topAnchor.constraint(equalTo: playbackButton.topAnchor),
            playbackImageView.bottomAnchor.constraint(equalTo: playbackButton.bottomAnchor),

            playbackButton.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor, constant: Theme.Spacing.xs),
            playbackButton.topAnchor.constraint(equalTo: headerRow.topAnchor),
            playbackButton.bottomAnchor.constraint(equalTo: headerRow.bottomAnchor),
            playbackButton.widthAnchor.constraint(equalToConstant: Self.playbackButtonWidth),

            timeLabel.leadingAnchor.constraint(equalTo: playbackButton.trailingAnchor, constant: Theme.Spacing.xxs),
            timeLabel.centerYAnchor.constraint(equalTo: headerRow.centerYAnchor),
            timeLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevronButton.leadingAnchor,
                                                constant: -Theme.Spacing.xs),

            // Same reasoning as the play control above; see also
            // `EditorToolRail.ToolButton`'s regression note for why a
            // center-only pin on the CONTROL itself is the trap.
            chevronImageView.centerXAnchor.constraint(equalTo: chevronButton.centerXAnchor),
            chevronImageView.topAnchor.constraint(equalTo: chevronButton.topAnchor),
            chevronImageView.bottomAnchor.constraint(equalTo: chevronButton.bottomAnchor),

            chevronButton.trailingAnchor.constraint(equalTo: headerRow.trailingAnchor, constant: -Theme.Spacing.xs),
            chevronButton.topAnchor.constraint(equalTo: headerRow.topAnchor),
            chevronButton.bottomAnchor.constraint(equalTo: headerRow.bottomAnchor),
            chevronButton.widthAnchor.constraint(equalToConstant: Self.chevronWidth),

            // Full width: every x in here is a time, measured against this
            // view's own width (see the class header), so the lanes run edge to
            // edge rather than inside a margin the geometry knows nothing of.
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

    /// One glyph, turned: the chevron points down to open and rotates to point
    /// up once open, rather than swapping symbols mid-resize.
    private func updateChevron(animated: Bool) {
        let expanded = state == .expanded
        let rotation = expanded ? CGAffineTransform(rotationAngle: .pi * 0.999) : .identity
        if animated {
            UIView.animate(withDuration: Theme.Motion.standard, delay: 0,
                           usingSpringWithDamping: 0.85, initialSpringVelocity: 0,
                           options: [.beginFromCurrentState]) {
                self.chevronImageView.transform = rotation
            }
        } else {
            chevronImageView.transform = rotation
        }
        chevronButton.accessibilityLabel = expanded
            ? String(localized: "Collapse timeline") : String(localized: "Expand timeline")
        chevronButton.largeContentTitle = chevronButton.accessibilityLabel
        chevronButton.largeContentImage = UIImage(systemName: expanded ? "chevron.up" : "chevron.down")
    }

    /// Only ever reports the tap — like `chevronTapped` above, this view never
    /// applies the toggle itself. The owner flips its player and calls back
    /// into `setModel` with the resulting `isPlaying`, which is what
    /// `updatePlaybackIcon` actually renders.
    @objc private func playbackTapped() {
        Haptics.tap()
        onTogglePlayback?()
    }

    @objc private func playbackPressed() { playbackChip.setPressed(true, scale: 0.88) }
    @objc private func playbackReleased() { playbackChip.setPressed(false, scale: 0.88) }

    private func updatePlaybackIcon() {
        let symbol = model.isPlaying ? "pause.fill" : "play.fill"
        let label = model.isPlaying ? String(localized: "Pause") : String(localized: "Play")
        guard playbackButton.accessibilityLabel != label || playbackImageView.image == nil,
              let image = UIImage(systemName: symbol) else { return }
        if window != nil, playbackImageView.image != nil, !Theme.Motion.isReduced {
            playbackImageView.setSymbolImage(image, contentTransition: .replace.downUp)
        } else {
            playbackImageView.image = image
        }
        playbackButton.accessibilityLabel = label
        playbackButton.largeContentTitle = label
        playbackButton.largeContentImage = image
    }

    /// `0:03.2 / 0:08.0`: where the playhead is, in ink (accent while the
    /// finger holds it), against the whole length, quieter. Rebuilt only when
    /// the tenth changes — the clock calls this every display frame.
    private func updateReadouts(at time: Double? = nil) {
        let isScrubbing: Bool
        if case .scrub = activeDrag { isScrubbing = true } else { isScrubbing = false }
        let current = VideoTimelineLayout.formatPreciseTime(time ?? playheadTime)
        let total = VideoTimelineLayout.formatPreciseTime(model.duration)
        let key = "\(current)|\(total)|\(isScrubbing)"
        guard key != readout else { return }
        readout = key
        let font = timeLabel.font ?? Theme.Typography.monospacedDigits(13, .semibold, .caption1)
        let text = NSMutableAttributedString(string: current, attributes: [
            .font: font,
            .foregroundColor: isScrubbing ? Theme.Color.accent : Theme.Color.textPrimary,
        ])
        text.append(NSAttributedString(string: " / \(total)", attributes: [
            .font: font, .foregroundColor: Theme.Color.textSecondary,
        ]))
        timeLabel.attributedText = text
        timeLabel.accessibilityLabel = "\(current) / \(total)"
    }

    // MARK: - Playback clock

    private func showPlayhead(at time: Double) {
        displayedPlayhead = time
        collapsedContent.setPlayhead(time)
        expandedContent.setPlayhead(time)
        updateReadouts(at: time)
    }

    private func updateClock() {
        let runs = model.isPlaying && window != nil && activeDrag == nil
        if runs, clock == nil {
            // Runs on from where the playhead is NOW — not from when the last
            // report arrived, which may have been long before play was pressed
            // (or before a drag paused the clock).
            playheadTime = displayedPlayhead
            playheadReportedAt = CACurrentMediaTime()
            let link = CADisplayLink(target: TimelineClockTarget(self),
                                     selector: #selector(TimelineClockTarget.tick(_:)))
            link.add(to: .main, forMode: .common)
            clock = link
        } else if !runs, let link = clock {
            link.invalidate()
            clock = nil
        }
    }

    fileprivate func clockTicked() {
        guard model.isPlaying, activeDrag == nil else { return }
        let elapsed = min(CACurrentMediaTime() - playheadReportedAt, Self.clockRunOn)
        showPlayhead(at: min(playheadTime + elapsed, model.duration))
    }

    // MARK: - Gestures

    private func timeForX(_ x: CGFloat) -> Double {
        VideoTimelineGeometry.time(forX: x, duration: model.duration, width: bounds.width)
    }

    private func xForTime(_ time: Double) -> CGFloat {
        VideoTimelineGeometry.x(forTime: time, duration: model.duration, width: bounds.width)
    }

    private func clamped(_ value: Double, _ lowerBound: Double, _ upperBound: Double) -> Double {
        guard lowerBound <= upperBound else { return lowerBound }
        return min(max(value, lowerBound), upperBound)
    }

    /// Pulls `time` onto the nearest of `targets` within `snapDistance` points,
    /// with a light tick the moment it takes hold — the feel of a magnet, so a
    /// caption can be lined up with a cut or the playhead without squinting.
    private func snapped(_ time: Double, to targets: [Double]) -> Double {
        let x = xForTime(time)
        let nearest = targets.min { abs(xForTime($0) - x) < abs(xForTime($1) - x) }
        guard let nearest, abs(xForTime(nearest) - x) <= Self.snapDistance else {
            snappedTime = nil
            return time
        }
        if snappedTime != nearest { Haptics.selectionChanged() }
        snappedTime = nearest
        return nearest
    }

    /// What a scrub snaps to: the ends, and every clip's and caption's edges.
    private var scrubSnapTargets: [Double] {
        var targets = [0, model.duration]
        for clip in model.clips where clip.isFilled { targets += [clip.start, clip.start + clip.duration] }
        for pill in model.textPills { targets += [pill.start, pill.end] }
        return targets
    }

    /// What a dragged edge snaps to: the playhead ("trim to here"), and — for a
    /// caption — the cuts, so it can start and end with a clip.
    private func editSnapTargets(includingClipEdges: Bool) -> [Double] {
        var targets = [playheadTime]
        if includingClipEdges {
            for clip in model.clips where clip.isFilled { targets += [clip.start, clip.start + clip.duration] }
        }
        return targets
    }

    /// Clamps an edited edge, with a firmer tick when it first meets a limit —
    /// the shortest a window may be, the start or the end of the composition.
    private func limited(_ value: Double, _ lowerBound: Double, _ upperBound: Double) -> Double {
        let result = clamped(value, lowerBound, upperBound)
        let atLimit = result != value
        if atLimit, !isAtEditLimit { Haptics.boundary() }
        isAtEditLimit = atLimit
        return result
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

    /// A tapped block dips and springs back — the selection is felt where the
    /// finger is, not only in the rail.
    private func pop(_ view: UIView?) {
        guard let view, window != nil, !Theme.Motion.isReduced else { return }
        view.transform = CGAffineTransform(scaleX: 0.95, y: 0.9)
        UIView.animate(withDuration: Theme.Motion.standard, delay: 0,
                       usingSpringWithDamping: Theme.Motion.springDamping,
                       initialSpringVelocity: Theme.Motion.springVelocity,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            view.transform = .identity
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        performTap(at: gesture.location(in: self))
    }

    private func performTap(at point: CGPoint) {
        switch hitTarget(at: point) {
        case .clipMiddle(let index):
            Haptics.selectionChanged()
            pop(expandedContent.clipBlockViews.first { $0.index == index }?.view)
            onSelectClip?(index)
        case .textMiddle(let id):
            Haptics.selectionChanged()
            pop(expandedContent.textPillBlockViews.first { $0.id == id }?.view)
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
        snappedTime = nil
        isAtEditLimit = false
        switch hitTarget(at: point) {
        case .clipEdge(let index, let edge):
            guard let clip = model.clips.first(where: { $0.index == index }) else {
                activeDrag = nil
                return
            }
            activeDrag = .trimClip(index: index, edge: edge, start: clip.start, duration: clip.duration)
            Haptics.softTap()
        case .textEdge(let id, let edge):
            guard let pill = model.textPills.first(where: { $0.id == id }) else {
                activeDrag = nil
                return
            }
            activeDrag = .retimeText(id: id, edge: edge, start: pill.start, end: pill.end)
            Haptics.softTap()
        case .background, .clipMiddle, .textMiddle:
            // Dragging anywhere that isn't an edge handle scrubs, including
            // over a clip's middle — only a plain tap there selects.
            activeDrag = .scrub
            collapsedContent.setScrubbing(true)
            expandedContent.setScrubbing(true)
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
            let target = snapped(time, to: scrubSnapTargets)
            setPlayhead(target)
            onScrub?(target)

        case .trimClip(let index, let edge, let start, let duration):
            let end = start + duration
            let targets = editSnapTargets(includingClipEdges: false)
            switch edge {
            case .leading:
                let newStart = limited(snapped(time, to: targets), 0, end - Self.minimumTrimDuration)
                onTrim?(index, newStart, end, phase)
            case .trailing:
                let newEnd = limited(snapped(time, to: targets), start + Self.minimumTrimDuration, model.duration)
                onTrim?(index, start, newEnd, phase)
            }

        case .retimeText(let id, let edge, let start, let end):
            let targets = editSnapTargets(includingClipEdges: true)
            switch edge {
            case .leading:
                let newStart = limited(snapped(time, to: targets), 0, end - Self.minimumTrimDuration)
                onRetimeText?(id, newStart, end, phase)
            case .trailing:
                let newEnd = limited(snapped(time, to: targets), start + Self.minimumTrimDuration, model.duration)
                onRetimeText?(id, start, newEnd, phase)
            }
        }
    }

    private func performPanEnd(at point: CGPoint, phase: EditPhase) {
        performPanContinue(at: point, phase: phase)
        if case .scrub = activeDrag {
            collapsedContent.setScrubbing(false)
            expandedContent.setScrubbing(false)
        }
        activeDrag = nil
        snappedTime = nil
        isAtEditLimit = false
        updateReadouts(at: displayedPlayhead)
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

    /// The header's two glyph controls, for the large-content-viewer test.
    var headerControlsForTesting: (playback: UIControl, chevron: UIControl) { (playbackButton, chevronButton) }

    /// The playhead's time in seconds, as last REPORTED by the owner — as
    /// opposed to `playheadXForTesting`'s rendered position, which the
    /// playback clock may have carried a little further.
    var playheadTimeForTesting: Double { playheadTime }

    /// The header's readout, as displayed.
    var readoutForTesting: String? { timeLabel.attributedText?.string }

    /// Whether the playback clock is running (it should only while playing).
    var isClockRunningForTesting: Bool { clock != nil }

    /// Drives one playback-clock frame now, as if `seconds` had passed since
    /// the owner's last report.
    func simulateClockTickForTesting(secondsSinceReport seconds: Double) {
        playheadReportedAt = CACurrentMediaTime() - seconds
        clockTicked()
    }

    /// Makes the last report `seconds` older than it is.
    func backdateLastReportForTesting(by seconds: Double) { playheadReportedAt -= seconds }

    /// One playback-clock frame, against the clock's own timestamps.
    func tickClockForTesting() { clockTicked() }

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
    /// palette split (selected renders `Theme.Color.accent`) without reaching
    /// past the public model into private view internals.
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

/// `CADisplayLink` retains its target; this keeps the timeline's clock from
/// keeping the timeline alive.
private final class TimelineClockTarget: NSObject {
    private weak var timeline: VideoTimeline?
    init(_ timeline: VideoTimeline) {
        self.timeline = timeline
        super.init()
    }
    /// A link whose timeline is gone stops itself rather than ticking forever.
    @MainActor @objc func tick(_ link: CADisplayLink) {
        guard let timeline else { return link.invalidate() }
        timeline.clockTicked()
    }
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
