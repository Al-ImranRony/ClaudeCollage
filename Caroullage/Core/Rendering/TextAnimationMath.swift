//
//  TextAnimationMath.swift
//  Caroullage
//
//  The SINGLE place a text overlay's animation is computed. `frame(for:at:)` is
//  a pure function of the overlay and a composition time, and both renderers
//  consume its result: the video export (`VideoOverlayRenderer` →
//  `TextRendering.draw`) and the live canvas (`TextOverlayView.applyAnimation`).
//  Neither renderer decides anything about timing, so the preview cannot drift
//  from the file.
//
//  Timing rules:
//   • The entrance runs from the overlay's in-point (`startTime ?? 0`).
//   • The exit — a short fade — runs only when there IS an out-point. An
//     unbounded caption holds its rest state to the end of the video.
//   • Per-word and per-character reveals spread across ~60% of the window, so a
//     short caption reveals quickly and a long one takes its time, clamped so a
//     reveal never crawls or flickers. An unbounded caption uses a fixed pace.
//   • A degenerate window (`end <= start`) is treated as unbounded, matching
//     `TextOverlay.isVisible(at:)`'s fail-open rule.
//

import CoreGraphics
import Foundation

/// The animated state of one text overlay at one instant.
public struct TextAnimationFrame: Equatable, Sendable {

    /// An alpha multiplier applied to a UTF-16 range of the overlay's text.
    /// Ranges not listed draw at full alpha.
    public struct RangeAlpha: Equatable, Sendable {
        public var location: Int
        public var length: Int
        public var alpha: CGFloat

        public init(location: Int, length: Int, alpha: CGFloat) {
            self.location = location
            self.length = length
            self.alpha = alpha
        }

        public var range: NSRange { NSRange(location: location, length: length) }
    }

    /// Whole-overlay opacity multiplier, 0…1.
    public var opacity: CGFloat
    /// Uniform scale about the overlay frame's centre.
    public var scale: CGFloat
    /// Translation as a fraction of the overlay frame's size (dx × width, dy × height).
    public var offset: CGVector
    /// Per-range glyph alpha, for word and character reveals.
    public var rangeAlphas: [RangeAlpha]

    public init(
        opacity: CGFloat = 1, scale: CGFloat = 1, offset: CGVector = .zero,
        rangeAlphas: [RangeAlpha] = []
    ) {
        self.opacity = opacity
        self.scale = scale
        self.offset = offset
        self.rangeAlphas = rangeAlphas
    }

    /// Fully shown, untransformed — what a caption with no animation always is.
    public static let rest = TextAnimationFrame()

    /// True when drawing this frame is identical to drawing no animation at all,
    /// so a renderer can take its ordinary path.
    public var isRest: Bool {
        opacity >= 1 && scale == 1 && offset == .zero && rangeAlphas.allSatisfy { $0.alpha >= 1 }
    }

    /// True when nothing would be drawn. Deliberately ignores `rangeAlphas`: a
    /// caption whose words have not revealed yet still paints its `.box` / `.pill`
    /// background, which is the label the words then appear on.
    public var isInvisible: Bool { opacity <= 0.001 }

    /// A coarsened copy for cache keys: two frames that would render to the same
    /// 8-bit pixels compare equal, so an export only re-renders when something
    /// visibly changed.
    public var quantized: TextAnimationFrame {
        func q(_ value: CGFloat, _ steps: CGFloat) -> CGFloat { (value * steps).rounded() / steps }
        return TextAnimationFrame(
            opacity: q(opacity, 128), scale: q(scale, 512),
            offset: CGVector(dx: q(offset.dx, 512), dy: q(offset.dy, 512)),
            rangeAlphas: rangeAlphas.map {
                RangeAlpha(location: $0.location, length: $0.length, alpha: q($0.alpha, 128))
            })
    }
}

public enum TextAnimationMath {

    // Tuned against the reference recordings (see the 2026-09-27 design doc).
    static let fadeIn: Double = 0.35
    static let riseIn: Double = 0.45
    static let popIn: Double = 0.4
    static let exitFade: Double = 0.3
    /// How far a rising caption starts below its rest position, as a fraction
    /// of its frame height. The frame clips it, so it reads as a mask reveal.
    static let riseDistance: CGFloat = 0.35
    static let wordSnapRamp: Double = 0.06
    static let revealShare: Double = 0.6
    static let wordPace: ClosedRange<Double> = 0.12 ... 0.45
    static let unboundedWordPace: Double = 0.3
    static let characterPace: ClosedRange<Double> = 0.03 ... 0.12
    static let unboundedCharacterPace: Double = 0.06

