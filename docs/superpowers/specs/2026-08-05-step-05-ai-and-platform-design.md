# Step 05 — AI Features, App Surface & Final Polish

**Date:** 2026-08-05
**Status:** Approved, implementation starting with Batch A
**Baseline:** 353 unit+integration, 34 UI tests, all green (`d3e53bd`)
**Source brief:** `Steps/Step_05_AIFeaturesAndPolish.md`

## Environment findings that shape this plan

Established before planning, not assumed.

### 1. The AI is entirely on-device Apple frameworks

VisionKit, Vision, Core Image and Image Playground. No LLM, no API key, no
server, no per-use cost. Confirmed there is no LLM SDK anywhere in the project.

### 2. Vision's ML requests do not run in the simulator

Probed directly with `VNGenerateForegroundInstanceMaskRequest`,
`VNGenerateAttentionBasedSaliencyImageRequest` and `VNDetectFaceRectanglesRequest`
on a synthetic image:

```
foregroundMask FAILED — Error Domain=com.apple.Vision Code=9
                        "Could not create inference context"
saliency/faces  FAILED — Error Domain=NSOSStatusErrorDomain Code=-1
                        "Failed to create espresso context"
```

The simulator has no neural-engine backend. **Every Vision-dependent feature is
therefore device-only**, and four unit tests plus the `testSubjectLiftFlow()` UI
test named in the brief cannot pass as written.

**Consequence — the central architectural decision of this step:** all Vision I/O
sits behind a `SubjectSegmenting` protocol, and everything interesting is pure
logic on the far side of it.

- Vision calls become a thin adapter (`VisionSubjectSegmenter`), device-only.
- Mask compositing, layout scoring, sticker extraction geometry and error
  handling are pure and fully tested headlessly against a stub segmenter.
- The real Vision path is verified by owner device QA, with an explicit checklist.

This is better architecture regardless of the simulator, and it mirrors the split
the codebase already uses — pure engines (`CollageLayoutEngine`,
`VideoCompositionMath`, `BeatDetector`) with thin I/O adapters around them.

### 3. Image Playground needs iOS 18.2+ and Apple Intelligence hardware

Deployment target is 17.0, so it is `@available`-gated and reports unavailable in
the simulator. The brief's "do not promote it as a paid feature on devices that
cannot run it" rule is honoured by hiding, not disabling.

### 4. Part C was written before the Step 04.5 tab restructure

It describes Home as the project gallery. Home is now a discovery screen and the
gallery is the Projects tab. **Owner decision: keep the tabs.** Gallery polish
lands on Projects; Home gains the Suggested Layouts row.

### 5. CloudKit and App Groups are deferred to Step 06

Both need entitlements bound to the owner's Apple Developer account, and
cross-device sync cannot be verified here. **Owner decision: defer both.** Widgets
read a locally written snapshot file instead of a shared container, so the widget
work still lands in this step and only its data-sharing mechanism changes later.

Two Done Criteria in the brief are knowingly carried to Step 06:
CloudKit sync, and widget/app data sharing via App Group.

## Batches

Ordered by risk. Owner chose the AI foundation first: it is the headline, it
carries the constraint above, and Part C's Suggested Layouts row depends on it.

### Batch A — AI foundation (no new UI)

The service layer and every piece of pure logic, fully tested headlessly.

- `Core/Services/AIService.swift` — `@MainActor`, takes a `SubjectSegmenting`.
- `Core/Services/SubjectSegmenting.swift` — the protocol plus
  `VisionSubjectSegmenter` (foreground mask, face rects, salient rects).
- `Core/Rendering/SubjectCompositor.swift` — pure: apply a grayscale mask to an
  image to produce RGBA with a real alpha channel; crop to the subject's bounds.
- `Core/Rendering/LayoutSuggestionEngine.swift` — pure: score every
  `GridTemplate` against per-photo face and saliency rects, return the best five.
- `generativeBackgroundsAvailable` — availability probe only.

**Tests:** compositor (alpha present, masked-out pixels transparent, bounds
crop), suggestion scoring (faces preserved beats faces cropped, deterministic
order, count clamped, degenerate inputs), service orchestration against a stub
segmenter, and the availability probe returning false in the simulator.

### Batch B — AI canvas surfaces

- Lift Subject button on the per-cell panel; result draggable to a cell or saved
  as a sticker.
- Magic eraser: UIKit brush overlay, stroke → mask → Core Image fill, per-stroke
  undo through the existing `UndoStack`.
- `PersonalSticker` SwiftData model + personal stickers in the sticker picker.
- Generative backgrounds behind availability + premium gating.

### Batch C — App surface

- Three App Intents (`CreateCollageFromRecentPhotos`, `CreateStoryCarousel`,
  `ExportLastProject`) + `AppShortcutsProvider` + donations.
- Two widgets reading a local snapshot (App Group deferred).
- Spotlight indexing with `NSUserActivity` deep links.
- Drag-and-drop into cells and out of project cards.

### Batch D — Projects & Home (Part C)

- Projects tab: masonry grid, sort/filter/search, context menu (Rename,
  Duplicate, Export, Share, Delete) with destructive confirmation.
- Home: Suggested Layouts row powered by Batch A.

### Batch E — UX polish + critical flows (Part D)

Functional polish only — loading and error states, haptics coverage, Reduce
Motion, microcopy, performance. **Visual redesign stays in Step 05b**, which
owns the per-screen SCRL-grade pass and the app icon; duplicating it here would
mean doing the same screens twice.

Plus the brief's three critical UI tests, with `testSubjectLiftFlow()` adapted:
it drives the flow through the stub segmenter so it is meaningful in CI, and the
real Vision path is device-QA'd.

## Definition of done

- Full suite green at the end of each batch, not only at the end.
- Pure AI logic covered headlessly; Vision path covered by a device-QA checklist.
- No feature advertised on a device that cannot run it.
- CloudKit and App Groups explicitly handed to Step 06.
