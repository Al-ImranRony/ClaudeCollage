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

Both galleries are alive at once, so every identifier has to be per-instance or
the two tabs' views collide in the accessibility tree. They come from the
configuration: Projects keeps `projectsGrid` / `projectsSearchField` /
`projectsSortControl` / `emptyStateCreateButton` exactly as today, and the
Carousel tab gets `carouselsGrid` / `carouselsSearchField` /
`carouselsSortControl` / `carouselsEmptyStateCreateButton`.

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

Five UI test files reach the type selector by tapping the `carouselButton` tab:
`CarouselTypeSelectorUITests`, `CarouselPreviewUITests`, `CarouselEditorUITests`,
`CarouselExportUITests`, `CriticalFlowTests`. Each entry becomes
`startEditingButton` → `startEditingCarousel`, via one shared helper rather than
the two taps repeated five times. (`TabBarShellUITests` uses `carouselButton`
only as a tab, which still exists, so it gains an assertion rather than an edit.)

`CarouselEditorUITests.testCarouselResumesFromHome` also changes its expectation:
backing out of the editor now returns to the tab the carousel was started from —
Home — rather than to the Carousel tab's old form root.

New coverage:

- `GalleryFilterTests` — the mode filter, search-within-filter, the three sort
  orders, and both halves of the empty-state rule.
- `StartEditingSheetTests` — the detent is measured, clamped, and falls back
  rather than collapsing before first layout.
- `TabBarShellUITests` — the sheet offers Carousel alongside the other four.
- `CarouselTabUITests` — the reported bug (no `carouselCreateButton` parked on
  the tab, the floating pill left as the only filled CTA), the tab always renders
  either a grid or its empty state, a non-carousel project never appears on the
  Carousel tab, and a carousel made from the "+" sheet leads it.

**Counting cards does not work as an assertion.** A collection view puts only its
VISIBLE cells in the accessibility tree, so both an absolute count and a delta
saturate at a screenful — the first version of these tests failed exactly that
way against a simulator already holding six projects. Cards therefore carry a
`projectCard-<mode>` accessibility identifier (not in the original design), and
the assertions are on identity: with Recent as the default order, "the thing just
made is card 0" holds regardless of what the simulator was already carrying.

### 5. Out of scope

Home's "Start Something" section (Grid / Shapes / Video) is left alone. It is
already a different list from the sheet's, and widening this change into Home
turns a fix into a rework. Worth a follow-up, not this one.

## Device QA follow-ups (2026-08-28)

Three defects found on device after the change landed. Two were exposed by it;
one is older and unrelated to the carousel work.

**1. Cards ghosted under the header when re-sorting.** `sortChanged` finished with
`collectionView.setContentOffset(.zero, …)`, and `.zero` is not the top of this
grid: it runs the full height of the view and carries a `contentInset.top` that
holds the first row clear of the pinned sort control. Offset zero parks that row
*under* the control and the nav bar, where the top fade leaves it as a pale
smear; with less than a screenful of cards there is nothing to bounce it back, so
it stayed there across further sort changes. Now scrolls to
`-adjustedContentInset.top`. Pre-existing on the Projects tab, but invisible
there because that gallery is usually taller than the screen.

**2. The "+ Start Editing" pill squared off after a tap.** Two writers were
racing for one property. `viewDidLayoutSubviews` set `layer.cornerRadius` to
23pt; a configured `UIButton` writes its own resolved background radius onto the
button's layer during layout, and the default `.dynamic` corner style resolves to
17pt on a 46pt-tall button. The shell won at launch and the button won the next
time a tap made it lay out. Fixed by letting the configuration own it —
`config.cornerStyle = .capsule`, which holds at any height — and dropping the
manual assignment. `cornerCurve` is now `.circular`, since a capsule's ends are
semicircles and `.continuous` at that radius draws a squircle.

The layout pass also assigned `frame` while the press animation's 0.92 scale was
still on the button. UIKit answers a frame assignment on a transformed view by
solving for the bounds that would produce it, inflating a 46pt button to 50pt and
compounding with every press. Now `bounds` + `center`, which are
transform-independent.

