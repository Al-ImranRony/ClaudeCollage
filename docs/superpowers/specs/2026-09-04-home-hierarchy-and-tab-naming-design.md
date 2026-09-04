# Home hierarchy and tab naming

**Date:** 2026-09-04
**Status:** Approved, ready for implementation planning
**Scope:** Two independent changes — Home's section order, and the middle tabs' names.

---

## 1. Home section order

### The problem

`HomeViewController.setupLayout()` builds this stack:

```
Hero → Photo Collages → Video Collages → Carousels → Suggested For You → Create New
```

The two highest-intent sections are the two furthest from the thumb. On an iPhone 17 a
first-run user scrolls roughly 1,400pt before reaching a single create door. The three
sections occupying the top of the screen are catalog browsing — which is precisely what
the Collage tab (`TemplateGalleryViewController`, 33 templates) and the Carousel tab
(`CarouselGalleryViewController`, 20 templates) exist to do.

The App Store convention in this category splits on whether the product is an editor or a
feed. Editors lead with create actions and put inspiration below: Canva opens on format
chips, CapCut on a "New project" button, Picsart on a create-action row, PhotoRoom on a
start tile. Feeds do the opposite. Caroullage is an editor wearing a feed's layout.

### The change

Reorder to:

```
Create New → Hero → Suggested For You → Photo Collages → Video Collages → Carousels
```

Nothing is added, removed, or restyled. Only the six `contentStack.addArrangedSubview`
calls change order, and `makeQuickStartSection()` moves ahead of `makeHeroSection()`.

`Create New` keeps its `SectionHeaderView`. Every other block on Home is a headed section,
and four unlabelled icon pills directly under the nav bar is the closest this screen gets
to the schematic tile grid Step 07 deliberately removed.

### Why the catalog strips can be demoted

They duplicate the two gallery tabs. Their "See All" actions
(`seeAllTemplatesButton`, `seeAllCarouselsButton`) already exist to hand users off to those
tabs, and both remain wired exactly as they are. Demoting the strips costs discovery of
content that has a dedicated tab; promoting Create New and Suggested For You buys the two
things only Home offers.

### Fold budget after the change

iPhone 17, 402 × 874pt. The floating "Start Editing" pill's top edge sits at ≈ 702pt.

| block | height | running total |
|---|---|---|
| status bar + compact nav | 106 | 106 |
| `contentStack` top padding | 8 | 114 |
| "Create New" header (`title2`, 22pt) | 26 | 140 |
| section spacing (`Spacing.sm`) | 12 | 152 |
| chip row (`sm` + 17pt glyph + `xxs` + `caption`  + `sm`) | 65 | 217 |
| `contentStack.spacing` (`Spacing.xl`) | 24 | 241 |
| hero (370 wide × 0.84) | 311 | **552** |
| `contentStack.spacing` | 24 | 576 |
| "Suggested For You" header | 26 | 602 |
| section spacing | 12 | 614 |
| suggestions strip (fixed `heightAnchor`) | 96 | **710** |

Create New and the hero are fully above the fold. The suggestions strip runs 614 → 710, so
its last 8pt tuck under the pill — it shows 88 of 96pt. That partial reveal is deliberate
and matches the cue the existing fold comment already relies on for "Video Collages": content
that peeks invites a scroll, content that is fully hidden does not.

`heroAspectRatio` stays at **0.84**. The value still holds under the new stack; only the
derivation written above it is now wrong.

### Behaviour that does not change

- `Suggested For You` remains conditional. `refreshSuggestions()` keeps its three states:
  `.notDetermined` shows the soft enable card, `.authorized` loads the strip, `.denied`
  hides the section. It still never prompts on its own — access is requested only when the
  user taps. Promoting it to position 3 makes the soft ask more visible on first run, which
  is the intent.
- All accessibility identifiers, closures, and `See All` wiring are untouched.
- The four chips keep their titles, glyphs, identifiers and actions.

### Comments that must be rewritten

Two doc comments describe a stack that will no longer exist, and editing around them would
leave the file arguing for the old screen:

- `HomeViewController.swift:17-25` — the "section order is the argument the screen makes"
  paragraph. Rewrite for the new order, and for why create now leads.
- `HomeViewController.swift:70-100` — the `heroAspectRatio` fold derivation. Replace the
  budget table with the one above, and keep the note that the ratio is derived rather than
  chosen.

