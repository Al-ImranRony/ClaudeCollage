# Step 05 — AI Features, App Surface & Final Polish
**Part:** 1 — Development (FINAL Development Step)
**Weeks:** 31–35
**Depends on:** Step 04 complete
**Unlocks:** Step 06 (Deployment)

---

## Goal

This is the last Development step. Take the feature-complete editor from Step 04 and add the **table-stakes 2026 features** that separate a chart-topping app from an also-ran: on-device AI, App Intents, Widgets, Spotlight, CloudKit sync, drag-and-drop, and a final UX polish pass. By the end of this step, the app runs end-to-end in the simulator at the quality bar of SCRL — no monetization, no App Store assets, no localization. Those live in Step 06.

> **Do not start this step until Step 04's universal export sheet is in place.** AI surfaces and widgets call into the export system, and the polish pass touches every editor.

---

## Two Deliverables in This Step

1. **AI & Platform Integration** — VisionKit, App Intents, WidgetKit, CloudKit, drag/drop, Spotlight. The features that take the app from "competent collage tool" to "first-class iOS citizen."
2. **Final UX Polish** — Home screen refinement, empty states, transitions, microcopy, haptics, sound design. Every screen passes a fit-and-finish review.

---

## Part A: AI Features (`Features/AI/` + `Core/Services/AIService.swift`)

### Design Principle
All AI runs **on-device**. No server, no API key, no infra cost. Free in the basic tier (subject lift, magic eraser, AI auto-layout). Premium only gates the generative features that depend on Apple Intelligence (Image Playground).

**UI placement:**
- AI **canvas surfaces** (subject lift handle on a cell, magic eraser brush) — **UIKit**, embedded in the existing editor view controllers
- AI **modals/prompts** (generative background prompt input, suggested-layouts picker, photo→sticker confirmation) — **SwiftUI**, hosted via `UIHostingController`

### AIService Architecture

```swift
@MainActor
final class AIService: ObservableObject {
    // VisionKit (iOS 17+)
    func liftSubject(from image: UIImage) async throws -> UIImage  // returns subject with alpha
    
    // Vision + Core Image
    func eraseObject(from image: UIImage, at maskPath: CGPath) async throws -> UIImage
    func detectSalientRegions(in image: UIImage) async throws -> [CGRect]
    
    // AI auto-layout
    func suggestLayouts(for images: [UIImage]) async -> [GridTemplate]
    
    // Image Playground (iOS 18.2+, Apple Intelligence devices)
    var generativeBackgroundsAvailable: Bool
    func generateBackground(prompt: String, style: ImageGenStyle) async throws -> UIImage
    
    // Photo→sticker
    func extractSticker(from image: UIImage, tapPoint: CGPoint) async throws -> UIImage
}
```

### Checklist — Subject Lifting (iOS 17+)

- [ ] Create `Core/Services/AIService.swift`
- [ ] Implement `liftSubject(from:)` using `VisionKit.ImageAnalyzer` + `ImageAnalysisInteraction.subjects`
- [ ] Add **Lift Subject** button to the per-cell editor panel (visible only on iOS 17+)
- [ ] On tap: run analysis, show subject with transparent background; user can drag it to any cell or save as a sticker
- [ ] On iOS 16: show a tooltip "Update to iOS 17 to use Subject Lift" (do not hide the button — drive iOS upgrades)
- [ ] Performance target: < 1.5s for a 12 MP photo on iPhone 13

### Checklist — Magic Eraser

- [ ] Implement `eraseObject(from:at:)` using `Vision.VNGeneratePersonSegmentationRequest` for people and `Vision.VNGenerateForegroundInstanceMaskRequest` for general objects
- [ ] In-app flow: user paints over an object with a brush → mask generated → Core Image `CIPerspectiveCorrection` + inpainting fills the area
- [ ] **Brush UI** — UIKit, custom `UIView` overlay on the canvas with a `UIPanGestureRecognizer`; renders strokes into a `CAShapeLayer` mask. Brush precision matters → UIKit.
- [ ] Adjustable size (10–200pt) via a small SwiftUI slider sheet
- [ ] Undo per stroke (push mask snapshots to the existing UndoStack)
- [ ] Add Magic Eraser button to the per-cell editor panel
- [ ] Edge cases: if no mask is detected, show a clear error; never crash

### Checklist — AI Auto-Layout

