# Home Showcase Redesign — Design Spec

**Date:** 2026-08-29
**Status:** Approved (owner, 2026-08-29)
**Goal:** Rebuild the Home tab from a schematic "dev-mode" landing screen into a
photo-real template showcase that competes with Prequel/SCRL/Unfold — built
around the app's three pillars: **Photo Collage, Video Collage, Carousel**.

## Problem

Home today shows featured templates as empty layout schematics ("+" chips) and
four icon quick-start tiles. Users never see what the app can *produce*. Top
competitors sell the outcome: every template preview is filled with real,
aspirational photography, and tapping one drops you into an editor shaped like
what you just saw.

## The hook contract

> The user taps a template that looks like a finished, beautiful post. The
> editor opens with that template's exact structure — photo zones **empty**,
> text zones prefilled — and when they add their own photos, the result matches
> what they were shown.

This is guaranteed structurally: showcase previews are rendered through the
**same `CollageRenderer` the editor and exporter use**, with sample photos
composited into the template's real zones. Preview fidelity is not a promise, it
is the pipeline.

## Owner decisions (locked)

1. **Sample photos: curated licensed stock (Pexels).** Real, cute, engaging
   model/lifestyle photography. **No recognizable actresses or celebrities** —
   bundling a real person's likeness to market an app violates right-of-publicity
   law and risks App Store rejection. Licensed model-released stock delivers the
   same aspirational look legally. Attribution shipped in `ATTRIBUTION.md`.
2. **Video previews: looping motion**, via pre-baked bundled loops (not runtime
   composition). Reduce Motion / Low Power Mode fall back to poster frames.
3. **Pillars: Photo Collage, Video Collage, Carousel** ("SCRL templates" =
   carousel templates).

## Architecture

### 1. Sample content system

New bundle directory `Caroullage/Resources/SampleContent/`:

- **~25 curated photos** (portraits, couples, friends, travel, food, seasonal),
  downsampled to ~1200px JPEG, ~150–250KB each. Filenames by subject:
  `sample_portrait_01.jpg`, `sample_couple_01.jpg`, `sample_travel_01.jpg`, …
- **`ATTRIBUTION.md`** — per-photo photographer credit, source URL, license.
- **3–4 baked video loops** (`sample_loop_*.mp4`, 2–3s, muted, H.264, ~1MB each)
  plus matching poster JPEGs. Authored in dev from licensed Pexels stock *video*
  composited into real video-collage layouts.
- **`sample_content_manifest.json`** — schema:
  ```json
  {
    "version": 1,
    "templates": {
      "<templateID>": { "photos": ["sample_portrait_01", "sample_travel_02"] }
    },
    "carousels": {
      "<carouselTemplateID>": { "framePhotos": [["a"], ["b"], ["c"]] }
    },
    "videoShowcases": [
      { "id": "duo-motion", "loop": "sample_loop_duo", "poster": "sample_loop_duo_poster",
        "title": "Duo Motion", "layoutID": "<GridTemplate id>" }
    ],
    "hero": ["<entry refs, one per pillar minimum>"]
  }
  ```
  Photo lists are ordered to match the template's photo zones in declaration
  order; art-directed so faces land in dominant zones.

New service **`SampleContentCatalog`** (`Core/Services/`):
- Loads and validates the manifest; resolves asset names to `UIImage`/file URLs.
- Answers: `samplePhotos(for template:)`, `sampleFrames(for carousel:)`,
  `videoShowcases`, `heroEntries`.
- Missing/mismatched entries degrade per-item (that card falls back to the
  existing schematic thumbnail) — never crash, never blank the section.

**Preview rendering** — `TemplateService` grows:
- `showcasePreview(for: CollageTemplate) -> CGImage?` — builds a render request
  with sample photos filled into photo zones, renders via `CollageRenderer`,
  disk-caches as `showcase_<templateID>_v<manifestVersion>.png` alongside the
  existing thumbnail cache (same eviction story; version bump invalidates).
- `showcasePreview(for: CarouselTemplate) -> CGImage?` — composites the first
  three frames side by side (all frames when the template has fewer), first
  frame dominant, small gaps, so the multi-frame idea reads at card size.

### 2. Home screen structure (top → bottom)

