# Carousel Tab → Carousel Template Gallery — Design Spec

**Date:** 2026-08-31
**Status:** Approved (owner, 2026-08-31)
**Goal:** Replace the Carousel tab's duplicate saved-project gallery with a
browsable catalog of the **20 bundled carousel templates**, laid out in the
SCRL storefront idiom: titled sections, a staggered masonry grid of photo-real
cards at their true aspect ratios, and a metadata caption under each card.

## Problem

The Carousel tab is `ProjectsViewController(configuration: .carousels)` — the
Projects grid with `modeFilter: .carousel` ([AppCoordinator.swift:95]). Every
card it shows is already on the Projects tab. The tab costs a slot in a
four-tab bar and returns nothing the user cannot get one tab over.

Meanwhile the app ships **20 carousel templates** in
`Resources/CarouselTemplates/` that **no browse surface exposes**. Home's
Carousels strip shows 6 of them; the other 14 are reachable only by accident.
"See All" on that strip does not open a gallery at all — it opens the *type
picker* sheet, because (per the comment at `AppCoordinator.swift:63`) "there is
no carousel-template gallery yet."

This spec builds that gallery, and gives it the tab.

## Owner decisions (locked)

1. **Saved carousels are dropped from the tab entirely.** They live on Projects,
   which already lists them and whose **"By type"** sort groups them together.
   Nothing is lost; the duplication is.