---

## 2. Tab naming

### The problem

The bar reads `Home | Templates | Carousel | Projects`.

*Templates* names a **content type**. *Carousel* names an **output format**. But both middle
tabs are template galleries. Nothing in the bar tells a user that "Templates" excludes
carousel templates, or that "Carousel" is also templates. Two tabs doing the same job,
labelled on two different axes, so they cannot be read as a set.

### The change

| surface | file | now | after |
|---|---|---|---|
| tab label | `AppCoordinator.swift:107` | `Templates` | `Collage` |
| collage gallery nav title | `TemplateGalleryViewController.swift:73` | `Templates` | `Collage Templates` |
| carousel gallery nav title | `CarouselGalleryViewController.swift:69` | `Carousels` | `Carousel Templates` |

Both middle tabs become format names — parallel, mutually exclusive, readable as a set —
and the word *Templates* moves to the nav titles, where it tells a user what they are
looking at once inside. The carousel side is included because the parallelism only pays off
if both screens introduce themselves the same way.

Localization follows each string's own neighbours rather than one blanket rule:

- Both **nav titles** become `String(localized:)`. The carousel gallery already uses that
  form; the collage gallery's raw `"Templates"` is the odd one out.
- The **tab title** stays a raw literal. `"Home"`, `"Carousel"` and `"Projects"` are all raw
  literals passed to `tabItem(_:_:selected:_:)`, and localizing one of four would introduce
  an inconsistency rather than remove one. Localizing all four tab titles is a reasonable
  follow-up, but it is not this change.

### Accessibility identifiers stay unchanged

`templatesButton` and `carouselButton` keep their names. They are not user-visible, and
renaming them would touch roughly eight test files for no behavioural gain.

### Known trade-off, accepted

The app also makes **video collages**, and they appear in neither middle tab — only a Home
strip and the "Video" create chip. A tab called *Collage* arguably promises video collages;
*Templates* promised nothing specific, so it could not break that promise. Accepted as mild
and separately fixable later (a Video category chip in the gallery). Not in scope here.

### The `title` vs `navigationItem.title` trap

`TemplateGalleryViewController.swift:70` already carries a comment warning that assigning
`title` on a tab root also rewrites its tab bar label, and that the trap "survives unnoticed
until someone renames one." This is that rename. Both galleries already use the safe
`navigationItem.title` form, so the change is clean — but both comments now describe a
mismatch that is real rather than hypothetical, and must be rewritten to say so.

---

## Test impact

Ten assertions across five UI test files. All are string updates; no test logic changes.

| file | lines | change |
|---|---|---|
| `TabBarShellUITests.swift` | 38, 64 | tab label arrays: `"Templates"` → `"Collage"` |
| `TabBarShellUITests.swift` | 241 | failure message wording |
| `TemplateGalleryUITests.swift` | 27, 73, 110 | `navigationBars["Templates"]` → `["Collage Templates"]` |
| `CarouselTabUITests.swift` | 34, 124 | `navigationBars["Carousels"]` → `["Carousel Templates"]` |
| `VisualWalkthroughUITests.swift` | 50 | taps the tab **by label** — `("Templates", "02-templates")` → `("Collage", "02-collage")` |
| `PaywallUITests.swift` | 39 | failure message wording only (uses the identifier) |

`HomeShowcaseUITests` needs no change. `testHomeShowsHeroAndThreePillars` asserts
`.exists` rather than hittability, and its `reveal()` helper swipes, so both are
order-tolerant.

## Verification

- `TabBarShellUITests`, `TemplateGalleryUITests`, `CarouselTabUITests`,
  `HomeShowcaseUITests`, `VisualWalkthroughUITests` pass on the iPhone 17 simulator.
- Home on a cold launch shows, above the pill: the Create New header, four chips, the full
  hero, the Suggested For You header, and most of the suggestions strip.
- The tab bar reads `Home · Collage · Carousel · Projects`; the two galleries' nav bars read
  `Collage Templates` and `Carousel Templates`.
- Neither gallery's tab label changes when its screen is pushed and popped — the
  `title` trap stays shut.

## Out of scope

- Video collage templates in the Collage gallery.
- Merging the two galleries into one segmented tab (considered, rejected: it would undo the
  Carousel gallery shipped in `1d7b77d`).
- Any restyling of the chips, hero, strips, or suggestions card.