1. **Hero showcase** — near-full-width ~4:5 card, cycling 4–5 flagship entries
   (≥1 per pillar; the video entry plays its loop). Bottom gradient scrim with
   template name + "Tap to create". Auto-advance ~4s with cross-fade; page dots;
   pauses while touched; swipeable. **Reduce Motion:** no auto-advance, no
   cross-fade — swipe only. Rotation logic lives in a timer-injectable
   `HeroRotationController` (plain object, unit-testable).
2. **"Photo Collages"** — horizontal strip of `ShowcaseTemplateCell`
   (~160pt wide, ~200pt image + name; photo-filled preview, premium lock badge
   via existing `canOpen`, spring press-down per existing card pattern).
   "See All" → template gallery (existing route).
3. **"Video Collages"** — same card size; `LoopingPreviewPlayerView` cards
   (AVPlayerLooper, muted, plays only while on screen; poster shows instantly
   and is the permanent state under Reduce Motion / Low Power Mode). Play badge.
   "See All" → video creation flow.
4. **"Carousels"** — cards use the multi-frame composite preview + frame-count
   badge ("4 frames"). "See All" → carousel start screen.
5. **"Suggested For You"** — existing suggestions row moves below the pillars,
   otherwise unchanged (same access gating).
6. **Quick-start chip row** — the four `QuickStartTile` rows compress into one
   compact horizontal chip row (Grid · Shapes · Video · Carousel). The "+" sheet
   remains the primary creation-by-type surface.

All spacing/color/type from existing `Theme` tokens; dark + light first-class.

### 3. Tap → editor routing

- Photo card / photo hero page → existing `AppCoordinator.openTemplate(_:)`
  (grid editor, photo zones empty, text prefilled). **Unchanged.**
- Carousel card → carousel editor seeded with that `CarouselTemplate`, frames
  empty, through the existing carousel start/template path.
- Video card → video editor with the showcase's `layoutID` preselected, cells
  empty → picker.
- Every route is a closure wired by `AppCoordinator`, matching the current
  Home wiring style.

### 4. Performance & footprint

- Previews render off the first layout pass and disk-cache (existing thumbnail
  pattern) — cold launch never blocks on compositing.
- Video: max 2 loops decode simultaneously (only on-screen cells play).
- Bundle budget: ~25 photos (~5MB) + 4 loops + posters (~5MB) ≈ **~10MB**.

## Error handling

- Manifest missing/corrupt → Home falls back to current schematic thumbnails
  wholesale (the section structure still renders).
- Individual asset missing → that card falls back to its schematic thumbnail.
- Video asset fails to load → poster frame persists (no spinner, no gap).

## Testing

**Unit / integration (sim-safe):**
- Manifest integrity: every referenced asset exists in the bundle; every
  showcased template ID exists in the parsed catalogs; photo counts match each
  template's photo-zone count (frame-by-frame for carousels).
- `SampleContentCatalog` resolution + per-item degradation.
- Showcase preview cache keying and version invalidation.
- `HeroRotationController`: advance, pause-on-touch, resume, Reduce Motion off-switch.

**UI tests:**
- Home shows hero + the three pillar sections (identifiers:
  `heroShowcase`, `photoShowcaseStrip`, `videoShowcaseStrip`,
  `carouselShowcaseStrip`, `quickStartChipRow`).
- Tapping a card in each pillar lands in the correct editor with empty content.
- Existing Home tests updated: `featuredTemplateStrip` and the old quick-start
  tile identifiers are replaced (expected churn).

**Device QA (not sim-testable):** loop playback smoothness, hero cross-fade
feel, thermal/battery sanity with loops playing.

## Licensing & compliance

- All bundled people photography: Pexels-licensed, model-released-style stock.
  Pexels license permits commercial app use without attribution; we ship
  `ATTRIBUTION.md` regardless.
- No celebrity/actress likenesses, ever.
- Photos are curated for the app's tone: cute, warm, aspirational — the
  Prequel/SCRL energy — without identifiable public figures.

## Out of scope

- Server-delivered template/preview packs (all content is bundled).
- New template authoring (showcases dress the *existing* catalogs).
- Redesign of the Template Gallery or Projects tabs (Home only; the gallery
  may adopt showcase previews in a later step).
- Runtime video composition for previews.