2. **Layout follows SCRL.** Titled sections with a `›` chevron, staggered
   masonry, photo-real cards at real aspect ratios, metadata caption under each
   card. (Reference screenshots are SCRL's Home tab, supplied by the owner.)
3. **All 20 templates get photo-real previews.** Dress the remaining 14 in the
   sample-content manifest, plus a schematic wireframe fallback so a card can
   never render blank.
4. **Filters are carousel *type* + canvas ratio.** Type (Panoramic / Matched /
   Scroll-Through / Grid Preview) is what actually changes what you get;
   category (travel/story/product/…) is decoration and is not surfaced.
5. **Chips collapse the sections.** "All" shows four titled sections; selecting
   a type chip — or tapping a section's `›` — collapses to one flat masonry
   grid of that type. No navigation push.
6. **Card preview is the cover page + page dots**, not the three-page strip.
7. **No promo banner.** The screen opens straight into the catalog; Home already
   owns the app's rotating hero.

## What already exists (and is reused unchanged)

The engine work is done. This is a surfacing task.

- **All 20 templates parse and open today.** `CarouselService.buildCarousel(from:)`
  maps any template's frames onto editable `CarouselFrame`s, and every one of
  the 20 has real `frames` in its JSON (verified). `openCarouselTemplate` in
  `AppCoordinator` already drives this for Home's 6.
- **`MasonryLayout`** ([Core/Rendering/MasonryLayout.swift]) is a pure,
  unit-tested function over aspect ratios that returns placed frames and a
  total height. It already backs the Projects grid via
  `NSCollectionLayoutGroup.custom`. The staggered layout is free.
- **`CollageRenderer`** renders carousel frames dressed in sample photography
  via `TemplateService.renderCarouselFrame(_:photos:of:maxDimension:)`, using
  the editor's own layout mapper — so a preview is structurally the page the
  editor opens.
- **`FilterMenuChip`** and **`CategoryChipCell`** are existing design-system
  components; the Templates tab's chip row is the pattern to follow.
- **`TopFadeView.install(in:above:)`** is the established treatment for content
  scrolling under pinned filter controls.

### The catalog, as authored

| Type | Templates | Ratios |
|---|---|---|
| Panoramic | 5 | 4:5 ×3, 9:16, 16:9 |
| Matched | 6 | 1:1 ×3, 4:5 ×2, 9:16 |
| Scroll-Through | 5 | 4:5 ×2, 9:16 ×3 |
| Grid Preview | 4 | 1:1 ×3, 4:5 |

4 of the 20 are premium: `carousel-gridpreview-6cell`, `carousel-matched-quotes`,
`carousel-panoramic-city`, `carousel-story-travel`.

## Architecture

### 1. Screen: `CarouselGalleryViewController`

New file, `Caroullage/Features/CarouselGallery/`. A tab root, so
`navigationItem.title` — **never** `title`, which rewrites the tab bar label
(the documented tab-root title trap).

```
╔═══════════════════════════════════╗
║  Carousels                    New ║  large title + trailing bar button
║  🔍 Search carousels              ║  UISearchController on template name
╟───────────────────────────────────╢
║ [Any Ratio ▾] │ [All][Panoramic]  ║  pinned: ratio menu chip │ divider │ chips
╟───────────────────────────────────╢
║  Panoramic                      › ║  section header
║  ┌────────┐  ┌──────────────┐     ║
║  │▓▓▓▓▓▓▓▓│  │▓▓▓▓▓▓▓▓▓▓▓▓▓▓│     ║  masonry, real aspect ratios
║  │▓ ●○○ ─│  │▓▓▓ ●○○ ──────│     ║  page dots overlaid
║  └────────┘  └──────────────┘     ║
║   Shoreline   Skyline Strip       ║
║   ⬚ Story 🖼4 ▤4  ⬚ Landscape …  ║  caption: ratio · photos · pages
║  Matched                        › ║
╚═══════════════════════════════════╝
```

**Layout.** `UICollectionViewCompositionalLayout` with a section-provider
closure, exactly as `ProjectsViewController.makeMasonrySection` does. Each
visible section builds its own `NSCollectionLayoutGroup.custom` from
`MasonryLayout.frames(aspectRatios:columns:2:containerWidth:spacing:captionHeight:)`.
A boundary supplementary item carries the section header. The section provider
must be rebuilt on invalidation, not configured once — a masonry section's
height depends on the items it is laying out, which change with every filter
and search keystroke.

**Section model.** One section per `CarouselType` when the type chip is "All";
a single unheadered section when a type is selected. Sections whose filtered
content is empty are omitted entirely rather than rendered as a bare header.

**Chevron behaviour.** A section header's `›` selects that type's chip. It does
not push. This keeps the tab a single screen and means the header and the chip
row can never disagree about what is being shown.

**Search** narrows within the current type and ratio, on `template.name`.

**Empty state.** When filters match nothing, a centred label in the manner of
the Templates tab's `galleryEmptyLabel` — not `HomeEmptyStateView`, which is
built for "you have made nothing yet" and would be wrong on a screen whose
content is bundled and therefore never absent.

**Creation door.** A trailing `New` bar button opens
`presentCarouselTypePicker()` — the existing sheet. This preserves the path to a
blank carousel that the tab's old empty state provided. A **bar button**
specifically, not a filled CTA: the Step 06 defect was two competing filled
brand-orange CTAs on this tab, and that must not return.

### 2. The ratio chip defaults to "Any Ratio" — a deliberate divergence

The Templates tab's `CanvasPreset` chip is a hard filter with no "any" case and
defaults to `.square`. Applied here that would be wrong twice:

- **Coverage.** Square matches 6 of 20 and Landscape matches exactly **1**.
  Opening the tab pre-filtered to Square hides 70% of the catalog behind a
  control the user has no reason to touch.
- **Look.** A single-ratio filter makes every card the same shape, which
  flattens the masonry back into a plain uniform grid — losing the exact quality
  that motivated the redesign.

So the Carousel gallery's ratio filter is `CanvasPreset?`, `nil` = "Any Ratio",
and `nil` is the default. The chip still offers all four presets. The Templates
tab is **not** changed.

### 3. Preview rendering

Two additions to `TemplateService`. Neither replaces `showcasePreview(for:)` —
Home's wide strip cards still want the three-page composite.

```swift
/// Frame 1 alone, at the template's true canvas aspect ratio, dressed in its
/// manifest sample photos. The masonry card's preview: a 9:16 template must
/// produce a tall image and a 1:1 a square one, or the grid has nothing to
/// stagger.
func showcaseCover(for template: CarouselTemplate,
                   sampleContent: SampleContentCatalog = .shared,
                   maxDimension: CGFloat = 480) -> CGImage?

/// A wireframe strip in the manner of `thumbnail(for:)` — zone outlines on the
/// cell well, no photography. The safety net for a template whose sample photos
/// fail to resolve.
func schematicCover(for template: CarouselTemplate,
                    maxDimension: CGFloat = 480) -> CGImage?
```

`showcaseCover` reuses the existing private `renderCarouselFrame(_:photos:of:maxDimension:)`
verbatim — the geometry path stays single-sourced through
`TemplateService.editorLayout`.

Note that `MasonryLayout` clamps card height to 0.68–1.55× width, so the two
extreme ratios are cropped by the card rather than laid out at true proportion:
a 9:16 cover (1.78) is clamped to 1.55 and a 16:9 cover (0.5625) to 0.68, each
losing ~13–17% to `.scaleAspectFill`. This is the existing, deliberate contract
— it is what keeps a panorama from becoming a sliver — and it is why the cover
is rendered at true ratio and cropped by the card, rather than rendered
pre-clamped. Cache keys follow the established shape
(`"cover-carousel-<id>-s<manifestVersion>-r<rendererRevision>@<dimension>"`) so
a re-authored manifest or a renderer revision invalidates both memory and disk
caches.

The **card** falls back `showcaseCover` → `schematicCover`, so it cannot render
empty. Home's existing `showcasedCarouselTemplates()` "no fallback" rule is
untouched: it is about which carousels Home *features*, not about how a card
degrades.

### 4. Card: `CarouselTemplateCardCell`

New design-system component. `ShowcaseTemplateCell` is a sibling, not a base
class: it burns the name **over** the image on a scrim and has no metadata row,
which is a different card.

```
┌──────────────┐
│▓▓▓▓▓▓▓▓▓▓▓▓▓▓│  cover, .scaleAspectFill, Theme.Radius.lg, clipped
│▓▓▓▓▓▓▓▓▓▓▓▓▓▓│  premium lock badge, top-right (reuse ShowcaseTemplateCell's)
│▓▓▓ ● ○ ○ ▓▓▓│  page dots, bottom-centre, over a short scrim
└──────────────┘
 Skyline Strip     name, one line, truncating
 ⬚ Landscape 🖼3 ▤3   ratio · photo count · page count
```

**Metadata**, matching the reference screenshots' `⬚ Portrait 🖼8 ▤4`:

| Field | Source |
|---|---|
| Ratio | `CanvasPreset(aspectRatio: template.canvasAspectRatio)?.displayName` |
| Photos | total `.photo` zones summed across all frames |
| Pages | `template.frameCount` |

Both counts derive from data already parsed. `carousel-gridpreview-4cell` has
photo zones `[4,1,1,1,1]` → **8 photos, 5 pages**, which is exactly the
reference format.

**Page dots** are capped at a readable maximum (7, matching the longest
template, `gridpreview-6cell`); the dot row is drawn, not a `UIPageControl`,
so it can sit over artwork without importing the control's own styling.

**Caption height is fixed** (`MasonryLayout`'s `captionHeight` parameter) so
captions align across a row even though the thumbnails above them do not — the
existing contract, honoured.

### 5. Sample content: dress the remaining 14

`sample_content_manifest.json` gains `framePhotos` entries for the 14 undressed
templates. **Zero new assets** — all 20 fit within the 24 photos already
bundled. The largest single requirement is 6 (frame 1 of
`carousel-gridpreview-6cell`); every other frame needs 1–4.

Photo selection follows subject family, so a preview reads as one coherent post:
food templates take `sample_food_*`, travel takes `sample_travel_*`, people take
portraits/friends/couple. `renderCarouselFrame` requires
`photos.count == photoCells.count` **exactly**, per frame — the manifest must be
authored against each template's real per-frame photo-zone counts, which are:

```
gridpreview-4cell   [4,1,1,1,1]    matched-menu     [1,1,1,1]
gridpreview-6cell   [6,1,1,1,1,1,1] matched-product  [1,1,1,1]
gridpreview-family  [4,1,1,1,1]    matched-quotes   [1,1,1]
gridpreview-travel  [4,1,1,1,1]    matched-steps    [1,1,1,1,1]
panoramic-beach     [1,1,1,1]      matched-team     [1,1,1,1]
panoramic-city      [1,1,1]        matched-tips     [1,1,1,1,1]
panoramic-skyline   [1,1,1]        story-beforeafter[1,1]
panoramic-sunset    [1,1,1,1,1]    story-lessons    [1,1,1,1,1]
panoramic-travel    [1,1,1]        story-recipe     [1,1,1,1]
                                   story-travel     [1,1,1,1]
                                   story-tutorial   [1,1,1,1,1]
```

The manifest `version` is bumped, which invalidates every cached carousel
preview through the existing cache-key contract.

### 6. Home's curation must become explicit — required, not optional

`HomeViewController.showcasedCarouselTemplates()` returns
`all.filter { manifest.carousels.keys.contains($0.id) }`. Home therefore shows
**whatever happens to be dressed**. Dressing the other 14 would silently take
Home's Carousels strip from 6 cards to 20 — a change to a screen this work is
not supposed to touch.

So the manifest gains an ordered, optional list:

```json
"featuredCarousels": [
  "carousel-matched-team", "carousel-matched-menu", "carousel-matched-tips",
  "carousel-matched-steps", "carousel-story-beforeafter",
  "carousel-gridpreview-family"
]
```

`SampleContentManifest` decodes it as `[String]?`; `SampleContentCatalog`
exposes `featuredCarouselIDs`. Home resolves against it in the manifest's order
and **falls back to today's behaviour** (every dressed carousel) when the key is
absent. Seeded with exactly the 6 Home shows today, so Home is byte-for-byte
unchanged by this work — and its curation stops being an accident of which
templates happened to have photos.

### 7. Premium gating — an existing bug this work must close

`TemplateService.canOpen(_:)` and `isPremium(_:)` exist only for
`CollageTemplate`. `HomeViewController.carouselCard` passes no `locked:` and
`AppCoordinator.openCarouselTemplate` performs no entitlement check, so
**`Trip Diary`, `Quote Set`, `City Sweep` and `Grid Reveal 6` open free from
Home today** despite `"isPremium": true` in their JSON.

Add the overloads:

```swift
func isPremium(_ template: CarouselTemplate) -> Bool
func canOpen(_ template: CarouselTemplate) -> Bool
```

Both the new gallery and Home's carousel card then show the lock badge and route
a locked tap to the paywall — the Templates tab's exact pattern
(`presentPaywall { … }` on `Haptics.boundary()`, then open on unlock). Fixing
this in the gallery while leaving Home open would be shipping two answers to one
question, so Home's card is updated in the same change.

### 8. Wiring (`AppCoordinator`)

```swift
let carousels = CarouselGalleryViewController(service: .shared)
carousels.onSelectTemplate  = { [weak self] in self?.openCarouselTemplate($0) }
carousels.onNewCarousel     = { [weak self] in self?.presentCarouselTypePicker() }
```

- Tab item is unchanged: `rectangle.stack.fill`, identifier `carouselButton`.
- `home.onBrowseCarousels` changes from `presentCarouselTypePicker()` to
  selecting the Carousel tab — "See All" finally means see all. The
  `// There is no carousel-template gallery yet` comment is deleted with it.
- `loadBundledCarouselTemplates()` is already called at startup; the gallery
  calls it again defensively, as the Templates tab does with
  `loadBundledTemplates()`.

### 9. Deletions

Dead once the tab changes, and removed rather than left behind:

- `ProjectsViewController.Configuration.carousels`
- `HomeEmptyStateView.Content.carousels`
- `GallerySortOrder.withoutModeGrouping`

`GalleryFilter.modeFiltered` **stays** — Projects still calls it with `nil`, and
its unit tests are the pin on that behaviour.

Three file-header/doc comments describe a world where "the gallery runs twice"
and are rewritten with the code they document, not left to rot:
`GalleryFilter.swift`'s header, `ProjectsViewController.Configuration`'s doc
comment, and `CarouselStartViewController`'s header (which narrates the tab's
Step 06 history and now has a third chapter — the picker stays a sheet, but its
callers change).

## Error handling & degradation

| Failure | Behaviour |
|---|---|
| Manifest missing/corrupt | Every card renders its `schematicCover`. The gallery is fully usable; it is just wireframes. |
| One template's photos fail to resolve | That card alone falls back to schematic. `sampleFramePhotos` is already all-or-nothing per template. |
| A template parses to zero frames | Excluded from the gallery. `openCarouselTemplate` already guards this, but a card that cannot open must not be shown. |
| Filters match nothing | Centred empty label; chips and search stay interactive. |
| Renderer returns nil for a cover | Schematic fallback; never an empty card. |

## Testing

**Unit (sim-safe):**
- Manifest integrity extends to all 20 automatically via the existing
  `SampleContentCatalogTests` / `ShowcasePreviewTests` loops over
  `manifest.carousels.keys` — including the per-frame photo-count check that
  makes a mis-authored entry a test failure rather than a blank card.
- New: `featuredCarouselIDs` resolution, ordering, and absent-key fallback.
- New: `showcaseCover` returns an image whose aspect ratio matches the
  template's canvas — the property the masonry depends on, and the one a
  regression to the strip renderer would break silently.
- New: `schematicCover` is non-nil for every bundled template, with no manifest.
- New: `canOpen(_: CarouselTemplate)` for free/premium × locked/unlocked.
- Section building: type grouping, ratio filter including the `nil` case,
  search, and empty-section omission — as a pure function over
  `[CarouselTemplate]`, testable without a simulator, in the manner of
  `GalleryFilter`.

**UI tests:** `CarouselTabUITests` is written entirely against the saved-project
gallery (`carouselsGrid`, `carouselsEmptyStateCreateButton`,
`projectCard-<mode>` identity assertions) and is **rewritten**. Expected churn.
New coverage:
- The tab renders the catalog and its section headers.
- `testCarouselTabHasNoCompetingCreateBar` is **kept**, retargeted at the new
  root — it pins the Step 06 regression and the new `New` bar button must not
  reintroduce it.
- Selecting a type chip collapses to one section; the `›` chevron does the same.
- Tapping a free card opens the carousel editor; tapping a locked card presents
  the paywall.
- Identifiers: `carouselTemplateGrid`, `carouselTypeChips`,
  `carouselRatioChip`, `carouselTemplateCard.free` / `.premium`,
  `carouselGalleryEmptyLabel`, `carouselGalleryNewButton`.

Per the existing UI-test note: assert **identity, not counts** — a collection
view only puts visible cells in the accessibility tree, so a count saturates at
a screenful.

**Device QA (not sim-testable):** masonry scroll smoothness with 20 rendered
covers, first-open latency before the disk cache is warm, and legibility of the
page dots over pale artwork (a real risk — much of the catalog is authored on
white, which is why `applyShowcaseCaptionShadow` exists).

## Known limitation: panoramic previews

A panoramic template's frames carry no crop data — the split happens at build
time from a photo the user picks (`PanoramicSourcePicker`). Its preview is
therefore *one sample photo per frame*, not slices of one wide scene. Mitigated
by choosing same-family sequences (`sample_travel_01/02/03`) so the strip reads
as a sweep.

Making it truly correct needs (a) genuinely wide source photography — the widest
bundled asset is 16:9 — and (b) a per-frame crop-rect path in the preview
renderer. Both are out of scope. Recorded here so the next person does not read
the mitigation as the intent.

## Out of scope

- Authoring new carousel templates. All 20 already exist; this surfaces them.
- Any change to the carousel editor.
- Redesign of Home or the Templates tab. Home changes in exactly two places:
  its "See All" destination, and the premium lock on its carousel cards.
- Server-delivered template packs. Everything stays bundled.
- Swipeable multi-page previews inside a card (considered, rejected: 20 live
  paging scroll views inside a scrolling grid is a memory and scroll-performance
  risk on older devices).
- Category (travel/story/product/…) as a user-facing filter.

[AppCoordinator.swift:95]: ../../../Caroullage/Coordinators/AppCoordinator.swift
[Core/Rendering/MasonryLayout.swift]: ../../../Caroullage/Core/Rendering/MasonryLayout.swift
