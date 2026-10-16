//
//  VideoFreezeFrameView.swift
//  Caroullage
//
//  The preview's last frame, held over the player while it changes items.
//
//  `AVPlayer.replaceCurrentItem(with:)` empties the player layer until the new
//  item has drawn its first frame, so every composition rebuild flashed the
//  canvas background through the video — a trim, a transition, a new layout.
//  This view covers that gap with the frame that was on screen and fades away
//  once the new item is drawing, so a rebuild reads as a crossfade.
//
//  A layout change gets more than a hold. The frame is cut along the old slots
//  and each piece glides to its slot in the new layout while the rebuilt
//  composition loads underneath: the move the user sees instead of a snap.
//  Pieces fill their moving slot the way the composition fills a cell (aspect
//  fill), so a tall slot becoming a wide one reframes rather than squashes.
//
//  It sits directly above the player layer and below every other subview of
//  the canvas — slot chrome, captions and stickers keep drawing and taking
//  touches on top of it — and never takes a touch itself.
//

import AVFoundation
import UIKit
import VideoToolbox

final class VideoFreezeFrameView: UIView {

    // MARK: - Grabbing the frame on screen

    /// The frame `playerLayer` is showing right now, or nil when there is none
    /// to read (no item yet, or a runtime that cannot draw it).
    ///
    /// Two sources, because neither covers both states. A paused layer hands
    /// back exactly the buffer it is displaying; a playing one refuses to
    /// (`displayedPixelBuffer` is nil at any non-zero rate), so playback reads
    /// the item's own video output instead — attached to every preview item by
    /// `makeFrameTap()`.
    static func currentFrame(of playerLayer: AVPlayerLayer) -> CGImage? {
        if let buffer = playerLayer.displayedPixelBuffer() {
            return image(from: buffer)
        }
        guard let item = playerLayer.player?.currentItem,
              let tap = item.outputs.lazy.compactMap({ $0 as? AVPlayerItemVideoOutput }).first,
              let buffer = tap.copyPixelBuffer(forItemTime: item.currentTime(), itemTimeForDisplay: nil)
        else { return nil }
        return image(from: buffer)
    }

    /// The output `currentFrame(of:)` reads while playing. Add one to each
    /// preview item before it reaches the player, so it sees every frame.
    static func makeFrameTap() -> AVPlayerItemVideoOutput {
        AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
    }

