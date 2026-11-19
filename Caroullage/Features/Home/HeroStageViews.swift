//
//  HeroStageViews.swift
//  Caroullage
//
//  The hero's stages: each kind of work is presented the way it is actually
//  used, rather than every page being one picture cropped or letterboxed into
//  the same box.
//
//  - A carousel is a deck of square posts that swipes itself, with the "1/4"
//    counter every carousel post wears — the format explains itself.
//  - A before/after carousel is a wipe across one photograph: the gesture
//    people already know from every photo editor's comparison slider.
//  - A tall story or reel stands as a story frame on a lit stage, whole,
//    instead of being cropped to a close-up or floated on a blur of itself.
//
//  The stage behind the deck and the story frame is a colour-matched dark
//  backdrop with a soft glow, sampled from the artwork. It is designed, not
//  derived from a blur: the previous blurred bed is exactly what made the
//  carousel pages read as letterboxing accidents.
//
//  Every view here is chrome over the hero cell, which owns the tap, so none of
//  them takes touches. All motion stops whenever the page is not the one on
//  screen, and none of it starts under Reduce Motion or Low Power Mode — the
//  static state of every stage is a complete picture in its own right.
//

import CoreImage
import UIKit

// MARK: - Motion gate

@MainActor
enum HeroStageMotion {
    /// The same rule the looping previews follow: decorative motion is opt-out
    /// under Reduce Motion AND Low Power Mode.
    static var isAllowed: Bool { LoopingPreviewPlayerView.isMotionAllowed }
}

// MARK: - Stage tint

/// The colour a stage is lit with, sampled from the artwork it presents.
enum HeroStageTint {

    /// The artwork's average colour, pushed into a range that always reads as a
    /// deep, coloured stage: never grey mud (a floor on saturation), never a
    /// bright wash that white type could not sit on (a ceiling on brightness is
    /// applied by `HeroStageBackdropView`, which only ever uses darkened shades).
    static func tint(of image: CGImage?) -> UIColor {
        guard let image, let average = averageColor(of: image) else {
            return UIColor(red: 0.22, green: 0.20, blue: 0.30, alpha: 1)
        }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return UIColor(hue: hue,
                       saturation: min(max(saturation * 1.35, 0.28), 0.8),
                       brightness: 1, alpha: 1)
    }

    private static func averageColor(of image: CGImage) -> UIColor? {
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drew: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drew else { return nil }
        var red = 0, green = 0, blue = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            red += Int(pixels[index]); green += Int(pixels[index + 1]); blue += Int(pixels[index + 2])
        }
        let count = CGFloat(side * side) * 255
        return UIColor(red: CGFloat(red) / count, green: CGFloat(green) / count,
                       blue: CGFloat(blue) / count, alpha: 1)
    }

    /// `color` at a fixed brightness, keeping its hue and saturation.
    static func shade(_ color: UIColor, brightness: CGFloat, alpha: CGFloat = 1) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, current: CGFloat = 0, oldAlpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &current, alpha: &oldAlpha)
        return UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: alpha)
    }
}

// MARK: - Backdrop

/// A dark, colour-matched stage: a deep vertical gradient in the artwork's hue
/// with a soft radial glow where the artwork stands.
///
/// Fixed dark in both appearances, like the scrim: the type over it is always
/// white, and a stage that flipped light would put it on white.
@MainActor
final class HeroStageBackdropView: UIView {

    override class var layerClass: AnyClass { CAGradientLayer.self }

