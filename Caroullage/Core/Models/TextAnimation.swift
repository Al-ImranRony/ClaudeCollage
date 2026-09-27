//
//  TextAnimation.swift
//  Caroullage
//
//  How a text overlay ENTERS and LEAVES its visible window, as distinct from
//  what it says (`TextOverlay`), how it is typeset (`TextOverlay`'s font
//  fields), and how it is presented against the footage (`TextStyle`).
//
//  Reserved by the 2026-09-05 redesign and implemented by the video templates
//  work (2026-09-27). Every case is rendered through ONE pure function,
//  `TextAnimationMath.frame(for:at:)`, which both the live canvas and the
//  video export call — see that type for the timing rules.
//
//  Adding a case here is safe in both directions: `TextOverlay` stores the raw
//  string, so a build that predates a new case falls back to `.none` for display
//  without destroying the value when it re-saves. See `TextOverlay.animation`.
//

import Foundation

public enum TextAnimation: String, Codable, Sendable, CaseIterable {
    /// The overlay simply appears at its in-point and disappears at its
    /// out-point.
    case none
    /// Fade in and out.
    case fade
    /// Slide in from the edge nearest the overlay's frame.
    case slide
    /// Scale up past the final size and settle back.
    case pop
    /// Reveal one character at a time across the in-point.
    case typewriter
    /// Reveal one word at a time, each word snapping in — kinetic lyrics.
    case words
    /// Reveal one word at a time, each word fading in softly.
    case wordFade
}

public extension TextAnimation {
    /// The name a user sees for the preset. Kept apart from `rawValue`, which is
    /// the persisted form — the same split as `TextStyle.Kind.displayName`.
    var displayName: String {
        switch self {
        case .none: String(localized: "None")
        case .fade: String(localized: "Fade")
        case .slide: String(localized: "Rise")
        case .pop: String(localized: "Pop")
        case .typewriter: String(localized: "Typewriter")
        case .words: String(localized: "Word by Word")
        case .wordFade: String(localized: "Word Fade")
        }
    }
}
