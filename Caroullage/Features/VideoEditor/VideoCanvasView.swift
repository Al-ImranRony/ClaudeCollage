//
//  VideoCanvasView.swift
//  Caroullage
//
//  Step 04 slice 5b — the video editor's canvas.
//
//  Its backing layer IS an `AVPlayerLayer` (the plan's requirement), so the composed
//  collage plays in real time with zero extra compositing on the UI thread: the
//  player item already carries the `AVVideoComposition` (per-cell layout, transforms
//  and transition ramps) and the `AVAudioMix` (per-cell volume + music), so what you
//  see and hear here is exactly what the exporter writes.
//
//  Hosting an AVPlayerLayer inside SwiftUI needs a UIViewRepresentable bridge that
//  gets messy around player lifecycle and KVO — UIKit owns it cleanly, which is why
//  this screen is UIKit while the control sheets are SwiftUI.
//
//  Two things layer ABOVE the player:
//  • `textViews` / `stickerViews` — the same pooled, interactive overlay views the
//    photo collage editor uses (`TextOverlayView` / `StickerOverlayView`), which
//    already draw through the shared `TextRendering`/`StickerRendering` helpers, so
//    a caption or sticker looks identical whether the project is a photo or video
//    collage. There is deliberately no second, baked-image copy of this layer: an
//    earlier slice tried compositing `bundle.overlayImage` into its own image view
//    here too, but that view sat hidden underneath these live ones (and, once a
//    text overlay carries timing, `overlayImage` is nil) — see `setPreviewTime`
//    below for how the live views themselves follow playback time instead.
//    `bundle.overlayImage` / `timedOverlays` still exist for the EXPORT, which
//    draws into a `CVPixelBuffer` where UIKit views can't run.
//  • `cellViews` — selection chrome + "tap to add" placeholders for empty slots.
//
//  All three live inside `stripView`, which is the layout's own space: the
//  canvas itself, or — when the collage pans (`CanvasPan`) — the whole strip,
//  translated by the camera offset at the preview time. So a caption dragged on
//  a panning collage is normalized against the strip and rides along with its
//  panel, exactly as the export draws it, and a tap hit-tests through the offset.
//
//  Captions are animated (`TextAnimationMath`) from the same preview time while
//  the player runs (`animatesCaptions`). A display link drives that time — the
//  VC's 10 Hz observer is fine for in/out points, too coarse for motion.
//
//  And one thing sits BETWEEN the player and `stripView`: `VideoFreezeFrameView`,
//  which holds the last frame while the player swaps items (the swap would
//  otherwise blank the video) and carries a layout change as a glide from the
//  old slots to the new ones. Overlays are pooled by identity, so an edit that
//  arrives from anywhere but the finger — undo, a new sticker, a deletion —
//  animates to its new state instead of popping.
//

import AVFoundation
import UIKit