    private let glow = CAGradientLayer()
    /// Where the glow is centred, in unit coordinates of this view.
    private var glowCenter = CGPoint(x: 0.5, y: 0.45)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        if let gradient = layer as? CAGradientLayer {
            gradient.startPoint = CGPoint(x: 0.5, y: 0)
            gradient.endPoint = CGPoint(x: 0.5, y: 1)
        }
        glow.type = .radial
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(glow)
        apply(tint: HeroStageTint.tint(of: nil), glowCenter: glowCenter)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func apply(tint: UIColor, glowCenter: CGPoint) {
        self.glowCenter = glowCenter
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        (layer as? CAGradientLayer)?.colors = [
            HeroStageTint.shade(tint, brightness: 0.30).cgColor,
            HeroStageTint.shade(tint, brightness: 0.12).cgColor,
        ]
        glow.colors = [
            HeroStageTint.shade(tint, brightness: 0.85, alpha: 0.55).cgColor,
            HeroStageTint.shade(tint, brightness: 0.85, alpha: 0).cgColor,
        ]
        CATransaction.commit()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // A circle, not an ellipse stretched to the card: the glow is a light
        // falling on the stage, centred on the artwork.
        let radius = max(bounds.width, bounds.height) * 0.62
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glow.frame = CGRect(x: bounds.width * glowCenter.x - radius,
                            y: bounds.height * glowCenter.y - radius,
                            width: radius * 2, height: radius * 2)
        CATransaction.commit()
    }
}

// MARK: - Page dots

/// The hero's position, drawn inside each page's caption: a pill for the
/// current page and dots for the rest.
///
/// In the caption rather than pinned to a corner of the card, because no
/// corner is free on every stage — the story frame stands on the trailing
/// edge, the wipe's labels hold the top. Under the title the dots sit on the
/// one surface every stage guarantees is dark.
@MainActor
final class HeroDotsView: UIView {

    private static let dot: CGFloat = 6
    private static let pill: CGFloat = 18
    private static let gap: CGFloat = 5

