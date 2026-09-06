//
//  TextAnimation.swift
//  Caroullage
//
//  How a text overlay ENTERS and LEAVES its visible window, as distinct from
//  what it says (`TextOverlay`), how it is typeset (`TextOverlay`'s font
//  fields), and how it is presented against the footage (`TextStyle`).
//
//  RESERVED. Nothing reads this yet, deliberately: tier-3 animation gets its own
//  spec. It is defined now only so that shipping it later is a change to the two
//  render call sites — both already draw per frame — rather than a document
//  migration for every project saved in the meantime. See spec §4.1 and §7.
//
//  Adding a case here is safe in both directions: `TextOverlay` stores the raw
//  string, so a build that predates a new case falls back to `.none` for display
//  without destroying the value when it re-saves. See `TextOverlay.animation`.
//

import Foundation

public enum TextAnimation: String, Codable, Sendable, CaseIterable {
    /// The overlay simply appears at its in-point and disappears at its
    /// out-point. The only behaviour any build currently implements.
    case none
    /// Fade in and out.
    case fade
    /// Slide in from the edge nearest the overlay's frame.
    case slide
    /// Scale up past the final size and settle back.
    case pop
    /// Reveal one character at a time across the in-point.
    case typewriter
}