    /// The overlay's animated state at `time` seconds into the composition.
    /// Outside the overlay's window the result is fully transparent; callers
    /// normally skip those overlays via `TextOverlay.isVisible(at:)` anyway.
    public static func frame(for overlay: TextOverlay, at time: Double) -> TextAnimationFrame {
        let animation = overlay.animation
        guard animation != .none else { return .rest }

        let start = overlay.startTime ?? 0
        let end: Double? = {
            guard let end = overlay.endTime, end > start else { return nil }
            return end
        }()
        let local = time - start
        guard local >= 0 else { return TextAnimationFrame(opacity: 0) }
        let window = end.map { $0 - start }

        var frame = TextAnimationFrame()
        switch animation {
        case .none:
            return .rest
        case .fade:
            frame.opacity = CGFloat(easeOut(progress(local, over: fadeIn)))
        case .slide:
            let p = easeOut(progress(local, over: riseIn))
            frame.opacity = CGFloat(min(1, p * 1.6))
            frame.offset = CGVector(dx: 0, dy: riseDistance * CGFloat(1 - p))
        case .pop:
            let p = progress(local, over: popIn)
            frame.opacity = CGFloat(min(1, p / 0.4))
            frame.scale = CGFloat(popScale(p))
        case .typewriter:
            let units = characterUnits(in: overlay.text)
            let pace = pace(count: units.count, window: window,
                            clamp: characterPace, unbounded: unboundedCharacterPace)
            frame.rangeAlphas = reveal(units, local: local, pace: pace, ramp: 0.02)
        case .words, .wordFade:
            let units = wordUnits(in: overlay.text)
            let pace = pace(count: units.count, window: window,
                            clamp: wordPace, unbounded: unboundedWordPace)
            let ramp = animation == .words ? wordSnapRamp : max(0.12, pace * 1.2)
            frame.rangeAlphas = reveal(units, local: local, pace: pace, ramp: ramp)
        }

        if let end {
            let remaining = end - time
            let exit = min(exitFade, (window ?? exitFade) * 0.25)
            if remaining < exit, exit > 0 {
                frame.opacity *= CGFloat(max(0, remaining / exit))
            }
        }
        return frame
    }

    /// How long the entrance takes to finish, from the in-point — when a caller
    /// wants to replay it (e.g. the editor previewing a newly chosen animation).
    public static func entranceDuration(for overlay: TextOverlay) -> Double {
        let start = overlay.startTime ?? 0
        let window: Double? = overlay.endTime.flatMap { $0 > start ? $0 - start : nil }
        switch overlay.animation {
        case .none: return 0
        case .fade: return fadeIn
        case .slide: return riseIn
        case .pop: return popIn
        case .typewriter:
            let count = characterUnits(in: overlay.text).count
            return Double(max(0, count - 1)) * pace(count: count, window: window,
                                                   clamp: characterPace,
                                                   unbounded: unboundedCharacterPace) + 0.02
        case .words, .wordFade:
            let count = wordUnits(in: overlay.text).count
            let pace = pace(count: count, window: window, clamp: wordPace, unbounded: unboundedWordPace)
            let ramp = overlay.animation == .words ? wordSnapRamp : max(0.12, pace * 1.2)
            return Double(max(0, count - 1)) * pace + ramp
        }
    }

    // MARK: - Units

    /// Whitespace-separated runs, as UTF-16 ranges — punctuation stays attached to
    /// its word ("videos." reveals as one), unlike `.byWords` enumeration.
    static func wordUnits(in text: String) -> [NSRange] {
        let ns = text as NSString
        var ranges: [NSRange] = []
        var runStart: Int?
        let whitespace = CharacterSet.whitespacesAndNewlines
        for index in 0 ..< ns.length {
            let unit = ns.character(at: index)
            let isSpace = UnicodeScalar(unit).map { whitespace.contains($0) } ?? false
            if isSpace {
                if let start = runStart {
                    ranges.append(NSRange(location: start, length: index - start))
                    runStart = nil
                }
            } else if runStart == nil {
                runStart = index
            }
        }
        if let start = runStart { ranges.append(NSRange(location: start, length: ns.length - start)) }
        return ranges
    }

    /// Composed characters (so an emoji or accented letter reveals whole),
    /// skipping whitespace, which has nothing to reveal.
    static func characterUnits(in text: String) -> [NSRange] {
        let ns = text as NSString
        var ranges: [NSRange] = []
        ns.enumerateSubstrings(
            in: NSRange(location: 0, length: ns.length), options: .byComposedCharacterSequences
        ) { substring, range, _, _ in
            guard let substring, !substring.allSatisfy(\.isWhitespace) else { return }
            ranges.append(range)
        }
        return ranges
    }

    // MARK: - Helpers

    private static func pace(
        count: Int, window: Double?, clamp: ClosedRange<Double>, unbounded: Double
    ) -> Double {
        guard count > 0 else { return unbounded }
        guard let window else { return unbounded }
        let spread = window * revealShare / Double(count)
        return min(clamp.upperBound, max(clamp.lowerBound, spread))
    }

    private static func reveal(
        _ units: [NSRange], local: Double, pace: Double, ramp: Double
    ) -> [TextAnimationFrame.RangeAlpha] {
        units.enumerated().map { index, range in
            let begin = Double(index) * pace
            let alpha = easeOut(progress(local - begin, over: ramp))
            return .init(location: range.location, length: range.length, alpha: CGFloat(alpha))
        }
    }

    private static func progress(_ elapsed: Double, over duration: Double) -> Double {
        guard duration > 0 else { return elapsed >= 0 ? 1 : 0 }
        return min(1, max(0, elapsed / duration))
    }

    private static func easeOut(_ p: Double) -> Double {
        let inverse = 1 - p
        return 1 - inverse * inverse * inverse
    }

    /// 0.6 → overshoot 1.06 at 70% → settle at 1.
    private static func popScale(_ p: Double) -> Double {
        if p < 0.7 {
            return 0.6 + 0.46 * easeOut(p / 0.7)
        }
        return 1.06 - 0.06 * easeOut((p - 0.7) / 0.3)
    }
}