    private var count = 0
    private var current = 0
    private var dots: [UIView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(count: Int, current: Int) {
        self.count = count
        self.current = current
        dots.forEach { $0.removeFromSuperview() }
        dots = (0..<count).map { index in
            let view = UIView()
            view.layer.cornerRadius = Self.dot / 2
            view.backgroundColor = Theme.Color.textOnToast.withAlphaComponent(index == current ? 1 : 0.4)
            addSubview(view)
            return view
        }
        isHidden = count < 2
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override var intrinsicContentSize: CGSize {
        guard count > 0 else { return .zero }
        let width = Self.pill + CGFloat(count - 1) * (Self.dot + Self.gap)
        return CGSize(width: width, height: Self.dot)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        var x: CGFloat = 0
        for (index, view) in dots.enumerated() {
            let width = index == current ? Self.pill : Self.dot
            view.frame = CGRect(x: x, y: (bounds.height - Self.dot) / 2, width: width, height: Self.dot)
            x += width + Self.gap
        }
    }
}

// MARK: - Deck

/// A carousel's frames as a row of posts that swipes itself: the current post
/// centred and full size, its neighbours peeking in smaller and dimmer, a
/// "2/4" counter on the current one.
@MainActor
final class HeroDeckStageView: UIView {

    private static let neighbourScale: CGFloat = 0.8
    /// Neighbours are darkened, not faded: a translucent card lets the stage
    /// show through and reads as a ghost rather than as the next post.
    private static let neighbourShade: CGFloat = 0.5
    private static let gap: CGFloat = 12
    private static let step: Duration = .milliseconds(1700)

    private var cards: [UIView] = []
    private var images: [UIImageView] = []
    private var shades: [UIView] = []
    private var aspect: CGFloat = 1
    /// The frame the counter names and the deck is centred on.
    private var current = 0
    /// Each card's signed distance from the centre, as last laid out.
    private var slots: [Int] = []
    private let counter = HeroCapsuleLabel()
    private var motion: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false

        counter.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        counter.textColor = Theme.Color.textOnToast
        counter.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        counter.insets = UIEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
        counter.layer.cornerCurve = .continuous
        counter.clipsToBounds = true
        counter.layer.zPosition = 100
        addSubview(counter)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(frames: [UIImage]) {
        stop()
        cards.forEach { $0.removeFromSuperview() }
        cards = []
        images = []
        shades = []
        current = 0
        aspect = frames.first.map { $0.size.width / max($0.size.height, 1) } ?? 1

        for frame in frames {
            let card = UIView()
            // The shadow sits on the card; the rounding and clipping on the image
            // inside it, or the clip would cut the shadow off.
            card.layer.shadowColor = UIColor.black.cgColor
            card.layer.shadowOpacity = 0.4
            card.layer.shadowRadius = 14
            card.layer.shadowOffset = CGSize(width: 0, height: 8)
            let image = UIImageView(image: frame)
            image.contentMode = .scaleAspectFill
            image.clipsToBounds = true
            image.layer.cornerRadius = Theme.Radius.sm
            image.layer.cornerCurve = .continuous
            card.addSubview(image)
            let shade = UIView()
            shade.backgroundColor = .black
            shade.alpha = 0
            image.addSubview(shade)
            shades.append(shade)
            insertSubview(card, belowSubview: counter)
            cards.append(card)
            images.append(image)
        }
        slots = cards.indices.map(signedSlot(for:))
        counter.isHidden = cards.count < 2
        laidOutSize = .zero
        setNeedsLayout()
        updateCounter()
    }

    // MARK: Motion

    func play() {
        guard motion == nil, cards.count > 1, HeroStageMotion.isAllowed else { return }
        motion = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.step)
                guard !Task.isCancelled, let self else { return }
                self.advance()
            }
        }
    }

    func stop() {
        motion?.cancel()
        motion = nil
    }

    private func advance() {
        current = (current + 1) % cards.count
        let previous = slots
        slots = cards.indices.map(signedSlot(for:))

        // A card leaving on the left wraps round to the far right, behind the
        // deck. Animating that straight would fly it across the whole stage, so
        // it slides out to the left first and is moved over invisibly.
        let wrapping = cards.indices.filter { previous[$0] < 0 && slots[$0] > previous[$0] }
        // The completion runs after the spring — possibly after `configure`
        // has dealt a new deck (cell reuse removes the old cards, which ends
        // their animations early). Capture the cards themselves, never indices
        // into an array that may have been replaced.
        let wrapped = wrapping.map { (card: cards[$0], slot: slots[$0]) }
        UIView.animate(
            withDuration: 0.65, delay: 0, usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0.3, options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            for index in self.cards.indices {
                let slot = wrapping.contains(index) ? previous[index] - 1 : self.slots[index]
                self.place(self.cards[index], at: slot)
            }
        } completion: { _ in
            for (card, slot) in wrapped where card.superview === self {
                self.place(card, at: slot)
            }
        }
        UIView.transition(with: counter, duration: Theme.Motion.quick,
                          options: [.transitionCrossDissolve]) { self.updateCounter() }
    }

    /// Signed distance of card `index` from the current one, wrapped so the
    /// deck is as balanced either side of the centre as its size allows.
    private func signedSlot(for index: Int) -> Int {
        let count = max(cards.count, 1)
        let offset = ((index - current) % count + count) % count
        return offset <= count / 2 ? offset : offset - count
    }

    private func updateCounter() {
        counter.text = "\(current + 1)/\(cards.count)"
        counter.sizeToFit()
        counter.layer.cornerRadius = counter.bounds.height / 2
        positionCounter()
    }

    /// Top-trailing corner of the centre card, where Instagram puts it.
    private func positionCounter() {
        let size = cardSize
        let inset: CGFloat = 8
        counter.frame.origin = CGPoint(
            x: bounds.midX + size.width / 2 - counter.bounds.width - inset,
            y: bounds.midY - size.height / 2 + inset)
    }

    // MARK: Layout

    private var cardSize: CGSize {
        var height = bounds.height
        var width = height * aspect
        // A wide frame on a short stage: cap by width so the neighbours still peek.
        if width > bounds.width * 0.58 {
            width = bounds.width * 0.58
            height = width / aspect
        }
        return CGSize(width: width, height: height)
    }

    private func place(_ card: UIView, at slot: Int) {
        let size = cardSize
        let distance = abs(slot)
        let scale: CGFloat = distance == 0 ? 1 : Self.neighbourScale
        let neighbourWidth = size.width * Self.neighbourScale
        let first = size.width / 2 + Self.gap + neighbourWidth / 2
        let x: CGFloat
        switch distance {
        case 0: x = 0
        case 1: x = first
        default: x = first + neighbourWidth + Self.gap
        }
        card.center = CGPoint(x: bounds.midX + x * (slot < 0 ? -1 : 1), y: bounds.midY)
        card.transform = CGAffineTransform(scaleX: scale, y: scale)
        card.alpha = distance <= 1 ? 1 : 0
        if let index = cards.firstIndex(of: card) {
            shades[index].alpha = distance == 0 ? 0 : Self.neighbourShade
        }
        card.layer.zPosition = CGFloat(10 - distance)
    }

    /// The size the cards were last laid out for. Layout passes that do not
    /// change it (the cell's cross-fade forces several) must leave the deck
    /// alone, or they would snap a swipe that is still springing.
    private var laidOutSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        guard bounds.size != laidOutSize || cards.first?.bounds.size != cardSize else { return }
        laidOutSize = bounds.size
        let size = cardSize
        UIView.performWithoutAnimation {
            for (index, card) in cards.enumerated() {
                card.transform = .identity
                card.bounds = CGRect(origin: .zero, size: size)
                images[index].frame = card.bounds
                shades[index].frame = card.bounds
                card.layer.shadowPath = UIBezierPath(
                    roundedRect: card.bounds, cornerRadius: Theme.Radius.sm).cgPath
                place(card, at: slots.indices.contains(index) ? slots[index] : 0)
            }
            positionCounter()
        }
    }
}

