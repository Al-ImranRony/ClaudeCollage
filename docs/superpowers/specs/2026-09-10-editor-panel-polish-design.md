# Editor chrome polish: one-shot tool emphasis, a symmetrical rail, and panels that read as one sheet

**Date:** 2026-09-10
**Status:** Implemented in the same session (owner asked for the change directly; no review gate)
**Scope:** `EditorToolRail`, `EditorPanel`, the panel content of both editors, and the text-style preset row they share.

---

## 0. What was wrong

Two owner complaints, both visible on the first screenshot of either editor:

1. **The active tool's icon animates forever.** `EditorToolRail` plays a `.repeating`
   SF Symbol effect on the selected tool for as long as it is selected. The owner wants
   a hover-style acknowledgement: the effect plays **once** when a tool becomes active,
   then rests.
2. **The panels look unfinished.** The rail bunches its five tools to the left and leaves
   the right 40% empty. The panel header is an uppercased caption with a ✕ dangling in
   the corner. Each panel lays its content out slightly differently (two copies of the
   same row helper, one per editor). The text-style presets are six bare "Aa" buttons that
   look identical, so the panel gives no idea what any of them do.

The reference screenshots the owner attached (SCRL, Unfold, Prequel, CapCut) share a
grammar: tools distributed evenly across the strip, a centred title with a round close
chip, option **cards** with a preview and a label, the chosen card outlined in the accent,
and press feedback on everything.

## 1. The rail

- **Distribution.** With no context inserted, the stack uses `.fillEqually` and is
  constrained to at least the rail's width, so N base tools take N equal columns — the
  same rule a `UITabBar` uses. With a context inserted that width constraint is released
  and the stack hugs its content at a 4pt gap: on a phone it overflows and scrolls, on an
  iPad it stays packed at the leading edge rather than being spread across the width.
- **Scrolling strips.** The rail and the preset strip use `EditorControlScrollView`,
  which delivers touches immediately (so a quick tap shows its press) and cancels them
  for controls (so a drag that starts on a held card still scrolls).
- **Active state.** Colour as before, plus a soft accent capsule (`accentSoft`, 44 × 28)
  behind the active icon. It pops in with the icon.
- **Emphasis plays once.** `ToolButton.setActive(_:animated:)`: on an animated transition
  into active, the icon pops (1.22 → 1 spring) and its per-tool symbol effect plays with
  `.nonRepeating`. `rebuild()` applies the current active state un-animated, so a context
  change that keeps a base panel open does not replay it. Reduce Motion skips both.
- **Separator.** Inset by `Spacing.md` on both sides so it reads as the divider between
  two tiers of one sheet, not as the top edge of a second bar.

## 2. The panel

- Background `surface` — the same as the rail — so panel + rail is one sheet whose only
  full-width hairline is the panel's top edge.
- Header: title centred in `Typography.subheadline` / `textPrimary`, no uppercasing.
  Close is a 28pt circular `controlFill` chip at the trailing margin, identifier
  `editorPanelCloseButton` unchanged.
- Content sits `Spacing.sm` under the header and `Spacing.sm` above the rail.

## 3. Panel content

- `EditorPanelRow` in `Core/DesignSystem/Editor/` replaces `FramePanelView.row` and
  `makeVideoPanelRow` / `wrapVideoPanelRows`: icon (15pt symbol in a 20pt box, `textSecondary`) · title
  (`caption`, `textPrimary`, 64pt column) · control. Both editors' rows are now the same
  code.
- `TextStylePresetRow` in `Features/GridEditor/Panels/` (beside `TextStyleSheet`, which
  the video editor already borrows) replaces both editors' `makeTextStylePanel` loops.
  Each preset is a 60 × 60 card showing "Aa" rendered through `TextRendering` with that
  style, and its name under it. The card whose kind matches the overlay's current style is
  outlined in `accent`; tapping re-highlights locally and reports the kind. Identifiers
  `textStyle_<kind>` are preserved — the rail tests tap them.
- Press feedback: `UIView.setPressed(_:)` in `Theme.swift` is the one spring every editor
  control uses (tool button, chips, cards, the layout/shape/swatch cells).

## 4. Out of scope

- Value read-outs beside sliders, a custom slider, and the Custom Shape button's styling.
- The `TextStyleSheet` (full editor) and `FilterStripView` — separate sheets, not panels.
