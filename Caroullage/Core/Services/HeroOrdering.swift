//
//  HeroOrdering.swift
//  Caroullage
//
//  Home retention, phase 2 — the hero leads with what the user said they make.
//
//  Onboarding asks "what do you create most?" and, until now, the answer only
//  reordered the photo strip. The hero is the first thing on the screen and
//  rotates through one page per pillar; a user who said "carousels" should see
//  the carousel page first, not fourth. A stable partition, so within a kind
//  the manifest's authored order still holds.
//

import Foundation

enum HeroOrdering {

    /// The hero kind a creator kind leads with. `.fun` and no answer leave
    /// the manifest's order alone.
    static func preferredKind(for creatorKind: CreatorKind?) -> SampleContentManifest.HeroKind? {
        switch creatorKind {
        case .carousels: return .carousel
        case .reels: return .video
        case .pinterest: return .template
        case .fun, .none: return nil
        }
    }

    static func order(
        _ refs: [SampleContentManifest.HeroRef],
        for creatorKind: CreatorKind?
    ) -> [SampleContentManifest.HeroRef] {
        guard let preferred = preferredKind(for: creatorKind) else { return refs }
        return refs.filter { $0.kind == preferred } + refs.filter { $0.kind != preferred }
    }
}