// MARK: - Compare

/// A before/after wipe: the edited photograph, with the unedited one revealed
/// to the left of a divider that sweeps slowly back and forth.
@MainActor
final class HeroCompareStageView: UIView {

    private static let cycle: CFTimeInterval = 4.2
    private static let rest: CGFloat = 0.5

    private let afterView = UIImageView()
    private let beforeView = UIImageView()
    private let wipeMask = CALayer()
    private let divider = UIView()
    private let line = UIView()
    /// Fades the divider out over the bottom of the card, so it never runs
    /// through the caption's type.
    private let lineFade = CAGradientLayer()
    private let knob = UIView()
    private let beforePill = HeroCapsuleLabel()
    private let afterPill = HeroCapsuleLabel()
    private var isPlaying = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true

        for view in [afterView, beforeView] {
            view.contentMode = .scaleAspectFill
            view.clipsToBounds = true
            addSubview(view)
        }
        wipeMask.backgroundColor = UIColor.black.cgColor
        wipeMask.anchorPoint = CGPoint(x: 1, y: 0.5)
        beforeView.layer.mask = wipeMask

        line.backgroundColor = .white
        line.layer.shadowColor = UIColor.black.cgColor
        line.layer.shadowOpacity = 0.35
        line.layer.shadowRadius = 4
        divider.addSubview(line)

