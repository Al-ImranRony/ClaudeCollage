# Carousel creation moves into "Start Editing"; the Carousel tab becomes a place

Date: 2026-08-27
Branch: `step-06-deployment`

## Problem

On the Carousel tab, two filled brand-orange primary CTAs stack at the bottom of
the screen roughly 66pt apart:

- `carouselCreateButton` — the full-width `Create` bar at the foot of
  `CarouselTypeSelectorView`, the committing action for the form above it.
- `startEditingButton` — the floating `+ Start Editing` gradient pill that
  `AppTabBarController` draws over every tab.

Both are filled, brand-coloured and rounded, in the same band, with nothing to
say which is the action. That is the symptom. There are two causes underneath
it, and the cosmetic one is the smaller.

**The Carousel tab is the only tab whose root is a form rather than a place.**
Home, Templates and Projects are browsable; `CarouselStartViewController` parks a
permanent "New Carousel" wizard in the tab bar. The floating pill's job — start
something new — is that screen's whole job, so the two collide by construction.
The tab also gives existing carousels nowhere to live; they land in Projects.

**The global create menu cannot make the app's signature format.** The pill opens
Camera / Image / Video / Custom Canvas. Standing on the Carousel tab, the app's
one "make something" button offers everything except a carousel.

There is a third, smaller problem the fix has to avoid making worse: the four
existing options mix two axes. Camera and Image are *where the photos come from*
and land in the same grid collage; Video and Custom Canvas are *what you are
making*. Appending Carousel to that list without re-cutting it adds to the mess.

## Design

### 1. The Start Editing menu

`StartEditingSheetViewController` goes from four rows to five, on one axis —
what are you making?

| # | Title | Subtitle | Symbol | Identifier |
|---|-------|----------|--------|------------|
| 1 | Camera | Shoot one now, with a filter | `camera.fill` | `startEditingCamera` |
| 2 | Photos | Pick photos, we'll fit a layout | `photo.on.rectangle.angled` | `startEditingImage` |
| 3 | Video | A moving collage | `play.rectangle.fill` | `startEditingVideo` |
| 4 | Carousel | A multi-frame post for the feed | `rectangle.on.rectangle.angled` | `startEditingCarousel` |
| 5 | Custom Canvas | Choose your own size | `square.resize` | `startEditingCustomCanvas` |

Camera stays first for the reason already recorded in the file: it is the only
row that makes something that does not exist yet.

"Image" becomes "Photos" — every other row names an activity, "Image" names a
format. **Its accessibility identifier stays `startEditingImage`.** Identifiers
were deliberately frozen when this sheet stopped being a `UIAlertController`, and
freezing them again means no existing UI test changes for the rename.
`QuickStartTile` sets `accessibilityLabel` from the title, so the spoken label
does follow the rename; nothing asserts on it.

Carousel sits after Video because both are multi-frame outputs. Its symbol is
`CollageMode.carousel.badgeSymbolName`, so the menu row and the gallery card
badge are the same glyph rather than two drawings of the same idea.

**The detent stops being a constant.** `contentHeight` is hardcoded at 420 and
its comment claims three rows while four render — it has already drifted, and
five rows overflow it. Replace it with a measured value:

- Hold the row stack in a property.
- In the custom detent resolver, return
  `min(measuredHeight, context.maximumDetentValue)`, where `measuredHeight` comes
  from `systemLayoutSizeFitting` on the stack plus the top and bottom margins.
- Call `sheetPresentationController?.invalidateDetents()` from
  `viewDidLayoutSubviews` when the measured height changes, so the sheet resizes
  when the view first lays out and again if Dynamic Type changes.

Before first layout there is no measurement to return, so the resolver falls back
to the current 420 and the first `invalidateDetents()` corrects it. The sheet
therefore never opens at zero height, and never opens taller than the screen.

### 2. The Carousel tab becomes a gallery of your carousels

`ProjectsViewController` gains an optional mode filter and is instantiated twice.

- New stored property `modeFilter: CollageMode?`, defaulting to `nil`, set via a
  designated initializer.
- `applyFilters()` derives an intermediate `modeFiltered` from `summaries` before
  applying the search text and the sort. `summaries` itself stays the raw store
  contents.
- The empty state keys off `modeFiltered`, not `summaries`. On the Carousel tab,
  "you have grid collages but no carousels" is the empty case. The existing rule
  that a no-match **search** must not show the empty state is preserved by the
  second half of the condition: the empty state shows when `modeFiltered` is
  empty *and* the search box is empty. With `modeFilter == nil`, `modeFiltered`
  equals `summaries` and the Projects tab behaves exactly as it does today.
- The sort control drops to Recent / Oldest when `modeFilter != nil`. "By type"
  cannot group anything when every item is one type.

