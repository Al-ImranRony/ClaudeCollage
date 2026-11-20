# Home sections redesign — design

Date: 2026-11-20 · Owner delegated every design decision ("act as a senior UI/UX engineer and decide").

## Intent

The hero was re-imagined to stage each kind of work the way it is used (video plays,
carousels deal out as a deck, tall work stands as a story frame). Everything below the
hero still used one card for everything: a 160 × 200 crop with the name printed on a
dark scrim. Six strips of the identical card read as a wall; carousels arrived as three
small pages floating on a muddy grey blur; 1:1 and 9:16 artwork was cropped to 4:5; two-line
headers ("For Reels / & Stories") broke the rhythm.

Goal: every strip clean, calm and distinct, carrying the hero's idea down the page —
**each kind of work presented in its own native shape** — with fresh hook copy.

## Goals / non-goals / anti-goals

- Goals: one shared caption system; per-kind card shapes; headers with a one-line hook;
  more air between sections; fresh copy and order.
- Non-goals: hero, create chips, Continue editing, Suggested For You, planner rules,
  See All targets, analytics, favourites behaviour.
- Anti-goals: anything that moves the first-screen fold (headers above the pill);
  extra motion competing with the hero (strip cards stay still, videos keep their
  existing gated loops); a crop that hides part of a collage.

## Approaches considered

1. **Restyle the existing card** (lighter scrim, bigger radius). Cheap, but keeps the
   one-card-for-everything monotony and the grey carousel bed. Rejected.
2. **Per-kind cards with captions below the artwork** (chosen). Matches the Collage
   gallery's `BrowseTemplateCell` (caption on the surface, not on the photo), lets each
   kind take its own shape, and removes every scrim from the strips.
3. **Mixed editorial layout** (one big feature tile + grid per section). Most magazine-like,
   but doubles the height of every section and fights the horizontal-strip pattern
   the rest of the app and the tests rely on. Rejected.

## The design

Card styles (`HomeCardStyle`), chosen per collection (`style` in `home_collections.json`,
defaulting by kind):

| Style | Used by | Artwork area | Treatment |
|---|---|---|---|
| poster | photo collections | 156 × 195 (4:5) | artwork shown **whole**, aspect-fit and mounted on a mat tinted from its own colour, soft shadow — a print in a frame |
| feature | in-season / pinned photo collection | 212 × 265 | the poster, larger: the season leads |
| story | "Stories & Reels" (9:16 templates) | 132 × 235 | full-bleed 9:16 with three story progress segments on top |
| reel | video collections | 132 × 235 | full-bleed looping video (existing gating), small play glyph |
| deck | carousel collections | 200 × 195 | the first slide in front, the next two stacked behind it, "1/5" counter |

Every card: name (subheadline, primary ink) + one meta line (caption, secondary ink)
**below** the artwork — "4 photos · 1:1", "Video · 9:16", "5 slides · 4:5". Lock and saved
badges stay where they were. Radius `Theme.Radius.lg` on the artwork, press scale as before.

Section header: title in `headline`-weight rounded 20pt on one line, a hook line in
`caption`/secondary beneath it, "See All" unchanged. Collections stack spacing 24 → 32.

Fresh copy: every collection gets a subtitle, and titles follow one editorial register —
short title-case noun phrases, the way the App Store names its shelves: Featured This Week,
Instagram Carousels, Stories & Reels, Pinterest Layouts, Celebrations, Minimalist, Travel,
Story Carousels, Panoramic Carousels, plus the three pillars. Season names stay bare
("Holiday Season", "Spring") because they also fill the reminder "New for …". Pillar item
orders refreshed so the first cards differ from the hero.

## Left to the builder

Exact mat tint maths, shadow values, and dark-mode mat shade — keep them on Theme tokens.
