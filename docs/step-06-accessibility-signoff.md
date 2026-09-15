# Step 06 · Phase 6.5 — Accessibility sign-off

What was checked, how, and what only a person on hardware can still check.
Dates are when the check last ran green on `dev`. Everything automated re-runs
with the suite; the owner rows do not, and are listed so they are picked up
before submission rather than discovered at review.

Simulator: iPhone 17, iOS 26.5, Xcode 26.5. Route for every manual pass is the
first-export flow: onboarding → "＋ Start Editing" → Photos (or Home's Grid
chip) → fill a cell → Export → Save to Photos.

---

## VoiceOver

| Date | Check | How | Result |
|---|---|---|---|
| 2026-09-16 | Every interactive element has a label; no SF Symbol name is spoken | `AccessibilityAuditUITests` (`sufficientElementDescription`, 14 surfaces) + `AccessibilityConventionsTests` (every design-system component) | Green. Six symbol-name leaks fixed in Batch A (paywall glyphs, onboarding glyphs, sticker pack segments). |
| 2026-09-16 | The canvas is navigable: cells, text zones and stickers are elements with a spoken position; activation does what a tap does | `CanvasAccessibilityTests`, `VideoCanvasAccessibilityTests`, `GridEditorFlowUITests.testAnEmptyCellIsAButtonVoiceOverCanPress` (XCUITest reads the accessibility tree; it finds `buttons["Empty cell 1 of …"]`, presses it, and the picker opens) | Green. |
| 2026-09-16 | Every gesture has a custom action (swap; nudge; delete / larger / smaller / rotate) | `CanvasAccessibilityTests` — each action mutates the model through the same callbacks as its gesture and records one undo snapshot | Green. |
| 2026-09-16 | Rotors: **Cells** on the canvas, **Frames** on the carousel navigator | `CanvasViewAccessibilityTests.testTheCellsRotorWalksTheCellsInOrderAndStopsAtTheEnds`; the Frames rotor walks visible `CarouselFrameCell`s | Green (Cells); Frames by construction — see owner rows. |
| 2026-09-16 | Toasts are announced | `showToast` posts `.announcement` | By construction. |
| — | **Owner, on device:** VoiceOver on, first-export flow end to end; confirm the rotor lists Cells (and Frames in the carousel editor) and that a sticker's actions rotor lists nine actions | Settings → Accessibility → VoiceOver | _Not yet run — the simulator cannot run VoiceOver itself._ |

## Switch Control

| Date | Check | How | Result |
|---|---|---|---|
| 2026-09-16 | Every element is focusable and every gesture-only operation has an action, so the flow is reachable by construction | The VoiceOver rows above — Switch Control consumes the same elements, traits and actions | By construction. |
| — | **Owner, on device:** Switch Control with one switch, first-export flow; confirm the canvas's custom actions appear in the item menu | Settings → Accessibility → Switch Control | _Not yet run._ |

## Dynamic Type

| Date | Check | How | Result |
|---|---|---|---|
| 2026-09-16 | No hardcoded SwiftUI size; every UIKit label re-scales live; `Font.theme*` carries a text style | `grep '\.system(size: [0-9]'` is empty; `AccessibilityConventionsTests` (third convention); `AccessibilityAuditUITests` (`dynamicType`) | Green with recorded exceptions (see the test's `knownIssues`: the nav bar's capped Done, the export header capped like a nav bar, image-only buttons' empty internal labels, the paywall's feature list which the audit measures before its grid re-lays out). |
| 2026-09-16 | No layout breakage at the largest accessibility size | `AccessibilityWalkthroughUITests` at `UICTContentSizeCategoryAccessibilityXXXL`, 11 screenshots attached to the result bundle | Route completes. First run found: overlapping rail labels, mid-word breaks in panel rows and section headers, four chips truncating, a sort chip breaking "Rec/ent", a sheet whose fifth row could not be reached, truncated "Save to P…", a hero caption under the page dots. All fixed (rows stack at accessibility sizes, sheets open large, one gallery column, the rail capped like a tab bar with the large content viewer, a scrolling sheet, scaled hero and tiles). Remaining by design: gallery hero captions over artwork truncate on one line. |
| 2026-09-16 | Compact controls offer the large content viewer | `LargeContentViewerTests` — the rail's tools and the timeline's header controls | Green. |

