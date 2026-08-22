# Step 05b — Visual Design Excellence & App Icon — Design

**Date:** 2026-08-22
**Branch:** `step-05b-visual-design-excellence`
**Source brief:** `Steps/Step_05b_VisualDesignExcellence.md`
**Baseline at start:** 429 unit+integration + 39 UI tests green (`** TEST SUCCEEDED **`)

## Goal

Bring the feature-complete app to a visual bar it can stand next to SCRL/Unfold with, unified
by the orange-and-white identity already encoded in `Theme`, and ship a custom app icon.

## What the audit found

- **There is no asset catalog at all.** `project.yml:81` sets
  `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`, but no `.xcassets` exists anywhere in the repo,
  so the app currently ships the blank default icon. Part A starts from zero, not from a redesign.
- **Raw system colours survive in 17 files**, concentrated in the editors
  (`GridEditorViewController`, `CanvasView`, `GridEditorControls`) and in the SwiftUI sheets.
- **Raw system fonts survive in 9 files**, almost all SwiftUI (`UniversalExportSheetView` alone
  has 11).
- The design foundation itself (`Theme`, `Haptics`, `AppAppearance`) is sound and is extended,
  not rebuilt.

## Owner decisions (2026-08-22)

1. **App icon direction: candidate 1, "fanned cards"** — three photo cards fanned like a hand,
   the front card's face being the app's own asymmetric three-cell collage, on the brand
   gradient. Chosen over the grid+dots and white-led paper-grid directions.
2. **Masonry gallery cards: yes** — Home and Projects cards size to each project's real aspect
   ratio instead of being cropped into uniform tiles. This was deferred out of Step 05 batch D
   and lands here.

## Architecture

### The icon is code, not a bitmap

`Tools/IconGenerator/main.swift` is a macOS CoreGraphics program that draws the icon and emits
every artefact from one definition: the PDF vector master, the preview contact sheet, and the
light/dark/tinted 1024 PNGs the asset catalog needs. A hand-drawn master plus hand-exported
sizes would be two sources of truth that drift; this is one.

The three appearances differ **only** by palette, never by geometry — each candidate draws from
four ink roles (`ground`, `card`, `cell`, `ghostAlpha`) and the `Variant` selects the palette.
Dark and tinted draw on a transparent ground because iOS composites them over a system backdrop.
That constraint has a consequence worth stating: a mark whose brand colour lives in the
*background* drains to a white silhouette in dark mode, so any candidate that paints its ground
orange must move the orange into its cells when the ground goes away.

### A component layer on top of `Theme`

`Theme` supplies tokens; it does not supply widgets, so every screen has been hand-assembling
buttons and headers from tokens and drifting. Step 05b adds
`ClaudeCollage/Core/DesignSystem/Components/` — primary/secondary/tertiary button
configurations, a card container, a section header, a pill segmented control, and an empty
state. Screens consume components; components consume tokens. Nothing else hardcodes a colour.

### Contrast is a test, not an eyeball

WCAG AA contrast between the brand ink pairs (`textOnAccent` on `accent`, `textPrimary` on
`background`/`surface`, `textSecondary` on `surface`) is asserted in unit tests against the
relative-luminance formula, in **both** light and dark trait collections. This is the only part
of "does it look right" that can be pinned down mechanically, so it is.

### Masonry without a layout regression

Gallery cards move to a `UICollectionViewCompositionalLayout` whose item heights come from each
project's stored aspect ratio. The height calculation is pure arithmetic over
`ProjectSummary`, so it is unit-tested headlessly (column balancing, extreme ratios, a single
item, an empty set) without instantiating a collection view.

## Batches

| Batch | Scope |
|---|---|
| **A** | App icon: refine the chosen fan for 40pt legibility, install the appiconset (light/dark/tinted), emit the PDF master, wire `project.yml`, verify on the simulator home screen, regression-test that the icon is actually bundled. |
| **B** | Brand system: the component layer, the WCAG-AA contrast tests, and the sweep that removes every remaining raw system colour and font. |
| **C** | Home, Projects (masonry), tab bar, mode selector / "+" sheet. |
| **D** | Grid & polygon editor, template & carousel editor, video editor. |
| **E** | Export sheet + success moment, motion and haptic consistency pass, full walkthrough screenshots for sign-off. |

## Non-goals

- Paywall styling — Step 06 owns the paywall.
- Localisation, accessibility audit beyond contrast and Dynamic Type — Step 06.
- Any change to rendering or export output. This step must not alter a single exported pixel;
  the render path is touched only where it reads a `Theme` colour for on-screen chrome.

## Done criteria

Unchanged from the brief, plus: the icon regression test passes, the contrast tests pass in both
appearances, and the full suite is still green with no new UI-test flake.