- [ ] Implement `suggestLayouts(for:)`:
  - Run `VNDetectFaceRectanglesRequest` on each input photo
  - Compute saliency via `VNGenerateAttentionBasedSaliencyImageRequest`
  - Score each grid template by how well it preserves detected faces and salient regions when cells are filled with the photos
  - Return top 5 suggested templates
- [ ] **Suggested Layouts** carousel shown at the top of the mode selector when the user has just picked 3+ photos
- [ ] Each suggestion shows a thumbnail preview; tap to instantly create the project with that template
- [ ] Free tier — this is a hook, not a paywall gate

### Checklist — Generative Backgrounds (Image Playground, iOS 18.2+)

- [ ] Detect availability via `ImagePlaygroundViewController.isAvailable`
- [ ] Implement `generateBackground(prompt:style:)` using Apple's Image Playground framework
- [ ] **Premium feature** — show paywall on tap if user is not subscribed
- [ ] UI: text prompt field + style picker (Animation, Illustration, Sketch)
- [ ] Generated image is applied as the canvas background; user can regenerate with the same prompt
- [ ] Gracefully hide the feature on devices without Apple Intelligence — do not promote it as a paid feature on those devices (no false advertising)

### Checklist — Photo→Sticker Workflow

- [ ] In the photo picker, long-press a photo → "Extract Subject" menu item
- [ ] Runs `liftSubject(from:)` → adds the result to the user's personal sticker library
- [ ] Personal stickers appear in the sticker picker alongside bundled packs
- [ ] Stored in `SwiftData` as `PersonalSticker` model with reference to the image data

---

## Part B: App Surface Integration

### Checklist — App Intents (Siri, Shortcuts, Spotlight, Action Button)

- [ ] Create `Core/Intents/` folder
- [ ] Define 3 App Intents:
  - **`CreateCollageFromRecentPhotos`** — parameter: count (default 9); creates a new grid project with the user's N most recent photos
  - **`CreateStoryCarousel`** — parameter: photo count; opens the carousel editor with the photos pre-loaded into matched template
  - **`ExportLastProject`** — re-exports the most recent project to the last-used platform preset
- [ ] Register all 3 in `AppShortcutsProvider` so they appear in Spotlight and Shortcuts
- [ ] Add **App Intent Donations** after the user performs each action 3 times — surfaces them in Siri Suggestions
- [ ] Each intent has localized titles + descriptions (localization itself happens in Step 06)
- [ ] Test on real device: assign `CreateCollageFromRecentPhotos` to the iPhone 15 Pro Action Button

### Checklist — Widgets (`ClaudeCollageWidgets` target)

- [ ] Implement two widgets in the existing widget extension target:
  - **Recent Projects** widget — small/medium/large sizes; shows last 1/3/6 project thumbnails; tap → opens the project
  - **Photo of the Day** widget — small/medium; shows a curated photo from the user's library with an "Edit" button (uses `WidgetKit` Interactive Buttons, iOS 17+)
- [ ] Use App Group `group.com.devron.claudecollage` to share data between app and widget
- [ ] Refresh policy: timeline reloaded every 30 minutes + on app state changes
- [ ] Static fallback widget for iOS 16 (non-interactive)

### Checklist — Spotlight Indexing

- [ ] Use `CSSearchableIndex.default()` to index every saved project
- [ ] Indexed metadata: project name, template category, mode, last edited date, thumbnail
- [ ] Update index on `CollageProject.didChange`
- [ ] Tap a Spotlight result → deep-link into that project via `NSUserActivity`

### Checklist — CloudKit Sync (Opt-In)

- [ ] Create `Core/Services/CloudSyncService.swift` using CloudKit `CKContainer.default()` private database
- [ ] Sync `CollageProject` records (model snapshot + thumbnail; no photo binaries — those stay in PhotoKit)
- [ ] Toggle in Settings: "Sync Projects with iCloud" (default OFF — opt-in)
- [ ] Conflict resolution: last-write-wins for metadata, user-prompt for content conflicts
- [ ] Handle quota errors gracefully ("Your iCloud is full" message + link to Settings)

### Checklist — Drag-and-Drop Everywhere

- [ ] Add SwiftUI `dropDestination(for: Image.self)` to every cell in every editor
- [ ] Add `draggable()` modifier to project thumbnails on the home screen (drag a project into Messages to share)
- [ ] Support `Transferable` for `CollageProject` (custom UTI: `com.devron.claudecollage.project`)
- [ ] Test drag from Safari (image), Files, Photos, Messages, Notes into a cell

### Checklist — Live Activities (extends Step 04)

