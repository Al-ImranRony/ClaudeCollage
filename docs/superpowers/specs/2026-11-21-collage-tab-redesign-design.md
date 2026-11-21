# Collage tab re-imagined — design record (2026-11-21)

The owner asked for a clean, gorgeous Collage tab carrying the template styles
that top App Store collage apps lead with, smooth to scroll, with UX decided
as a lead product designer would.

## What was wrong

- A **hard ratio filter** opened the tab on Square, so two thirds of the
  catalog was invisible until you found a menu.
- One uniform grid of same-shaped cards; nothing to browse *toward*.
- The catalog was simple grids. None of the trending looks could be built:
  instant prints, film strips and booth strips are all "a photo sitting on
  something", and the renderer had no "something".
- A collage template's preview ignored the editor's spacing and corner radius,
  so the opened project was a cousin of the card, not the card.

## Research (summary)

Recurring style families across PicCollage, Unfold, Storyluxe, Tezza, Frames,
Moldiv, PhotoGrid, Canva and Google Photos: film/analog, instant/polaroid,
photo-booth strips, editorial/magazine, scrapbook/photo dump, clean gutter
grids, shapes, year-in-review. Galleries are organized as **named shelves**,
with photo-count filtering (PicCollage), a personal/featured row on top
(Frames 7.0), and seasonal drops every one to three weeks as the retention
hook. Layout (Instagram) was discontinued in 2024; template-first browsing
plus photo-count filters is the current pattern.

## Decisions

1. **Two modes, one pure function** (`CollageGalleryPlanner`).
   - *Browsing* (no chip, filter or search): a paged spotlight of fresh
     **free** templates → themed shelves → the whole catalog in a masonry
     grid.
   - *Finding* (any chip, filter or search): one masonry grid of matches,
     with an empty state that offers **Clear Filters**.
2. **Filters chip** replaces the ratio chip: one menu asking *How Many Photos*
   (Any, 1–5, 6+) and *Canvas Ratio* (Any by default).
3. **Shelves keep each template's true shape**; widths are clamped
   (0.5625–1.4). The "NEW" tag shows only on the spotlight and the catalog
   grid: on every shelf card it meant nothing and covered headline art.
4. **Spotlight** presents a template like a print on a tinted stage (a wash of
   its own background colour), with depth scaling on neighbours (turned off
   under Reduce Motion).
5. **Seasonal shelf with `months`**: "Holiday Season" leads in Nov–Jan and
   steps aside the rest of the year.
6. **Curation lives in data**: `Resources/Collections/collage_gallery.json`
   (spotlight, new ids, shelves).

## Renderer additions

- `CanvasDecoration` + `DecorationRendering`: flat cards, bands, sprocket
  holes and tape, painted between the background and the cells. They are
  normalized (frame, radius and shadow as fractions of the canvas), persisted
  in `GridEditorState.decorations` (omitted when empty, decoded as empty when
  missing), drawn by the export renderer and by a cached layer on the canvas.
- `TemplateStyle` (`style` in template JSON): spacing, corner radius, outer
  margin, shadow and outline in reference points. Styled templates lay out
  through the editor's own `CollageLayoutEngine` call. Preview == project is
  pinned by `TemplateStyleDecorationTests`. Legacy templates (no `style`) keep
  their cache keys and look.

## Catalog

26 new templates (9 premium): Instant (print, trio, booth, taped), Film
(contact roll, film strip, negative duo), Editorial (Issue 01, cover, The
Edit, before & after), Photo Dump (nine, mood board, weekend recap, year in
frames), clean grids, shapes (bubbles, cameo, white space), a story layout,
holiday (Friendsgiving, Cozy Season, Holiday Booth) and a boarding pass.
Generated geometry; every template carries a sample-photo manifest entry.

## Sample photography (follow-up, same day)

178 photo slots were dressed from 24 photos, so each appeared about 7 times
(the beach shots 10–11 times). 61 Pexels photos were added (85 in all, +6.3 MB),
mostly to cover what the pool lacked: men, families, holiday, cafés, cities,
nature, road trips, pets, parties, flowers, vintage. `Tools/assign_sample_photos.py`
re-dresses every template: at most 3 uses per photo (mean 2.1), no repeat inside
the spotlight or a shelf, theme and orientation matched, and occasion
templates kept strictly on theme. Shelves also move templates an earlier row
already showed to their back.

### Carousel tab

The Carousel tab still used only the original 24 photos (178 slots; two beach
shots appeared 14 times each, and Menu showed the same dish twice). The same
tool (`--carousels`) now re-dresses it:
- at most 3 carousels share a photo (mean 1.9)
- all 28 covers are different
- no photo repeats across one carousel's slides
- captions decide themes (Meet the Team = four women's portraits, Menu = dishes, Trip Diary = beach → lake → road → city), and theme-critical carousels pick first
- holiday photos stay in holiday carousels
- Grid Reveal keeps its intended grid-then-reveal repetition
- panoramas get hand-picked wide sources

Each template already appears once on the tab. `SampleDressingVarietyTests` pins every rule. Manifest `version` → 8 so cached previews re-render.

## Smoothness

Cards are cache-first (memory hits show in the same frame, only late arrivals
crossfade). Shelf heads are prefetched because sideways sections are invisible
to the grid's prefetcher. The spotlight effect is a transform. Shadows carry
paths. `PerformanceUITests.testCollageTabScrollHitches` measured **0 ms
dropped** on cold and warm drives through the whole page.

## Follow-ups

- Home's strips still feature only the legacy catalog. Featuring the new
  styles there is a separate curation change.
- The ~77 pre-existing untranslated keys from bb3eb90 still fail
  `LocalizationTests`. This work's new strings are translated into all 11
  languages.