## Tap targets

| Date | Check | How | Result |
|---|---|---|---|
| 2026-09-16 | Every control is at least 44×44pt | `AccessibilityConventionsTests` (`point(inside:)` probe at ±22pt); `AccessibilityAuditUITests` (`hitRegion`) | Green. Fixed in Batch A: panel close (28), timeline controls (32×24), rail tools (58×37), context chip (78×25), filter chip (~34), camera close (40), Skip / Cancel / Restore / Terms / Privacy, tertiary ThemeButtons. |

## Colour contrast

| Date | Check | How | Result |
|---|---|---|---|
| 2026-09-16 | Body ink ≥ 4.5:1, large text and UI ≥ 3:1, both appearances | `ThemeContrastTests` (8 tests, since Step 05b) | Green. |
| 2026-09-16 | **Increase Contrast:** both inks ≥ 7:1 (AAA) on every surface; separators and the accent ≥ 4.5:1 | `ThemeContrastTests` high-contrast block; `Theme.Color.dynamic(light:dark:lightHigh:darkHigh:)` on `textSecondary`, `separator`, `accent` | Green. Light: secondary ink 8.6:1, separator 5.3:1, accent 8.6:1. Dark: 11.1 / 6.9 / 9.7. |
| 2026-09-16 | Increase Contrast on the simulator, by eye and by pixel | `xcrun simctl ui <device> increase_contrast enabled`, then `VisualWalkthroughUITests` (Home, the three tabs, the grid editor, the export sheet) with the setting on and off | Route completes both ways, no layout breakage. The Projects count label (secondary ink on white) samples `#48474D` with the setting on — the `#4B4B53` variant, anti-aliased — against the normal `#6E6E77`; the two crops are visibly different greys. |
| 2026-09-16 | The audit's contrast check | `AccessibilityAuditUITests` (`contrast`) | Green with recorded exceptions — the audit samples pixels, so anything clipped, straddling the screen edge or below a fold is skipped (`isHittable` and wholly on screen), and four boundary/glass samples are listed with their sampled values. |

## Reduce Motion

| Date | Check | How | Result |
|---|---|---|---|
| 2026-09-16 | Every animation answers the setting | Review of every `UIView.animate` / `withAnimation` / symbol-effect site outside `Theme.Motion`: all route through `Theme.Motion.duration` and the `effectiveSpring*` pair; repeating or auto-advancing motion (rail emphasis, hero rotation, paywall auto-advance, looping video) checks `Theme.Motion.isReduced`; presses answer with opacity via `setPressed` | Two hand-rolled presses (the "+" pill, the Home header) moved to `setPressed` in Batch D. |
| — | **Owner, on device:** Reduce Motion on — the active tool's icon does not bounce, Home's hero does not auto-advance, the paywall's hero does not auto-advance, a press dims rather than shrinks | Settings → Accessibility → Motion | _Not yet run._ |

## Bold Text

| Date | Check | How | Result |
|---|---|---|---|
| 2026-09-16 | Every font is a system font (`Theme.Typography` builds on `UIFont.systemFont`; SwiftUI on `.system(_:design:weight:)`), which the system emboldens itself | Code review; the walker's font checks | By construction. |
| — | **Owner, on device:** Bold Text on — Home, the grid editor with a panel open, the paywall; nothing clips | Settings → Accessibility → Display & Text Size → Bold Text | _Not yet run — no simulator toggle exists (`simctl ui` offers appearance, content size and increase contrast only)._ |

---

## On-device passes owed to the owner

As with every hardware QA in this project, these are the owner's, on a free-account install:

1. VoiceOver — first-export flow; the Cells / Frames rotors; a sticker's nine actions.
2. Switch Control — first-export flow with one switch; the canvas's actions in the item menu.
3. Bold Text — Home, the editor with a panel, the paywall.
4. Reduce Motion — the four behaviours listed above.

Record the date and result in this file when done.