**3. A dead band along the bottom of the collage editor.** The control tray was
pinned to `view.safeAreaLayoutGuide.bottomAnchor`, stopping it 34pt short of the
screen edge — and since editors hide the tab bar, nothing occupied that strip and
nothing could scroll into it. Now pinned to `view.bottomAnchor` with
`contentInsetAdjustmentBehavior = .never`, because a scroll view that reaches the
edge otherwise hands the same inset straight back as content inset. Both halves
are pinned by `EditorControlTrayTests`, whose harness has its own guard test: the
first version passed against the unfixed code because `additionalSafeAreaInsets`
never reaches `safeAreaInsets` outside a window.

Not changed: the toast, eraser toolbar, camera shutter and carousel frame strip
also pin to the safe area, but those are floating controls that should respect
the home indicator, not trays with empty space beneath them.

## Carousel editor rework (2026-08-29)

Three defects and two product changes, from a second device-QA pass.

**1. Jerky long-press zoom, square platter behind rounded corners.** Two causes.
The stutter was not the animation: `thumbnail(for:)` ran a full Core Graphics
composite synchronously inside `cellForItemAt`, and `reloadFrames()` emptied the
cache on every view-model change, so a context-menu zoom competed with N
full-canvas renders on the main thread. Rendering now happens off the main actor
(`RenderRequest` is `Sendable` and `CollageRenderer` is `@unchecked Sendable`
precisely for this) into `CarouselThumbnailCache`, which is keyed by frame
content — an edit costs one re-render, a reorder costs none. The platter was a
missing `UITargetedPreview`: without `UIPreviewParameters.visiblePath` matching
the cell's corner mask, UIKit lifts the cell onto its default opaque rectangle.

**2. Broken delete UI.** `confirmDelete` presented a `.actionSheet` from inside
the context-menu action handler, while the menu was still running its dismissal
transition; UIKit abandons the teardown and strands the menu's container. Every
menu action is now deferred into `willEndContextMenuInteraction`'s animator
completion, and the confirmation is gone entirely — `deleteFrame` is on the
carousel's undo stack with Undo in the nav bar, so a destructive-styled menu item
plus a modal confirm was asking twice about something already reversible.

**3. Frame number badge.** Was a caption on a 90%-opaque accent rectangle sized
by padding its string with literal spaces. Now a material capsule with
monospaced digits — material so it holds over a bright photo and an empty frame
alike, monospaced so the badge does not resize between frame 9 and 10, and
accent-filled only on the selected panel so selection needs no second affordance.

**4. The strip is one continuous canvas.** Panels sit edge to edge along the
carousel's axis with a hairline seam, and only the strip's two ends are rounded.
A gutter is not neutral styling here: for a panoramic carousel the frames *are*
one photograph cut into pieces, and a gap draws a seam the published post does
not have.

The axis is now persisted (`CollageProject.carouselAxisRaw`, optional, so no
migration) and offered for every carousel type rather than panoramic only, since
it no longer means just "which way is the source photo cut". A toolbar menu
switches it in the editor.

The geometry has one non-obvious rule. Filling the cross axis and taking the
other dimension from the aspect is the natural formula and it is wrong: on a 4:5
canvas it yields a panel exactly as wide as the screen, so you see one frame at a
time and the strip is indistinguishable from a single-frame editor. A panel is
therefore capped at 62% of the container along the scroll axis, so the next panel
always peeks. **This was caught by running it, not by the tests** — the original
tests asserted the natural formula and passed.

Export is untouched: each frame renders through its own `GridEditorViewModel` at
canvas size, and the navigator's arrangement never enters `renderFrames()`.
`testChangingTheAxisDoesNotTouchTheFrames` guards that, because an axis that
reached the frames would change the exported post.