- [ ] Confirm video export Live Activity from Step 04 is working
- [ ] Add Live Activity for **long-running AI tasks** (e.g., AI auto-layout on 20+ photos) — same pattern, different attributes

---

## Part C: Home Screen Polish

The home screen is the first thing users see on every launch after onboarding. It must feel premium.

**Framework:** SwiftUI shell (navigation, header, empty state, sort bar) wrapping a UIKit `UICollectionView` for the masonry thumbnail grid. SwiftUI handles the chrome cleanly; UIKit handles the scroll-and-prefetch performance for potentially hundreds of project thumbnails.

- [ ] Project gallery: masonry-style 2-column `UICollectionView` (`UICollectionViewCompositionalLayout` with self-sizing cells) hosted in a SwiftUI `UIViewControllerRepresentable`
- [ ] Each card: thumbnail + mode badge (Grid / Template / Carousel / Video) + last-edited date + tiny tier ribbon if exported with watermark
- [ ] **Empty state** (no projects yet): SwiftUI — large hero illustration + headline "Your canvas, ready when you are" + 3 mode CTAs (Grid / Template / Video) directly tappable
- [ ] Long-press a project card → `UIContextMenuInteraction`: **Rename**, **Duplicate**, **Export**, **Share**, **Delete**
- [ ] Delete requires confirmation alert (destructive)
- [ ] **Sort/Filter bar** (SwiftUI): Most Recent / Oldest / By Mode + search by name
- [ ] **Suggested Layouts** row at the top (powered by `AIService.suggestLayouts`) when the user has 3+ recent photos — UIKit horizontal `UICollectionView`
- [ ] Pull-to-refresh (`UIRefreshControl` on the collection view) triggers a manual CloudKit sync (if enabled)

---

## Part D: UX Polish Pass — Every Editor

This is fit-and-finish. Walk every screen, every state, every gesture. The polish list:

