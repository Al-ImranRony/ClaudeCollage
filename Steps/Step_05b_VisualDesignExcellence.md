# Step 05b — Visual Design Excellence & App Icon
**Part:** 1 — Development (capstone)
**Weeks:** 35–37
**Depends on:** Step 05 complete (all screens exist)
**Unlocks:** Step 06 (Deployment — needs the final look + icon for App Store assets)

---

## Goal

Take the working, feature-complete app and make it **visually indistinguishable from a chart-topping App Store app** (SCRL, Unfold, Mojo, VSCO tier). Every screen becomes modern, minimal, and delightful, unified by an **orange (Claude) + white** brand identity used brilliantly wherever it fits. Ship a **custom, stunning app icon**.

This is the consolidation of all serious visual work. It runs at the *end* of development on purpose: a full per-screen redesign needs every screen to already exist. The lightweight design foundation (see below) was laid back at Step 01 so the app never *looked* raw in the meantime.

> **Two explicit product directives from the owner (2026-07-13):**
> 1. **App icon** — a stunning icon in an **orange-white theme, like the Claude icon**, that highlights **Collage + Carousel photo editing** as the app's main subject.
> 2. **Theme color = orange (same as Claude)**, used brilliantly everywhere it fits; every screen gets a **stunning, interactive yet minimal** color theme and design → a modern, simplistic UI.

---

## Already done — the design foundation (Step 01 follow-up, 2026-07-13)

Do **not** rebuild these; extend them. Lives in `Caroullage/Core/DesignSystem/`:

- **`Theme.swift`** — `Theme.Color` (semantic, dynamic light/dark; **brand accent = Claude orange**), `Theme.Typography` (SF Pro Rounded, Dynamic-Type scaled), `Theme.Spacing` / `Radius` / `Elevation` / `Motion`. `UIView.applyCardShadow()`.
- **`Haptics.swift`** — `@MainActor Haptics` with prepared generators + semantic API.
- **`AppAppearance.swift`** — global tint + nav-bar appearance, applied in `SceneDelegate`.

First adopters already themed: Home (cards/empty state), `GridEditorControls`, toast. Everything else should reach the same bar in this step.

---

## Part A — The App Icon

- [ ] Design a distinctive icon: **orange→white** palette echoing the Claude mark; motif communicates **collage grid + carousel/swipe** (e.g. overlapping photo frames fanning into a swipe, or a grid morphing into a carousel dot row).
- [ ] Produce it as a **scalable vector master** (SVG/PDF) first, then render the full `AppIcon.appiconset` (all iOS sizes incl. 1024², dark + tinted variants for iOS 18).
- [ ] No text in the icon; legible at 40²; test on light and dark home screens.
- [ ] Add to `Assets.xcassets`; wire in `project.yml`. Verify it shows on the sim home screen.
- [ ] Produce 2–3 candidate directions, screenshot each on a sim home screen, and pick with the owner before finalizing.

## Part B — Brand Color System (orange, used brilliantly)

- [ ] Lock the orange palette: primary, pressed, soft-tint, and a tasteful gradient partner (orange→amber or orange→coral — keep it minimal, avoid a clashing purple).
- [ ] Audit **every** screen for leftover system defaults (`.systemBackground`, `.tintColor`, `.label`, `.preferredFont`) and replace with `Theme.*` tokens.
- [ ] Apply the brand gradient to hero/CTA surfaces (primary "Create", export button, paywall in Step 06) — sparingly, for emphasis.
- [ ] Ensure WCAG-AA contrast for orange-on-white text/controls; verify full light + dark parity.

## Part C — Per-Screen Redesign (SCRL-grade, minimal + interactive)

For each surface: strong visual hierarchy, generous whitespace, purposeful motion, haptics on every meaningful interaction.

- [ ] **Home / gallery** — refined cards, section headers, sort/filter, a confident empty state, staggered appearance animation.
- [ ] **Mode selector / new-project entry** — a beautiful, tactile picker for Grid / Polygon / Template / Carousel / Video.
- [ ] **Grid & Polygon editor** — polished toolbar, selected-cell affordances, animated layout/shape switching, tool sheets.
- [ ] **Template & Carousel editor** — navigator, swipe preview, safe-zone overlay styling.
- [ ] **Video editor** — timeline + controls styling.
- [ ] **Export sheet** — progress, success animation, share affordances.
- [ ] **Shared components** — buttons, sheets, toasts, sliders, segmented controls, empty states: build a small reusable component layer on top of `Theme`.

## Part D — Motion & Micro-interactions

- [ ] Consistent screen transitions and sheet presentations.
- [ ] Spring-based selection/press feedback (pattern already on Home cards).
- [ ] Success/celebration moment on export.
- [ ] Every meaningful tap routed through `Haptics.*`.

---

## Done Criteria

- [ ] Custom app icon shipped and rendering on the home screen (light + dark).
- [ ] Zero raw system-default colors/fonts remain; every screen uses `Theme.*`.
- [ ] Orange brand identity reads clearly and tastefully across all screens, light + dark, AA-contrast verified.
- [ ] Side-by-side with SCRL/Unfold, the app holds its own on visual quality.
- [ ] All existing unit + UI tests still green; no perf regression (still < 200 MB, 60fps editors).
- [ ] A fresh full walkthrough screenshotted on-device for the owner's sign-off.

---

## Why here (serial placement rationale)

Placed as the **final Part 1 step, before Deployment**: the App Store assets, screenshots, and Featuring nomination in Step 06 all depend on the finished look and the app icon. Doing the comprehensive pass earlier would mean redesigning screens that don't exist yet; the foundation laid at Step 01 already prevents a "dev-mode" look during the interim.