**5. "Sync Edit" → "Apply This Style to All Frames".** The capability was right;
the toggle was not. It was hidden modal state — flip it on, edit a frame twenty
minutes later, and other frames change with nothing to say so — it never said
which frame was the source, and it broadcast two of the four things `StyleChange`
defines. It is now an action in each frame's context menu, so the frame under
your finger *is* the source, it happens once, it carries `.font` and
`.textColor` too, and Undo reverses it. The toolbar slot it vacated now holds the
direction control, which belongs next to the strip it changes.

That exposed a related bug: `commitCurrentFrame` never recorded, so a frame edit
was invisible to carousel undo and undoing anything structural afterwards
silently discarded it. It now records when the state actually changed.

**Counting cells does not work here either.** With a panel and a half on screen,
`strip.cells.count` saturates — the same trap as the gallery. The navigator now
publishes its frame count as the collection view's accessibility value, which is
real VoiceOver value (only a panel and a half is visible, and VoiceOver reaches
cells one at a time with no sense of how many remain) rather than a test hook.

## Filter-control pass (2026-08-29)

**Tab order.** `Home | Templates | Carousel | Projects`. Carousel takes the
mid-bar position where the thumb lands, because it is the signature format;
Projects, the archive, takes the edge.

**Two segmented controls became menu chips.** A `UISegmentedControl` has to draw
every option all the time, so it costs a full row regardless of how often the
choice is made. Both of these were set once and then ignored:

- The gallery's Recent/Oldest row now carries a live count on the left and a
  compact sort menu on the right. The row went from stating a binary nobody
  changes to stating what you are looking at.
- The template gallery's ratio control is now a pinned chip at the head of the
  category row, with a hairline between it and the tags. That is one filter row
  instead of two, and it makes the distinction visible: a category is a tag, the
  ratio is a mode that reshapes every card. The menu also shows each ratio's
  actual aspect as a subtitle, which the segmented control never did.

`FilterMenuChip` is the shared control. It sets `configuration.indicator =
.popup` for the chevron rather than `changesSelectionAsPrimaryAction`, which
would overwrite `configuration.attributedTitle` and drop the chip's type styling
along with its `accessibilityValue`.

**A wrong turn worth recording.** The menu actions were first given
`UIAction.Identifier`s so tests could select them unambiguously — the stated
worry being that "Story" is both a ratio and a category chip. Two things were
wrong: XCUITest does not surface `UIAction.Identifier` as an element identifier,
so the tests failed outright; and the collision never existed, because the
category chips are static texts rather than buttons. The identifiers were removed
and the menus are matched by label.

## Files touched

| File | Change |
|------|--------|
| `Features/Home/StartEditingSheetViewController.swift` | fifth row; "Image" → "Photos"; measured detent |
| `Core/Services/GalleryFilter.swift` *(new)* | the narrowing, sorting and empty-state rules |
| `Features/Home/ProjectsViewController.swift` | `Configuration`; filtering delegated to `GalleryFilter` |
| `Features/Home/HomeViewController.swift` | `HomeEmptyStateView.Content`; `projectCard-<mode>` on cards |
| `Features/CarouselEditor/CarouselStartViewController.swift` | tab root → modal host |
| `Coordinators/AppCoordinator.swift` | `makeGallery(configuration:onNew:)`; `presentCarouselTypePicker()` |
| `CaroullageUITests/Support/XCUIApplication+Carousel.swift` *(new)* | shared entry helper |
| `CaroullageUITests/UI/*` (6 files) | new entry route; `CarouselTabUITests` added |
| `CaroullageTests/Unit/*` (2 new files) | `GalleryFilterTests`, `StartEditingSheetTests` |

## Success criteria

- The Carousel tab shows no full-width `Create` bar; the floating pill is the
  only filled CTA on every tab root.
- `+ Start Editing` offers Carousel from any tab.
- The Carousel tab lists carousels only, and none of Projects' behaviour
  (masonry, search, sort, context menu) is duplicated to get it.
- The five-row sheet fits at default and at large Dynamic Type.
- Full suite green: 429 unit+int, 39 UI, plus the additions above.