    private static func image(from buffer: CVPixelBuffer) -> CGImage? {
        var image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &image)
        return image
    }

    // MARK: - State

    /// The whole frame, for a hold with no move.
    private let fullFrame = UIImageView()
    /// One clipped piece per filled slot, keyed by slot index, while a layout
    /// change is morphing (or has morphed and is waiting to be released).
    private var pieces: [Int: UIView] = [:]
    /// The frame being held, and where it sat in this view — what later pieces
    /// are cut from if a layout change lands during a plain hold.
    private var frozenImage: CGImage?
    private var frozenVideoRect: CGRect = .zero

    /// Whether anything is being held over the player.
    private(set) var isHolding = false
    /// Bumped by every hold, so a fade-out that started before it cannot clear it.
    private var generation = 0
    /// A morph owns the screen until its move has landed; no release before this.
    private var holdUntil: CFTimeInterval = 0

    private var releaseCondition: (() -> Bool)?
    private var releaseDeadline: CFTimeInterval = 0
    /// When a hold that nobody releases gives up — see `watchdogTimeout`.
    private var watchdogDeadline: CFTimeInterval = 0
    private var displayLink: CADisplayLink?
    /// Set once the item a hold was waiting for is drawing. From then on the
    /// player shows what the hold shows — so the next hold or layout change
    /// must take a FRESH frame rather than keep, or re-aim, pieces cut from a
    /// moment that has long passed (browsing layouts while playing otherwise
    /// froze the preview on the first tap's frame).
    private var isSuperseded = false

    /// How long a release may wait for the new item before fading regardless —
    /// a failed or slow item must never leave the preview frozen.
    static let releaseTimeout: TimeInterval = 1.5
    /// How long a hold may wait for ANY release. A layout change holds before
    /// its rebuild has even started; if that rebuild stalls, the still frame
    /// must not sit over live video indefinitely.
    static let watchdogTimeout: TimeInterval = 4

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isHidden = true
        clipsToBounds = true
        // What a glide uncovers is, for that moment, an empty slot — so it is
        // painted as one: the same well the slot chrome fills an empty slot
        // with. Black (the composition's own backdrop) read as holes punched in
        // the canvas, and darkened every new slot while its chrome faded in.
        backgroundColor = Theme.Color.controlFill
        accessibilityElementsHidden = true

        fullFrame.contentMode = .scaleToFill
        fullFrame.autoresizingMask = Self.followsResize
        fullFrame.isHidden = true
        addSubview(fullFrame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { clear() }
    }

    // MARK: - Holding

    /// Holds `image` — the frame on screen, drawn into `videoRect` — over the
    /// player until `release(when:)` lets it go.
    ///
    /// No image (nothing could be read) keeps whatever is already held rather
    /// than dropping it: a second swap that lands before the first item has
    /// drawn reads an empty layer, and the older frame is still the right thing
    /// to show.
    ///
    /// Morph pieces keep the screen too, gliding or settled, until the item
    /// they stand in for is drawing: they already show the NEW layout, while
    /// the player — whose item the rebuild is about to replace — still draws
    /// the old one, so a fresh grab would snap the slots back to where they
    /// came from. Once that item draws, a fresh grab is the better picture.
    func hold(_ image: CGImage?, videoRect: CGRect) {
        if image != nil, isSuperseded { removePieces() }
        guard let image, pieces.isEmpty else {
            if isHolding { beginHold() }
            return
        }
        beginHold()
        frozenImage = image
        frozenVideoRect = videoRect
        fullFrame.image = UIImage(cgImage: image)
        fullFrame.frame = videoRect
        fullFrame.isHidden = false
    }

    /// Cuts the frame along the old slots and glides each piece to its new
    /// one. `from` holds the FILLED slots' rects before the change (an empty
    /// slot has no video to carry), `to` every slot's rect after it, both in
    /// this view's points; a slot past the end of `to` was removed, so its
    /// piece fades out where it stands.
    ///
    /// A morph that lands on another one still in flight re-aims the pieces it
    /// already has from wherever they are on screen, rather than recutting a
    /// frame that is itself mid-move. Once the earlier change's item is
    /// drawing, the player's frame is current and matches the slots, so the
    /// new change is cut from it instead.
    func morph(_ image: CGImage?, videoRect: CGRect,
               from: [Int: CGRect], to: [CGRect], duration: TimeInterval) {
        if image != nil, isSuperseded { removePieces() }
        if pieces.isEmpty {
            guard let source = image ?? frozenImage else { return }
            let sourceRect = image != nil ? videoRect : frozenVideoRect
            beginHold()
            frozenImage = source
            frozenVideoRect = sourceRect
            fullFrame.isHidden = true
            for (index, rect) in from {
                guard let crop = Self.cropRect(for: rect, videoRect: sourceRect, imageSize: source.size),
                      let cropped = source.cropping(to: crop) else { continue }
                pieces[index] = makePiece(cropped, frame: rect)
            }
        } else {
            beginHold()
        }
        guard !pieces.isEmpty else {
            // Nothing to move (no filled slot before the change): hold the whole
            // frame instead, so the swap still crossfades.
            if let frozenImage { hold(frozenImage, videoRect: frozenVideoRect) }
            return
        }
        holdUntil = CACurrentMediaTime() + duration

        let leaving = pieces.filter { !to.indices.contains($0.key) }
        for index in leaving.keys { pieces[index] = nil }
        UIView.animate(
            withDuration: duration, delay: 0,
            usingSpringWithDamping: Self.morphDamping, initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            for (index, piece) in self.pieces { piece.frame = to[index] }
            for piece in leaving.values {
                piece.alpha = 0
                piece.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
            }
        } completion: { _ in
            leaving.values.forEach { $0.removeFromSuperview() }
        }
    }

    /// Keeps a held frame registered with the video if the canvas resizes under
    /// it (the timeline expanding, a panel opening) before it is released.
    private static let followsResize: UIView.AutoresizingMask = [
        .flexibleWidth, .flexibleHeight,
        .flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin,
    ]

    /// Settled rather than bouncy: a tile of video that overshoots its slot
    /// reads as a glitch, not as life.
    static let morphDamping: CGFloat = 0.86

    // MARK: - Releasing

    /// Fades the held frame away once `isReady` reports the new item is drawing
    /// — never while a morph is still moving, and never later than
    /// `releaseTimeout`. Polled per display frame: the player layer's readiness
    /// can already read true for the item it is leaving, so a single KVO edge is
    /// not a signal this can trust; a condition checked until it holds is.
    func release(when isReady: @escaping () -> Bool) {
        guard isHolding else { return }
        releaseCondition = isReady
        releaseDeadline = CACurrentMediaTime() + Self.releaseTimeout
        startTracking()
    }

    fileprivate func displayLinkFired(now: CFTimeInterval = CACurrentMediaTime()) {
        guard isHolding else { return stopTracking() }
        guard now >= holdUntil else { return }
        if let condition = releaseCondition {
            let isReady = condition()
            guard isReady || now >= releaseDeadline else { return }
            isSuperseded = isReady
        } else {
            guard now >= watchdogDeadline else { return }
        }
        stopTracking()
        fadeOut()
    }

    private func fadeOut() {
        let token = generation
        UIView.animate(
            withDuration: Theme.Motion.duration(Theme.Motion.quick), delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]
        ) {
            self.alpha = 0
        } completion: { _ in
            guard self.generation == token else { return }
            self.clear()
        }
    }

    // MARK: - Private

    /// Every hold starts over: a fade in progress is cancelled, any pending
    /// release is dropped (the caller releases again once its own swap lands),
    /// and the watchdog is re-armed.
    private func beginHold() {
        generation += 1
        releaseCondition = nil
        isSuperseded = false
        layer.removeAllAnimations()
        alpha = 1
        isHidden = false
        isHolding = true
        watchdogDeadline = CACurrentMediaTime() + Self.watchdogTimeout
        startTracking()
    }

    private func clear() {
        stopTracking()
        removePieces()
        fullFrame.image = nil
        fullFrame.isHidden = true
        frozenImage = nil
        holdUntil = 0
        isSuperseded = false
        alpha = 1
        isHidden = true
        isHolding = false
    }

    private func startTracking() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: FreezeFrameDisplayLinkTarget(self),
                                 selector: #selector(FreezeFrameDisplayLinkTarget.tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopTracking() {
        releaseCondition = nil
        displayLink?.invalidate()
        displayLink = nil
    }

    private func removePieces() {
        pieces.values.forEach { $0.removeFromSuperview() }
        pieces = [:]
    }

    private func makePiece(_ image: CGImage, frame: CGRect) -> UIView {
        let piece = UIView(frame: frame)
        piece.clipsToBounds = true
        piece.autoresizingMask = Self.followsResize
        let imageView = UIImageView(image: UIImage(cgImage: image))
        imageView.contentMode = .scaleAspectFill
        imageView.frame = piece.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        piece.addSubview(imageView)
        addSubview(piece)
        return piece
    }

    /// The pixels of a frame drawn into `videoRect` that sit under `rect` (both
    /// in view points), or nil when the two don't overlap.
    static func cropRect(for rect: CGRect, videoRect: CGRect, imageSize: CGSize) -> CGRect? {
        guard videoRect.width > 0, videoRect.height > 0 else { return nil }
        let sx = imageSize.width / videoRect.width
        let sy = imageSize.height / videoRect.height
        let mapped = CGRect(x: (rect.minX - videoRect.minX) * sx,
                            y: (rect.minY - videoRect.minY) * sy,
                            width: rect.width * sx,
                            height: rect.height * sy)
            .integral
            .intersection(CGRect(origin: .zero, size: imageSize))
        return mapped.isNull || mapped.isEmpty ? nil : mapped
    }

    // MARK: - Test seams

    var pieceCountForTesting: Int { pieces.count }
    var isShowingFullFrameForTesting: Bool { !fullFrame.isHidden && fullFrame.image != nil }
    var frozenImageForTesting: CGImage? { frozenImage }
    /// Runs the release check now (or `secondsLater`) instead of on the next
    /// display frame.
    func tickForTesting(secondsLater: TimeInterval = 0) {
        displayLinkFired(now: CACurrentMediaTime() + secondsLater)
    }
}

private extension CGImage {
    var size: CGSize { CGSize(width: width, height: height) }
}

/// `CADisplayLink` retains its target; this breaks the cycle so a held frame
/// never keeps the canvas alive.
private final class FreezeFrameDisplayLinkTarget: NSObject {
    private weak var view: VideoFreezeFrameView?
    init(_ view: VideoFreezeFrameView) {
        self.view = view
        super.init()
    }
    /// A link whose view is gone stops itself rather than ticking forever.
    @MainActor @objc func tick(_ link: CADisplayLink) {
        guard let view else { return link.invalidate() }
        view.displayLinkFired()
    }
}