final class VideoCanvasView: UIView {

    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        // Safe: `layerClass` above guarantees the backing layer's type.
        guard let layer = layer as? AVPlayerLayer else {
            fatalError("VideoCanvasView backing layer must be AVPlayerLayer")
        }
        return layer
    }

    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    /// One chrome view per layout slot (placeholder + selection outline).
    private var cellViews: [VideoCellChromeView] = []

    /// VoiceOver/Switch Control activated a slot — the same thing a tap on it
    /// means. Wired by the view controller (phase 6.5).
    var onCellActivated: ((Int) -> Void)?

    private var canvasSize: CGSize = CGSize(width: 1, height: 1)
    /// The space `cellFrames` and the overlays are laid out in — `canvasSize`, or
    /// the whole strip for a panning collage.
    private var layoutSize: CGSize = CGSize(width: 1, height: 1)
    private var pan: CanvasPan?
    private var cellFrames: [CGRect] = []
    /// Hosts the cell chrome and overlays in layout space; offset by the camera.
    private let stripView = UIView()
    /// How long the composition runs — what the camera's progress is measured
    /// against. Pushed by the VC whenever the composition is rebuilt.
    var compositionDuration: Double = 0 {
        didSet { if compositionDuration != oldValue { refreshTimedState() } }
    }
    /// Whether captions play their animation. The VC turns it on only while
    /// the player runs: a paused preview shows every caption on screen in its
    /// finished state, so a freshly opened template — paused at 0:00, where a
    /// fade or a word reveal has not begun — never looks captionless, and the
    /// caption being edited is never mid-reveal. Scrubbing still shows WHICH
    /// captions are on screen at each moment; only the motion waits for Play.
    var animatesCaptions = false {
        didSet { if animatesCaptions != oldValue { refreshTimedState() } }
    }
    private var displayLink: CADisplayLink?
    /// Which slots held a clip at the last `configure` — a layout morph carries
    /// only those, since an empty slot has no video to move.
    private var slotFilled: [Bool] = []
    /// Created on first use, so a canvas that never swaps items never has one.
    private var freezeFrameStorage: VideoFreezeFrameView?

    // Interactive text/sticker overlay views (reused from the grid editor), layered
    // above the player — the only overlay rendering path in the preview; see the
    // header comment for why there's no separate baked-image layer.
    private var textViews: [TextOverlayView] = []
    private var stickerViews: [StickerOverlayView] = []
    private var textModels: [TextOverlay] = []
    private var stickerModels: [StickerOverlay] = []

    /// The composition time the preview is showing, in seconds — pushed by the VC's
    /// player time observer. Drives which timed text overlays are on screen so the
    /// canvas matches what the export will write for that same instant. Same
    /// half-open `[start, end)` contract as `TextOverlay.isVisible(at:)`, compared
    /// with no tolerance: the caller must feed the same `CMTime.seconds` conversion
    /// the export uses, or an in/out point landing exactly on a frame boundary could
    /// disagree between the two.
    private var previewTime: Double = 0

    var onTextChanged: ((TextOverlay) -> Void)?
    var onTextCommitted: (() -> Void)?
    var onTextTapped: ((UUID) -> Void)?
    var onStickerChanged: ((StickerOverlay) -> Void)?
    var onStickerCommitted: (() -> Void)?
    var onStickerDeleted: ((UUID) -> Void)?
    var onStickerSelected: ((UUID) -> Void)?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.Color.surface
        playerLayer.videoGravity = .resizeAspect
        clipsToBounds = true
        layer.cornerRadius = Theme.Radius.md

        isAccessibilityElement = false
        accessibilityIdentifier = "videoCanvas"

        stripView.backgroundColor = .clear
        addSubview(stripView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Configuration

    /// Lays out the slot chrome. `frames` are in canvas pixels of LAYOUT space
    /// (`pan`'s strip when there is one); they're scaled into view space by
    /// `canvasToView`.
    ///
    /// `animated` is for a LAYOUT change: the chrome glides to the new slots and
    /// the video on screen is cut into its cells and glides with it (see
    /// `VideoFreezeFrameView.morph`), held until the rebuilt composition draws.
    /// Anything else that moves the slots — a border drag, a restore — snaps, as
    /// it always has: a glide per slider tick would lag the finger.
    func configure(canvasSize: CGSize, cellFrames frames: [CGRect],
                   filled: [Bool], selectedIndex: Int?, pan: CanvasPan? = nil,
                   animated: Bool = false) {
        // Where the filled slots sit is read BEFORE anything moves.
        let morphs = animated && window != nil && bounds.width > 0
            && !cellViews.isEmpty && frames != cellFrames
        let morphSources = morphs ? filledSlotRects() : [:]
        self.canvasSize = canvasSize
        self.pan = pan
        self.layoutSize = pan?.stripSize(for: canvasSize) ?? canvasSize
        self.cellFrames = frames
        slotFilled = filled
        updateMotionUpdates()

        // Match the chrome to the slot count (layout switch). Slots keep their
        // index across a layout change — the model keeps each slot's clip — so
        // the views for the slots both layouts share are kept and moved, and
        // only the difference is added or retired.
        var freshCellViews: [VideoCellChromeView] = []
        if cellViews.count != frames.count {
            if cellViews.count > frames.count {
                let leaving = cellViews[frames.count...]
                cellViews.removeLast(cellViews.count - frames.count)
                leaving.forEach { retire($0, animated: morphs) }
            }
            while cellViews.count < frames.count {
                let index = cellViews.count
                let view = makeCellView()
                view.onActivate = { [weak self] in self?.onCellActivated?(index) }
                stripView.addSubview(view)
                cellViews.append(view)
                freshCellViews.append(view)
            }
            cellViews.forEach { stripView.insertSubview($0, at: 0) }
            refreshAccessibilityElements()
        }

        for (index, cellView) in cellViews.enumerated() {
            let isFilled = filled.indices.contains(index) ? filled[index] : false
            let isSelected = (index == selectedIndex)
            cellView.isAccessibilityElement = true
            cellView.accessibilityLabel = CanvasAccessibility.videoCellLabel(
                index: index, count: frames.count, isFilled: isFilled)
            cellView.accessibilityHint = CanvasAccessibility.videoCellHint(isFilled: isFilled)
            cellView.accessibilityTraits = isSelected ? [.button, .selected] : .button
            // A filled cell shows the video through it — only its outline matters.
            cellView.backgroundColor = isFilled ? .clear : Theme.Color.controlFill
            cellView.layer.borderWidth = isSelected ? 3 : 1
            cellView.layer.borderColor = (isSelected ? Theme.Color.accent
                                                     : Theme.Color.separator).cgColor
            cellView.accessibilityIdentifier = "videoCell-\(index)"
            if let chip = cellView.subviews.first as? EmptyZoneChipView {
                chip.isHidden = isFilled
            }
        }
        if morphs { morphLayout(from: morphSources, fresh: freshCellViews) }
        setNeedsLayout()
    }

    // MARK: - Layout morph + item swaps

    private var freezeFrameView: VideoFreezeFrameView {
        if let view = freezeFrameStorage { return view }
        let view = VideoFreezeFrameView(frame: bounds)
        freezeFrameStorage = view
        keepFreezeFrameBelowContent()
        return view
    }

    /// Slots the held frame directly under the canvas's first real subview.
    ///
    /// NOT `insertSubview(_:at: 0)` / `sendSubviewToBack`: `AVPlayerLayer` draws
    /// its video in a private SUBLAYER of this backing layer, at the front of
    /// the sublayer list, so index 0 is underneath the video. There the hold
    /// only showed once the swap had emptied the video layer, and a layout
    /// glide's pieces moved invisibly behind the old frame. Inserting below a
    /// sibling view keeps it above that private layer and below the chrome.
    private func keepFreezeFrameBelowContent() {
        guard let freeze = freezeFrameStorage else { return }
        if let lowest = subviews.first(where: { $0 !== freeze }) {
            insertSubview(freeze, belowSubview: lowest)
        } else if freeze.superview !== self {
            addSubview(freeze)
        }
    }

    /// Where the player draws the frame inside this view. The canvas is sized
    /// to the composition's aspect, so this is the bounds in practice; the
    /// layer's own answer is used when it has one, so a rounding difference
    /// can't misalign a cut.
    private var currentVideoRect: CGRect {
        let rect = playerLayer.videoRect
        return rect.width > 0 && rect.height > 0 ? rect : bounds
    }

    /// Call right before the player's item is replaced: holds the frame on
    /// screen over the gap the swap leaves.
    func holdFrameForItemSwap() {
        freezeFrameView.hold(VideoFreezeFrameView.currentFrame(of: playerLayer),
                             videoRect: currentVideoRect)
        keepFreezeFrameBelowContent()
    }

    /// Call right after the swap: lets the held frame go once `item` is
    /// drawing — at once when there is no item to wait for.
    func releaseHeldFrame(once item: AVPlayerItem?) {
        guard let freeze = freezeFrameStorage else { return }
        guard let item else { return freeze.release { true } }
        freeze.release { [weak self, weak item] in
            guard let self, let item, self.player?.currentItem === item else { return true }
            switch item.status {
            case .readyToPlay: return self.playerLayer.isReadyForDisplay
            case .failed: return true
            default: return false
            }
        }
    }

    /// The filled slots' current rects in this view's space, by slot index.
    private func filledSlotRects() -> [Int: CGRect] {
        var rects: [Int: CGRect] = [:]
        for (index, view) in cellViews.enumerated()
        where slotFilled.indices.contains(index) && slotFilled[index] {
            rects[index] = convert(view.frame, from: view.superview)
        }
        return rects
    }

    private func morphLayout(from sources: [Int: CGRect], fresh: [VideoCellChromeView]) {
        let transform = canvasToView()
        let targets = cellFrames.map { $0.applying(transform) }
        let duration = Theme.Motion.duration(Theme.Motion.slow)

        if Theme.Motion.isReduced {
            // No travel under Reduce Motion — the old frame simply crossfades
            // into the new layout once it draws.
            holdFrameForItemSwap()
        } else {
            let pieceTargets = zip(cellViews, targets).map { view, rect in
                convert(rect, from: view.superview)
            }
            freezeFrameView.morph(VideoFreezeFrameView.currentFrame(of: playerLayer),
                                  videoRect: currentVideoRect,
                                  from: sources, to: pieceTargets, duration: duration)
            keepFreezeFrameBelowContent()
        }

        // A new slot fades in where it will be; the rest glide there.
        for view in fresh {
            view.frame = targets[cellViews.firstIndex(of: view) ?? 0]
            view.alpha = 0
        }
        UIView.animate(
            withDuration: duration, delay: 0,
            usingSpringWithDamping: Theme.Motion.isReduced ? 1 : VideoFreezeFrameView.morphDamping,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            for (view, rect) in zip(self.cellViews, targets) {
                view.frame = rect
                view.alpha = 1
                view.layoutIfNeeded()
            }
        }
    }

    /// Takes a view off the canvas — fading when the change is animated, so a
    /// slot, caption or sticker that goes away leaves rather than vanishes. It
    /// stops taking touches at once: it is no longer part of the document.
    private func retire(_ view: UIView, animated: Bool) {
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        guard animated, window != nil else { return view.removeFromSuperview() }
        UIView.animate(
            withDuration: Theme.Motion.duration(Theme.Motion.quick), delay: 0,
            options: [.beginFromCurrentState, .curveEaseIn]
        ) {
            view.alpha = 0
            if !Theme.Motion.isReduced {
                view.transform = view.transform.scaledBy(x: 0.85, y: 0.85)
            }
        } completion: { _ in
            view.removeFromSuperview()
        }
    }

    // MARK: - Interactive overlays

    /// Pools/rebuilds the interactive text views and repositions them. Wires each
    /// view's gesture callbacks back out through this canvas.
    ///
    /// `selected` mirrors `updateStickerOverlays(_:selected:)` — Task 6's "Text
    /// selected" contextual rail group is not the only feedback that something
    /// is selected: `TextOverlayView` already carries the same persistent
    /// selection chrome `StickerOverlayView` does, so the tapped zone shows it
    /// on the canvas too.
    ///
    /// Each caption keeps ITS view across updates — matched by id, not by
    /// position — so deleting one no longer hands its neighbour's view a new
    /// caption (a visible jump), and a caption moved by undo glides back from
    /// where it was. See `applyOverlayChange` for what animates.
    func updateTextOverlays(_ overlays: [TextOverlay], selected: UUID? = nil) {
        let previous = textModels
        var pool = Dictionary(zip(previous.map(\.id), textViews)) { first, _ in first }
        var fresh: Set<ObjectIdentifier> = []
        textModels = overlays
        textViews = overlays.map { overlay in
            if let view = pool.removeValue(forKey: overlay.id) { return view }
            let view = TextOverlayView()
            view.onChanged = { [weak self] in self?.onTextChanged?($0) }
            view.onCommitted = { [weak self] in self?.onTextCommitted?() }
            view.onTapped = { [weak self] in self?.onTextTapped?($0) }
            stripView.addSubview(view)
            fresh.insert(ObjectIdentifier(view))
            return view
        }
        pool.values.forEach { retire($0, animated: true) }
        for (view, overlay) in zip(textViews, overlays) {
            view.isSelected = overlay.id == selected
        }
        textViews.forEach { stripView.bringSubviewToFront($0) }
        stickerViews.forEach { stripView.bringSubviewToFront($0) }   // stickers above text

        let before = Dictionary(previous.map { ($0.id, $0) }) { first, _ in first }
        for (view, overlay) in zip(textViews, overlays) {
            applyOverlayChange(view, isNew: fresh.contains(ObjectIdentifier(view)),
                               moved: before[overlay.id].map { $0 != overlay } ?? false,
                               restyled: before[overlay.id].map { Self.isRestyle($0, overlay) } ?? false) {
                self.place(view, for: overlay)
            }
        }
        setNeedsLayout()
        updateMotionUpdates()
        // A freshly pooled view defaults to visible — refresh immediately so a
        // timed-out caption doesn't flash on screen before the next player tick.
        refreshTimedState()
        refreshAccessibilityElements()
    }

    /// Pooled by sticker id, like captions. A sticker used to be torn down and
    /// rebuilt on EVERY document change — including each tick of its own drag,
    /// which re-created the very view under the finger and re-rendered its
    /// symbol sixty times a second.
    func updateStickerOverlays(_ overlays: [StickerOverlay], selected: UUID?) {
        let before = Dictionary(stickerModels.map { ($0.id, $0) }) { first, _ in first }
        var pool = Dictionary(stickerViews.map { ($0.stickerID, $0) }) { first, _ in first }
        var fresh: Set<ObjectIdentifier> = []
        stickerModels = overlays
        stickerViews = overlays.map { overlay in
            if let view = pool.removeValue(forKey: overlay.id) { return view }
            let view = StickerOverlayView(overlay: overlay)
            view.onChanged = { [weak self] in self?.onStickerChanged?($0) }
            view.onCommitted = { [weak self] in self?.onStickerCommitted?() }
            view.onDeleted = { [weak self] in self?.onStickerDeleted?($0) }
            view.onSelected = { [weak self] in self?.onStickerSelected?($0) }
            stripView.addSubview(view)
            fresh.insert(ObjectIdentifier(view))
            return view
        }
        pool.values.forEach { retire($0, animated: true) }
        for (view, overlay) in zip(stickerViews, overlays) {
            view.isSelected = overlay.id == selected
            applyOverlayChange(view, isNew: fresh.contains(ObjectIdentifier(view)),
                               moved: before[overlay.id].map { $0 != overlay } ?? false,
                               restyled: false) {
                self.place(view, for: overlay)
            }
        }
        stickerViews.forEach { stripView.bringSubviewToFront($0) }
        setNeedsLayout()
        refreshAccessibilityElements()
    }

    /// How an overlay's view takes a document change:
    ///
    /// - **new** — placed, then pops in (fade + a small spring up to size);
    /// - **moved by something other than the finger** (undo/redo, a nudge, a
    ///   style sheet) — glides from where it is to where the document says;
    /// - **restyled** — the old look crossfades into the new one;
    /// - **under the finger** — placed directly: the view already moved itself,
    ///   and animating toward where it already is would only lag the drag.
    ///
    /// Before the canvas has a size there is nothing to animate from, so
    /// `layoutSubviews` places everything when it first lays out.
    private func applyOverlayChange(_ view: UIView, isNew: Bool, moved: Bool, restyled: Bool,
                                    place: @escaping () -> Void) {
        guard bounds.width > 0, window != nil else { return }
        if isNew {
            place()
            guard !Theme.Motion.isReduced else {
                view.alpha = 0
                UIView.animate(withDuration: Theme.Motion.duration(Theme.Motion.standard)) { view.alpha = 1 }
                return
            }
            let rest = view.transform
            view.alpha = 0
            view.transform = rest.scaledBy(x: 0.6, y: 0.6)
            UIView.animate(
                withDuration: Theme.Motion.standard, delay: 0,
                usingSpringWithDamping: Theme.Motion.springDamping,
                initialSpringVelocity: Theme.Motion.springVelocity,
                options: [.allowUserInteraction]
            ) {
                view.alpha = 1
                view.transform = rest
            }
            return
        }
        guard moved else { return }
        guard !Self.isUnderFinger(view) else { return place() }
        if restyled {
            UIView.transition(with: view, duration: Theme.Motion.duration(Theme.Motion.quick),
                              options: [.transitionCrossDissolve, .allowUserInteraction],
                              animations: place)
            return
        }
        UIView.animate(
            withDuration: Theme.Motion.duration(Theme.Motion.standard), delay: 0,
            usingSpringWithDamping: Theme.Motion.effectiveSpringDamping, initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            place()
            view.layoutIfNeeded()
        }
    }

    /// Whether one of the view's own gestures is mid-flight.
    private static func isUnderFinger(_ view: UIView) -> Bool {
        view.gestureRecognizers?.contains { $0.state == .began || $0.state == .changed } ?? false
    }

    /// A change of look rather than of place or size — a discrete choice worth
    /// a crossfade. Deliberately not the text or the font SIZE: those change
    /// per keystroke and per slider tick in the style sheet, where a dissolve
    /// on every one would smear the typing.
    private static func isRestyle(_ old: TextOverlay, _ new: TextOverlay) -> Bool {
        old.style != new.style || old.colorHex != new.colorHex || old.fontName != new.fontName
            || old.isBold != new.isBold || old.isItalic != new.isItalic
            || old.isUnderlined != new.isUnderlined || old.alignmentRaw != new.alignmentRaw
    }

    // MARK: - Accessibility (phase 6.5)

    /// Slots in layout order, then captions, then stickers — the order the photo
    /// canvas uses. A caption hidden by its timing is skipped by VoiceOver on its
    /// own (`isHidden`).
    ///
    /// On a panning collage only what the camera currently shows is listed:
    /// the strip's other panels — and the captions and stickers on them — sit
    /// outside the canvas, clipped, and VoiceOver used to land on them anyway.
    /// So the list follows the camera (`layoutStrip` calls back here), and is
    /// only reassigned when what is visible actually changes.
    private func refreshAccessibilityElements() {
        let all = (cellViews as [UIView]) + (textViews as [UIView]) + (stickerViews as [UIView])
        let visible = all.filter { isOnCanvas($0) }
        let current = (accessibilityElements as? [UIView]) ?? []
        guard current.count != visible.count || !zip(current, visible).allSatisfy({ $0 === $1 }) else { return }
        accessibilityElements = visible
    }

    /// Whether any of `view` falls inside the canvas the camera shows. Before
    /// the first layout nothing has a frame yet, so everything counts.
    private func isOnCanvas(_ view: UIView) -> Bool {
        guard bounds.width > 0, bounds.height > 0, view.superview != nil else { return true }
        return convert(view.frame, from: view.superview).intersects(bounds)
    }

    /// True when an interactive text/sticker view sits under the point — the VC uses
    /// this to skip cell-tap handling (the overlay's own gestures take the touch).
    func hasInteractiveOverlay(at point: CGPoint) -> Bool {
        let stripPoint = convert(point, to: stripView)
        return stickerViews.contains { $0.frame.contains(stripPoint) }
            || textViews.contains { !$0.isHidden && $0.frame.contains(stripPoint) }
    }

    // MARK: - Playback time

    /// The VC's player time observer calls this ~10x/sec with the current playback
    /// time (seconds). Hides/shows the pooled text views so a caption is only ever
    /// on screen inside its `startTime`/`endTime` window — the same thing the
    /// export's per-frame overlay selection does, so preview and export agree.
    func setPreviewTime(_ seconds: Double) {
        guard seconds != previewTime else { return }
        previewTime = seconds
        refreshTimedState()
    }

    /// Test seam: the pooled text overlay views, to assert visibility directly
    /// rather than through screenshot comparison.
    var textOverlayViewsForTesting: [UIView] { textViews }

    /// Test seam: the pooled sticker views, in model order.
    var stickerOverlayViewsForTesting: [StickerOverlayView] { stickerViews }

    /// Test seam: the view holding frames over item swaps, once one exists.
    var freezeFrameViewForTesting: VideoFreezeFrameView? { freezeFrameStorage }

    /// Test seam: the slot chrome, in slot order.
    var cellChromeViewsForTesting: [UIView] { cellViews }

    /// The time captions are currently being shown against. A scrub must move
    /// this synchronously — see `VideoEditorViewController.scrub(to:)`.
    var previewTimeForTesting: Double { previewTime }

    /// Everything that follows the preview time: which captions are on screen,
    /// how far into its animation each one is, and where the camera sits.
    private func refreshTimedState() {
        for (view, overlay) in zip(textViews, textModels) {
            let visible = overlay.isVisible(at: previewTime)
            view.isHidden = !visible
            guard visible else { continue }
            view.applyAnimation(animatesCaptions
                ? TextAnimationMath.frame(for: overlay, at: previewTime) : nil)
        }
        layoutStrip()
    }

    /// Test seam: where the camera currently sits, in view points.
    var cameraOffsetForTesting: CGPoint { CGPoint(x: -stripView.frame.minX, y: -stripView.frame.minY) }

    // MARK: - Motion updates

    /// Whether anything on the canvas moves with time between the VC's coarse
    /// ticks — a pan or an animated caption.
    private var needsMotionUpdates: Bool {
        (pan?.extent ?? 1) > 1 || textModels.contains { $0.animation != .none }
    }

    private func updateMotionUpdates() {
        if needsMotionUpdates, window != nil {
            guard displayLink == nil else { return }
            let link = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.tick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateMotionUpdates()
    }

    fileprivate func displayLinkFired() {
        // Only while the player actually runs: a paused preview is moved by the
        // VC's scrub/seek path, and re-reading an unchanged time is wasted work.
        guard let player, player.rate != 0 else { return }
        let seconds = player.currentTime().seconds
        guard seconds.isFinite else { return }
        setPreviewTime(seconds)
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        freezeFrameStorage?.frame = bounds
        layoutStrip()
        let transform = canvasToView()
        for (index, cellView) in cellViews.enumerated() where cellFrames.indices.contains(index) {
            cellView.frame = cellFrames[index].applying(transform)
            (cellView.subviews.first as? EmptyZoneChipView)?.canvasShortSide =
                min(bounds.width, bounds.height)
        }
        layoutOverlays()
        refreshAccessibilityElements()
    }

    /// Positions the interactive overlay views from their normalized models (bounds
    /// == the canvas, so 1:1 with the composited video the player shows). Font scale
    /// maps reference-canvas point sizes onto the on-screen size, matching export.
    private func layoutOverlays() {
        for (view, overlay) in zip(textViews, textModels) { place(view, for: overlay) }
        for (view, overlay) in zip(stickerViews, stickerModels) { place(view, for: overlay) }
    }

    /// Puts a caption's view where its model says, at the on-screen type scale.
    /// The one placement both layout and the animated update paths use.
    private func place(_ view: TextOverlayView, for overlay: TextOverlay) {
        let fontScale = canvasSize.width > 0 ? bounds.width / canvasSize.width : 1
        // `bounds`/`center`, not `frame`: an animating caption carries a
        // transform on its content — and a popping-in one on the view itself —
        // so the view's own frame is only meaningful at identity.
        let frame = TextRendering.frame(for: overlay, in: stripView.bounds.size)
        view.bounds = CGRect(origin: .zero, size: frame.size)
        view.center = CGPoint(x: frame.midX, y: frame.midY)
        view.configure(with: overlay, fontScale: fontScale)
    }

    private func place(_ view: StickerOverlayView, for overlay: StickerOverlay) {
        view.apply(overlay: overlay, in: stripView.bounds.size)
    }

    /// Sizes the strip to layout space and slides it by the camera offset at the
    /// preview time. Identity (strip == canvas, no offset) when nothing pans.
    private func layoutStrip() {
        let scale = canvasSize.width > 0 ? bounds.width / canvasSize.width : 1
        let size = CGSize(width: layoutSize.width * scale, height: layoutSize.height * scale)
        let camera = pan?.cameraOffset(at: previewTime, duration: compositionDuration,
                                       canvas: bounds.size) ?? .zero
        let frame = CGRect(origin: CGPoint(x: -camera.x, y: -camera.y), size: size)
        guard stripView.frame != frame else { return }
        let resized = stripView.bounds.size != size
        stripView.frame = frame
        if resized { layoutOverlays() }
        refreshAccessibilityElements()
    }

    /// Maps canvas pixels → view points. The view is sized to the canvas aspect
    /// ratio by the VC, so this is a uniform scale.
    private func canvasToView() -> CGAffineTransform {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return .identity }
        return CGAffineTransform(scaleX: bounds.width / canvasSize.width,
                                 y: bounds.height / canvasSize.height)
    }

    // MARK: - Hit testing

    /// The layout slot under a point in this view's coordinates, or nil.
    func cellIndex(at point: CGPoint) -> Int? {
        guard canvasSize.width > 0, canvasSize.height > 0, bounds.width > 0 else { return nil }
        // Through the strip, so a tap lands on the slot under the finger wherever
        // the camera has travelled to.
        let stripPoint = convert(point, to: stripView)
        let canvasPoint = CGPoint(x: stripPoint.x * canvasSize.width / bounds.width,
                                  y: stripPoint.y * canvasSize.height / bounds.height)
        return cellFrames.firstIndex { $0.contains(canvasPoint) }
    }

    // MARK: - Private

    private func makeCellView() -> VideoCellChromeView {
        let cellView = VideoCellChromeView()
        cellView.isUserInteractionEnabled = false   // the VC owns the tap gesture
        // Cells render with sharp rectangular edges — no per-cell corner-radius
        // concept exists in the video composition — so the selection chrome must
        // stay square too, or its rounded outline reads as misaligned against the
        // rectangular video underneath it.
        cellView.clipsToBounds = true

        // The same "+" chip the photo canvas shows in an empty zone, so a slot
        // that wants media looks the same in both editors.
        let chip = EmptyZoneChipView()
        chip.translatesAutoresizingMaskIntoConstraints = false
        cellView.addSubview(chip)
        NSLayoutConstraint.activate([
            chip.leadingAnchor.constraint(equalTo: cellView.leadingAnchor),
            chip.trailingAnchor.constraint(equalTo: cellView.trailingAnchor),
            chip.topAnchor.constraint(equalTo: cellView.topAnchor),
            chip.bottomAnchor.constraint(equalTo: cellView.bottomAnchor),
        ])
        return cellView
    }
}

/// `CADisplayLink` retains its target; this breaks the cycle so a canvas that
/// leaves the screen is not kept alive by its own animation clock.
private final class DisplayLinkProxy {
    private weak var canvas: VideoCanvasView?
    init(_ canvas: VideoCanvasView) { self.canvas = canvas }
    @MainActor @objc func tick() { canvas?.displayLinkFired() }
}

/// A slot's chrome view, and its accessibility element. Activation routes out
/// through the canvas exactly as a tap on the slot does (phase 6.5).
final class VideoCellChromeView: UIView {
    var onActivate: (() -> Void)?

    override func accessibilityActivate() -> Bool {
        onActivate?()
        return true
    }
}