`HomeEmptyStateView` is currently hardcoded to a grid glyph, "No collages yet",
"Create your first grid collage to get started." and a "New Collage" button. It
gains an initializer taking symbol, title, subtitle and button title, with the
current strings as the defaults so the Projects tab is untouched. The Carousel
tab passes `rectangle.on.rectangle.angled`, "No carousels yet", "Build a
multi-frame post for the feed.", "New Carousel". `emptyStateCreateButton` keeps
its identifier.

Carousel tab configuration: `navigationItem.title = "Carousels"` — never `title`,
which would rewrite the tab bar label the first time the tab's view loaded — and
search placeholder "Search your carousels". The tab's own descriptor
(`"Carousel"`, `rectangle.stack.fill`, `carouselButton`) is unchanged.

`AppCoordinator` currently wires seven closures onto the single gallery. With two
instances that block gets factored into `makeGallery(mode: CollageMode?) ->
ProjectsViewController`, so the wiring exists once. The only per-instance
difference is `onNewProject`: Projects starts a grid, Carousel opens the type
picker.

**Rejected alternatives.** A dedicated `CarouselGalleryViewController` would be
freer — a filmstrip preview per card — but forks masonry, search and the
rename/duplicate/export/delete context menu. This codebase has repeatedly lifted
shared components rather than forking; `QuickStartTile` exists for exactly that
reason. Keeping the type picker as a strip above the carousel grid was also
rejected: it puts a create surface back into the tab root, which is the thing
that caused the collision.

### 3. Where carousel creation happens

One code path, three doors.

`CarouselStartViewController` stops being a tab root and becomes a modal host. It
already hosts `CarouselTypeSelectorView`, and that view already renders a Cancel
header when `onCancel` is non-nil — a branch that is currently dead, because the
only caller passes `nil`. The change is to pass a real `onCancel` that dismisses,
present the controller as a page sheet, and drop the three pieces that only made
sense inside a navigation stack: `navigationItem.title`, `prefersLargeTitles`,
and the `TopFadeView` that faded content under a nav bar there is no longer. The
SwiftUI view's own header supplies the title and the Cancel button.

The three doors:

1. The Carousel row in the Start Editing sheet.
2. The Carousel tab's empty-state button.
3. The `NewStoryCarousel` App Intent — unchanged, it already calls
   `beginCarousel(config:)` directly and never touched this screen.

All three land in `AppCoordinator.beginCarousel(config:)`, which is unchanged.

Presentation order matters for door 1: `StartEditingSheetViewController.finish`
already dismisses before acting, because presenting from a covered controller is
dropped by UIKit. The carousel row uses the same `finish` wrapper as every other
row, so nothing new is required.

Net effect on the reported screen: the `Create` bar now lives inside a sheet
where it is the only CTA, and the floating pill stays on all four tabs with
nothing to compete with.

### 4. Test impact

Six UI test files reach the type selector by tapping the `carouselButton` tab:
`CarouselTypeSelectorUITests`, `CarouselPreviewUITests`, `CarouselEditorUITests`,
`CarouselExportUITests`, `CriticalFlowTests`, `TabBarShellUITests`. Each entry
becomes `startEditingButton` → `startEditingCarousel`, via one shared helper
rather than the two taps repeated six times.

New coverage:

- The Start Editing sheet offers all five rows, Carousel included.
- The sheet's five rows fit — the presented sheet's height is at least the
  measured content height, so a regression to a stale constant fails.
- The Carousel tab lists only `.carousel` projects: create one grid collage and
  one carousel, assert Projects shows two cards and Carousel shows one.
- The Carousel tab's empty state opens the type picker.
- Existing: a no-match search on a non-empty gallery still shows no empty state.

### 5. Out of scope

Home's "Start Something" section (Grid / Shapes / Video) is left alone. It is
already a different list from the sheet's, and widening this change into Home
turns a fix into a rework. Worth a follow-up, not this one.

## Files touched

| File | Change |
|------|--------|
| `Features/Home/StartEditingSheetViewController.swift` | fifth row; "Image" → "Photos"; measured detent |
| `Features/Home/ProjectsViewController.swift` | `modeFilter`; empty-state and sort-control rules |
| `Features/Home/HomeViewController.swift` | `HomeEmptyStateView` initializer parameters |
| `Features/CarouselEditor/CarouselStartViewController.swift` | tab root → modal host |
| `Coordinators/AppCoordinator.swift` | `makeGallery(mode:)`; Carousel tab; carousel row action |
| `CaroullageUITests/UI/*` (6 files) | shared entry helper |

## Success criteria

- The Carousel tab shows no full-width `Create` bar; the floating pill is the
  only filled CTA on every tab root.
- `+ Start Editing` offers Carousel from any tab.
- The Carousel tab lists carousels only, and none of Projects' behaviour
  (masonry, search, sort, context menu) is duplicated to get it.
- The five-row sheet fits at default and at large Dynamic Type.
- Full suite green: 429 unit+int, 39 UI, plus the additions above.
