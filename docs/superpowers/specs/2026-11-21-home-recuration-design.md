# Home re-curation for the new Collage and Carousel content (2026-11-21)

The Collage tab redesign (26 new looks: instant, film, editorial, photo dump,
soft grids) and the SCRL-style carousels shipped, but Home still curated only
the legacy catalog — the Collage spec listed it as a follow-up. Home is the
first screen, so it has to hook with the content the tabs now lead with.

This is a curation change only: JSON and the manifest's hero list. No layout,
planner or card code changed.

## Hero (`sample_content_manifest.json` → `hero`)

| Before | After |
|---|---|
| video Travel Filmstrip | video Travel Filmstrip |
| carousel Team (deck) | **carousel Film Frames (deck)**: the SCRL-style flagship |
| video Title Grid | **template Instant Trio**: the Collage tab's spotlight lead |
| template Story Caption Hero | video Title Grid |
| video Quad Motion | **template Editorial Issue**: the magazine-cover trend |
| carousel Before/After (compare) | carousel Before/After (compare) |

Quad Motion went: its loop is itself a generic collage, and it was the weakest
page. The lineup still opens on video, never plays two videos back to back,
and no kind outnumbers video (`HeroStageTests`). Film Frames got `frameTexts`
holding its own authored copy ("ROLL 01"), so the dressed-copy guard holds and
the rendered frames don't change.

## Collections (`home_collections.json`, version 3)

- **New: Trending Now** (`trending`). Pinned and badged NEW, priority 5, so it
  sits under the season's strip. It mirrors the Collage tab's spotlight and
  Trending shelf, and its See All lands on All, where the tab opens on exactly
  those. It is a weekly pick of 6 from 18. The list is ordered so every
  week's six are 4 free cards and 2 locked, free first. It reuses the
  Collage shelf's translated title and subtitle.
- **Replaced: Featured This Week.** It was a weekly pick of legacy templates.
  Trending is the weekly strip now.
- **New rotating strips** that mirror the Collage tab's shelves: Instant &
  Booth, Shot on Film, Editorial, Photo Dump. Each reuses its shelf's
  translated copy, and See All lands on its chip.
- **Seasons refreshed.** Holiday now leads with Friendsgiving, Cozy, Holiday
  Booth and Year in Frames. Autumn, Spring and Summer each mix in the new looks
  that fit them.
- **Affinity and theme strips refreshed.** Stories & Reels, Pinterest,
  Minimalist, Travel and Celebrations each lead with their new looks.
- **Pillars.** Photo Collages is now all free cards (soft grids, white space,
  classics), kept apart from Trending so the two never fight over cards. The
  Carousels pillar now leads with Menu (free) instead of Film Frames, which
  the hero claims.
- **`featuredTemplates`** (the pillar's top-up pool and the no-file fallback)
  now lists free new looks.

The cap on curated strips stays at three, so Home is no longer than before.
On a default launch in the holiday window, Home shows: Holiday Season, then
Trending Now (NEW), then one affinity or rotating strip, then the three
pillars.

## Guards

- `HomeCollectionCatalogTests.testHomeFeaturesTheCollageTabsNewLooksAllYear`:
  Trending is on Home every week of the year for every onboarding answer. Its
  items are all Collage-tab new looks, and the hero stages at least one of
  them.
- `testEveryPillarLeadsWithAFreeCardAllYear`: each pillar's first card (the
  one the UI suites tap) opens rather than raising the paywall, whichever
  strips claimed cards above it.
- The existing all-year distinctness test passes on the new file: no card
  shows twice, every strip has at least 4 cards, and there are 2 to 3 curated
  strips.