### Animations & Transitions
- [ ] UIKit editor transitions use `UIView.animate(withDuration:usingSpringWithDamping:initialSpringVelocity:options:)` for spring physics on draggable elements (cells, stickers, frame thumbnails)
- [ ] UIKit screen transitions use custom `UIViewControllerAnimatedTransitioning` for the template-gallery-to-editor expansion (UIKit's equivalent of `matchedGeometryEffect`)
- [ ] SwiftUI surfaces (paywall, onboarding, settings) use SwiftUI's `withAnimation` + `matchedGeometryEffect` where appropriate
- [ ] Reduce Motion (`UIAccessibility.isReduceMotionEnabled`) honored throughout — fade replaces spring when ON
- [ ] No animation longer than 400ms (industry standard for "snappy" feel)

### Haptics
- [ ] Light tap haptic on every button press
- [ ] Selection haptic on layout picker
- [ ] Success haptic on export complete
- [ ] Error haptic on validation failure
- [ ] Use `UIImpactFeedbackGenerator` + `UINotificationFeedbackGenerator`

### Microcopy
- [ ] Replace placeholder strings (every "TODO" or "Lorem ipsum") with crafted copy
- [ ] Empty states: warm, action-oriented copy ("Add a photo to get started" not "No photos")
- [ ] Error messages: explain what happened + what to do ("Your photo is too small to crop — try a higher-resolution image")
- [ ] Use sentence case throughout (not Title Case) — modern iOS convention

### Loading States
- [ ] Every async operation has a loading state — never a frozen screen
- [ ] Skeleton loaders for the template gallery (gray cards with shimmer) instead of spinners
- [ ] Progressive image loading: low-res placeholder → full-res when ready
- [ ] AI operations show their estimated time ("This usually takes ~2 seconds")

### Error States
- [ ] Every failure path has a user-facing message + suggested action
- [ ] Network errors (template CDN): cached version shown + "Couldn't fetch new templates" banner
- [ ] AI errors: clear "Try a different photo" hint
- [ ] Storage full: link to Settings → iPhone Storage

### Sound Design (Optional)
- [ ] Subtle UI sounds for major actions (export complete, photo added) — off by default; toggle in Settings
- [ ] Audio uses `AVAudioSession.Category.ambient` so it never interrupts music

### Performance
- [ ] Profile every editor in Instruments → Time Profiler: no frame > 16.67ms during typical use
- [ ] Memory profile: < 200 MB during video editing on iPhone 12
- [ ] Image cache eviction: `NSCache` with 100 MB cap

---

## Critical UI Tests (`ClaudeCollageUITests/UI/CriticalFlowTests.swift`)

Three XCUITest flows — exactly the same as in the original Step 05 design. Don't expand this list. These three flows protect the user from the worst possible regressions.

- [ ] **`testNewGridProjectExportFlow()`** — launch → New Project → Grid → tap empty cell → pick photo from simulator → Export → "Saved to Photos" toast asserted
- [ ] **`testCarouselThreeFramesExportFlow()`** — launch → New Project → Carousel → Matched type → 3 frames → fill each → Export → "As Images" → ZIP export completes
- [ ] **`testSubjectLiftFlow()`** *(new — added because AI is now in Development)* — launch → New Project → Grid → tap cell → pick photo → tap "Lift Subject" → assert subject preview appears

> Note: The original Step 05 had a `testSubscriptionRestoreFlow()` UI test. That moves to Step 06 (Deployment), because subscriptions are a deployment concern.

---

## Unit Tests — Extend Existing Files

### `AIServiceTests.swift` (new file, integration tests)
- [ ] `testSubjectLiftReturnsImageWithAlpha()` — sample photo with a clear subject → returned image has alpha channel + non-empty pixel data
- [ ] `testEraseObjectShrinksMaskedRegion()` — paint a mask → erased output has fewer non-background pixels in the masked area
- [ ] `testSuggestLayoutsReturnsAtLeastOne()` — pass 3 photos → at least 1 template returned
- [ ] `testGenerativeBackgroundUnavailableOnNonAIDevices()` — on simulator → `generativeBackgroundsAvailable == false`; method throws clearly

### `CloudSyncServiceTests.swift` (new file)
- [ ] `testProjectSerializesToCloudKitRecord()` — project → CKRecord → project round-trip equals original
- [ ] `testSyncToggleOffSkipsUploads()` — disabled toggle → `sync()` returns immediately

### Coverage check
- [ ] Run `Cmd+Shift+U` with code coverage ON
- [ ] Verify coverage targets from the plan:
  - `Core/Rendering/`: ≥ 80%
  - `Core/Services/Template*`: ≥ 70%
  - `Core/Services/Carousel*`: ≥ 70%
  - `Core/Services/AIService.swift`: ≥ 50%
  - UI: ≥ 20%

---

## Done Criteria (= Development is Complete)

**AI features:**
- [ ] Subject lifting works on iOS 17+, gracefully falls back on iOS 16
- [ ] Magic eraser removes painted regions cleanly
- [ ] AI auto-layout suggests templates that respect detected faces and saliency
- [ ] Image Playground generative backgrounds work on Apple Intelligence devices; hidden on others
- [ ] Photo→sticker workflow adds extracted subjects to personal sticker library

**App surface:**
- [ ] All 3 App Intents appear in Spotlight, Siri Suggestions, and Shortcuts
- [ ] Both widgets render correctly in small/medium/large sizes
- [ ] Spotlight indexing surfaces saved projects in iOS Spotlight search
- [ ] CloudKit sync toggle works; projects sync across two signed-in devices
- [ ] Drag-and-drop works from Safari, Photos, Files, Messages into the editor

**Polish:**
- [ ] Every screen passes fit-and-finish review — no placeholder copy, no awkward states
- [ ] Haptics fire on every meaningful interaction
- [ ] All animations honor Reduce Motion
- [ ] Loading and error states cover every async operation
- [ ] Performance targets met (cold launch < 2s, video edit memory < 200 MB, 60fps editor)

**Tests:**
- [ ] All 3 critical UI tests pass
- [ ] All AI + cloud sync unit tests pass
- [ ] Code coverage hits targets in `Core/`
- [ ] Full test suite runs in < 60s on CI

**Simulator demo bar:**
- [ ] A reviewer who has never seen the app can pick it up in the simulator and create a polished carousel post in under 3 minutes
- [ ] An impartial reviewer comparing this against SCRL in the simulator cannot tell which app is more mature

> If every Done Criteria is checked, Development is complete. Proceed to **Step 06 — Deployment**.

---

## Hand-Off to Step 06

When you finish Step 05, the app is feature-complete and polished — but it has:
- No monetization (StoreKit is configured locally; no paywall, no entitlement gating)
- No onboarding funnel (the app drops straight into the editor)
- No localization (English only)
- No App Store assets (placeholder icon, no screenshots)
- No App Store Connect metadata
- No Featuring Nomination submitted

That is all Step 06. Step 06 is the launch sprint.
