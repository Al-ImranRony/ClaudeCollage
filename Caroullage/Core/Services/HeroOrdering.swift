//
//  HeroOrdering.swift
//  Caroullage
//
//  Home retention, phase 2 — the hero leads with what the user said they make.
//
//  Onboarding asks "what do you create most?" and, until now, the answer only
//  reordered the photo strip. The hero is the first thing on the screen and
//  rotates through one page per pillar; a user who said "carousels" should see
//  the carousel page first, not fourth.
//
//  The hero loops, and the manifest is authored as a loop: kinds alternate,
//  and no two videos ever play back to back (see `HeroStageTests`). So the
//  answer ROTATES that loop to start at the first page of the preferred kind
//  rather than pulling every page of that kind to the front. A partition put
//  a reels maker's two videos back to back, and a carousel maker's deck and
//  wipe side by side. A rotation keeps every neighbour the manifest chose,
//  and the kind's own pages keep their authored order.
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
        guard let preferred = preferredKind(for: creatorKind),
              let start = refs.firstIndex(where: { $0.kind == preferred })
        else { return refs }
        return Array(refs[start...] + refs[..<start])
    }
}