        knob.backgroundColor = .white
        knob.layer.shadowColor = UIColor.black.cgColor
        knob.layer.shadowOpacity = 0.3
        knob.layer.shadowRadius = 8
        knob.layer.shadowOffset = CGSize(width: 0, height: 3)
        let arrows = UIImageView(image: UIImage(
            systemName: "chevron.left.chevron.right",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)))
        arrows.tintColor = UIColor(white: 0.1, alpha: 1)
        arrows.contentMode = .center
        arrows.translatesAutoresizingMaskIntoConstraints = false
        knob.addSubview(arrows)
        NSLayoutConstraint.activate([
            arrows.centerXAnchor.constraint(equalTo: knob.centerXAnchor),
            arrows.centerYAnchor.constraint(equalTo: knob.centerYAnchor),
        ])
        divider.addSubview(knob)
        addSubview(divider)

        for (pill, text) in [(beforePill, String(localized: "Before")),
                             (afterPill, String(localized: "After"))] {
            pill.attributedText = NSAttributedString(
                string: text.uppercased(),
                attributes: [.kern: 1.2, .font: UIFont.systemFont(ofSize: 11, weight: .bold),
                             .foregroundColor: Theme.Color.textOnToast])
            pill.backgroundColor = UIColor.black.withAlphaComponent(0.45)
            pill.insets = UIEdgeInsets(top: 4, left: 9, bottom: 4, right: 9)
            pill.clipsToBounds = true
            pill.layer.cornerCurve = .continuous
            addSubview(pill)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(before: UIImage?, after: UIImage?) {
        stop()
        beforeView.image = before
        afterView.image = after
    }

    func play() {
        guard !isPlaying, HeroStageMotion.isAllowed, bounds.width > 0 else { return }
        isPlaying = true
        addSweep()
    }

    func stop() {
        isPlaying = false
        wipeMask.removeAllAnimations()
        divider.layer.removeAllAnimations()
    }

    /// One keyframe sweep shared by the mask and the divider so the two can
    /// never drift apart: out to the right, across to the left, home to rest.
    private func addSweep() {
        let width = bounds.width
        let values = [Self.rest, 0.8, 0.2, Self.rest].map { NSNumber(value: Double(width * $0)) }
        let ease = CAMediaTimingFunction(name: .easeInEaseOut)
        let sweep = CAKeyframeAnimation(keyPath: "position.x")
        sweep.values = values
        sweep.keyTimes = [0, 0.27, 0.77, 1]
        sweep.timingFunctions = [ease, ease, ease]
        sweep.duration = Self.cycle
        sweep.repeatCount = .infinity
        sweep.beginTime = CACurrentMediaTime() + 0.35
        wipeMask.add(sweep, forKey: "sweep")
        divider.layer.add(sweep, forKey: "sweep")
    }

    private var laidOutSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != laidOutSize else { return }
        laidOutSize = bounds.size
        afterView.frame = bounds
        beforeView.frame = bounds

        let restX = bounds.width * Self.rest
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wipeMask.bounds = CGRect(origin: .zero, size: bounds.size)
        wipeMask.position = CGPoint(x: restX, y: bounds.midY)
        CATransaction.commit()

        let knobSide: CGFloat = 32
        divider.bounds = CGRect(x: 0, y: 0, width: knobSide, height: bounds.height)
        divider.center = CGPoint(x: restX, y: bounds.midY)
        line.frame = CGRect(x: (knobSide - 2) / 2, y: 0, width: 2, height: bounds.height)
        lineFade.frame = line.bounds
        lineFade.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        lineFade.locations = [0, 0.52, 0.66]
        line.layer.mask = lineFade
        // A little above centre: the caption owns the bottom of the card.
        knob.frame = CGRect(x: 0, y: bounds.height * 0.42 - knobSide / 2,
                            width: knobSide, height: knobSide)
        knob.layer.cornerRadius = knobSide / 2

        let inset = Theme.Spacing.sm
        for pill in [beforePill, afterPill] {
            pill.sizeToFit()
            pill.layer.cornerRadius = pill.bounds.height / 2
        }
        beforePill.frame.origin = CGPoint(x: inset, y: inset)
        afterPill.frame.origin = CGPoint(x: bounds.width - afterPill.bounds.width - inset, y: inset)

        // A size change mid-sweep leaves the animation's absolute positions
        // behind; re-seat it for the new width.
        if isPlaying {
            wipeMask.removeAllAnimations()
            divider.layer.removeAllAnimations()
            addSweep()
        }
    }
}

// MARK: - Story chrome

/// The progress segments across the top of a story: the first fills over the
/// page's time on screen, which is what makes a tall frame read as a story
/// rather than as a narrow photograph.
@MainActor
final class HeroStoryChromeView: UIView {

    private static let segments = 3
    private var tracks: [UIView] = []
    private let fill = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        tracks = (0..<Self.segments).map { _ in
            let track = UIView()
            track.backgroundColor = UIColor.white.withAlphaComponent(0.4)
            track.layer.cornerRadius = 1.25
            track.clipsToBounds = true
            addSubview(track)
            return track
        }
        fill.backgroundColor = .white
        // Grows from the leading edge.
        fill.layer.anchorPoint = CGPoint(x: 0, y: 0.5)
        fill.layer.transform = CATransform3DMakeScale(0.5, 1, 1)
        tracks[0].addSubview(fill)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Fills the first segment over `duration`. Without motion the segment
    /// stands half full: a story in progress, not a broken bar.
    ///
    /// Animates a horizontal scale rather than the width, so the fill does not
    /// depend on the tracks having been laid out yet — `play()` can arrive
    /// before the first layout pass, and layout can run mid-fill.
    func play(duration: TimeInterval) {
        fill.layer.removeAnimation(forKey: "progress")
        guard HeroStageMotion.isAllowed, duration > 0 else { return setFraction(0.5) }
        setFraction(1)
        let progress = CABasicAnimation(keyPath: "transform.scale.x")
        progress.fromValue = 0
        progress.toValue = 1
        progress.duration = duration
        progress.timingFunction = CAMediaTimingFunction(name: .linear)
        fill.layer.add(progress, forKey: "progress")
    }

    func stop() {
        fill.layer.removeAnimation(forKey: "progress")
        setFraction(0.5)
    }

    private func setFraction(_ fraction: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.layer.transform = CATransform3DMakeScale(max(fraction, 0.0001), 1, 1)
        CATransaction.commit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let gap: CGFloat = 3
        let width = (bounds.width - gap * CGFloat(Self.segments - 1)) / CGFloat(Self.segments)
        for (index, track) in tracks.enumerated() {
            track.frame = CGRect(x: CGFloat(index) * (width + gap), y: 0, width: width, height: 2.5)
        }
        // Bounds and centre, not frame: the fill carries a scale transform.
        fill.bounds = CGRect(x: 0, y: 0, width: width, height: 2.5)
        fill.center = CGPoint(x: 0, y: 1.25)
    }
}

// MARK: - Before grade

/// The "before" half of a before/after wipe: the same photograph, flat and
/// dull the way a straight-off-the-camera frame looks next to an edit. Derived
/// rather than shipped, so the wipe always compares a photo with itself.
@MainActor
enum HeroCompareGrade {
    /// Graded once per photograph: the hero cell re-requests its frames every
    /// time it is reused, and a Core Image pass is not free on the main thread.
    private static let cache = NSCache<UIImage, UIImage>()

    static func before(from image: UIImage) -> UIImage? {
        if let cached = cache.object(forKey: image) { return cached }
        guard let graded = grade(image) else { return nil }
        cache.setObject(graded, forKey: image)
        return graded
    }

    /// `before(from:)`, with the Core Image pass run off the main actor — the
    /// hero's path, so a first launch does not grade a 1200px photo on the
    /// main thread while Home is appearing. Same cache, same result.
    static func beforeInBackground(from image: UIImage) async -> UIImage? {
        if let cached = cache.object(forKey: image) { return cached }
        let graded = await Task.detached(priority: .userInitiated) { grade(image) }.value
        if let graded { cache.setObject(graded, forKey: image) }
        return graded
    }

    nonisolated private static func grade(_ image: UIImage) -> UIImage? {
        guard let input = CIImage(image: image) else { return nil }
        let flattened = input
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.22,
                kCIInputContrastKey: 0.86,
                kCIInputBrightnessKey: 0.03,
            ])
            .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: -0.35])
            .applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 7600, y: 0),
            ])
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let output = context.createCGImage(flattened, from: input.extent) else { return nil }
        return UIImage(cgImage: output, scale: image.scale, orientation: image.imageOrientation)
    }
}

// MARK: - Capsule label

/// A label with insets, for the stage's small capsules ("1/4", "BEFORE").
private final class HeroCapsuleLabel: UILabel {
    var insets: UIEdgeInsets = .zero

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let base = super.sizeThatFits(CGSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: base.width + insets.left + insets.right,
                      height: base.height + insets.top + insets.bottom)
    }

    override var intrinsicContentSize: CGSize { sizeThatFits(.zero) }
}
