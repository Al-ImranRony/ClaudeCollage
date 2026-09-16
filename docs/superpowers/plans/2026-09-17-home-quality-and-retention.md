# Home tab: quality and retention plan

## Context

**Status (2026-09-17):** phases 1–4 implemented on branch `feat/home-retention` (worktree `.claude/worktrees/home-retention`). Left open on purpose: the `markExported` hooks in the three editor view controllers (another session holds uncommitted edits there; until they land the unfinished-project reminder never fires because `lastExportedAt` is never set), the device QA pass, and the App Group entitlement the widget still needs.

The user asked for a review of the Home tab (icons, components, collections, design, structure, appearance) and a plan that lifts it to the standard of SCRL, Unfold, Prequel and Canva, and that hooks users into long-term retention. Step 06 (deployment) is in progress; this is the last screen-level investment before submission.

Reviewed: every file in `Caroullage/Features/Home/`, the showcase components in `Core/DesignSystem/Components/`, `SampleContentCatalog`, the `TemplateService` preview API, both gallery tabs, the retention surfaces (widget, intents, Spotlight, notifications, rating), the two prior Home specs, Step 06's roadmap, and live screenshots of the 2026-09-07 build on the iPhone 17 simulator in light and dark (Home top, mid, bottom; Collage tab for comparison).

**Constraint from the user:** another session has uncommitted edits in `GridEditorViewController.swift`, `CarouselEditorViewController.swift`, `VideoEditorViewController.swift` and `VideoEditorPlaybackControlTests.swift`. Nothing in this plan touches those four files; the one hook that needs them (marking a project exported) is sequenced after that work lands.

## Review: what Home is today

Order on screen: brand lockup + Pro pill → "Create New" (four grey chips: Grid, Shapes, Video, Carousel) → hero pager (5 pages, auto-advance every 4 s) → "Suggested For You" (a lavender permission card, or a strip of grey layout wireframes once photo access is granted) → "Photo Collages" strip → "Video Collages" strip → "Carousels" strip. Then the page ends.

### What already meets the bar
- Photo-real previews rendered by the same `CollageRenderer` the editor uses; tapping opens exactly that structure. This is the app's strongest idea and it is real.
- Liquid Glass tab bar, gradient "Start Editing" pill, brand lockup, dark mode, Dynamic Type, VoiceOver, Reduce Motion, Low Power gating for loops. The fold budget is measured, not guessed.
- Onboarding already captures what the user makes (`CreatorKind`: carousels / reels / pinterest / fun), but only the photo strip uses it.

### Gaps against SCRL, Unfold, Prequel, Canva

1. **Home is identical on every launch.** Same five hero pages, nine templates, three videos, six carousels, forever. No recents, no "continue editing", no favourites, no "new this week", no seasonal awareness. Canva opens on your recent work; Unfold and SCRL sell collections and drops; Prequel leads with what is trending. Nothing here gives a returning user a reason to open the app.
2. **No personal content.** The only personal element, "Suggested For You", is a permission ask until answered, vanishes when denied, and when granted shows grey wireframes (`LayoutSchematicCell`) on a screen whose premise is photo-real output. It promises "one made from your photos" and shows a schematic.
3. **Create chips are generic and duplicated.** Four SF-symbol pills named by app structure. "Shapes" means nothing to a first-run user. The "+ Start Editing" pill 500 pt below opens a different five-item menu. Competitors name doors by destination (Post, Story, Reel, Carousel) with a format hint.
4. **Strips read as a small catalog, not collections.** Three flat rows of 140×176 cards (~3.5 visible) that duplicate the Collage and Carousel tabs. Titles truncate ("4-Up Square G…", "Caption He…"). The six template categories and four carousel types are never used on Home. Unfold's named collections and SCRL's packs are the model: a name, a cover, a reason, a "new" mark.
5. **Hero motion is a page scroll, not a cross-fade.** The 2026-08-29 spec asked for cross-fade; `advance(to:)` calls `scrollToItem(animated:)`, so every 4 s the card slides sideways while the user is reading it.
6. **Retention infrastructure is missing or dead.**
   - No analytics; the only tracker prints in DEBUG. Nothing shipped here can be measured.
   - `caroullage://` deep links are unwired: no `CFBundleURLTypes`, no `openURLContexts`, no `continue userActivity`. Widget taps and Spotlight results cold-launch to Home.
   - The Recent Collages widget always renders its empty state (App Group entitlement is account-gated, see `docs/step-06-account-gated.md`).
   - No local notifications beyond the trial reminder, although Step 06 phase 6.15 commits to seasonal drops "surfaced via In-App Events + push".
   - No Settings screen exists, so there is nowhere for a notification toggle, restore purchases, legal links or version.
   - `EntitlementStore` broadcasts nothing; every surface polls on `viewWillAppear`.
7. **Cold-start cost.** Previews render synchronously on the main actor on a cache miss (hero at 900 px, PNG); `SampleContentCatalog.imageCache` and `TemplateService.thumbnailCache` never evict.
8. **Dead weight.** `ProjectCardCell` and `HomeEmptyStateView` live in `HomeViewController.swift` (1,266 lines) but only `ProjectsViewController` uses them.

### Kept unchanged
Hero as focal point, four create doors above it, photo-real pipeline, tab bar and pill, fold discipline, `SampleContentCatalog` and its manifest, and every accessibility identifier tests depend on: `heroShowcase`, `heroPage-<id>`, `showcaseTemplate-/showcaseVideo-/showcaseCarousel-<id>`, `homeProButton`, `newProjectButton`, `polygonQuickStartButton`, `videoCollageButton`, `carouselQuickStartButton`, `startEditingButton`, `enableSuggestionsButton`, `suggestedLayoutsStrip`.

## Target Home (top to bottom)

```
Brand lockup ............................... [gear] [Pro]
Create New          Grid · Shapes · Video · Carousel   (kept; adds a one-line format hint, e.g. "1:1 post", "9:16 reel")
Hero                ordered by CreatorKind; cross-fade on auto-advance
Continue editing    [card][card][card]   See All       (only when projects exist)
From your photos    3 photo-real auto-collages, or a compact enable row
<Collection A>      "New this week" / in-season, e.g. "Autumn"    (config + date driven, NEW badge)
<Collection B>      CreatorKind affinity, e.g. "For Instagram carousels"
Photo Collages · Video Collages · Carousels          (become collections too; See All → gallery with category preselected)
Saved Collages · Saved Carousels                     (favourites; only when non-empty)
```

**Fold rule (iPhone 17, pill top at 733 pt):** first-run frames are byte-identical to today (recents and Saved collapse when empty). For returning users the recents strip sits between hero and suggestions at the existing 176 pt card height, so its cards peek under the pill (the "scroll for more" cue the budget already relies on) and no header is ever cut mid-word. Any shorter strip parks the next header inside the pill band; the 176 height is the constraint, not a choice. The suggestions strip stays at 83 pt (96 already overlaps by 4.7 pt).

## Decisions assumed (defaults; say so if you want a different one)

| Decision | Default | Why |
|---|---|---|
| Local notifications | Yes, opt-in only, capped (≤1 per 7 days, ≤2 per 30), never on first launch, never in `-UITestMode` | Phase 6.15 already commits to it; caps keep App Review and users comfortable |
| Create chips | Keep titles and identifiers, add a format hint sublabel | Renaming touches 11 languages and tests for little gain; the hint answers "what is Shapes?" |
| Suggestions | Render the user's photos into the top 3 layouts (on device) | The section's promise; no competitor does it; the engine and photo provider already exist |
| Favourites persistence | `UserDefaults` id list, not SwiftData | No relationships; a schema change risks the silent in-memory fallback in `ModelContainerFactory` |
| Content delivery | Bundled `home_collections.json`, week-deterministic rotation | No server exists; matches the "everything stays bundled" non-goal |
| Settings screen | Minimal SwiftUI sheet (notifications, restore, manage subscription, terms, privacy, version) | Needed to hang notifications off; also the missing in-app restore |

## Implementation

Four phases. Each is independently shippable, TDD (tests first, `CaroullageTests/Unit` + `CaroullageUITests/UI`), every UIKit surface on `Theme` tokens, every string through `String(localized:)` with all 11 languages landed by hand (`LocalizationTests` fails on one missing key; the catalog is not auto-synced, see `xcstrings-extraction-requires-sync` memory).

### Phase 1: Foundation (no visible change except deep links working)

1. **Analytics seam.** `Core/Services/Analytics.swift`: `protocol AnalyticsTracking`, `enum AnalyticsEvent` (homeSectionShown, collectionSeeAll, templateOpened(id, source), heroTapped, recentResumed, suggestionOpened, favouriteToggled, settingsOpened, restore(result), reminderScheduled/Opened, deepLinkOpened), `ConsoleAnalytics` copied from `ConsoleFunnelTracker` in `OnboardingViewModel.swift:163-177`, `Analytics.shared` settable for a spy. No SDK (would change `PrivacyInfo.xcprivacy` and `PrivacyManifestTests`).
2. **`EntitlementStore.didChangeNotification`**, posted from `setPremiumUnlocked` only on change (`EntitlementStore.swift:35-37`). Home observes it to refresh the Pro button and lock badges.
3. **`ProjectStore`** (`Core/Services/ProjectStore.swift:62-74`): `recentSummaries(limit:)` using a sorted `FetchDescriptor` with `fetchLimit` and `propertiesToFetch` (id, updatedAt, modeRaw, name, previewThumbnail) so blobs are not loaded; `projectCount()` via `fetchCount`; move `listSummaries()` onto the same descriptor. Add optional `lastExportedAt: Date?` to `CollageProject` (optional = migration-free, precedent `name`), `markExported(id:)`, `mostRecentUnexported(since:)`. **Call sites for `markExported` are the three editors next to `RatingPrompt.exportSucceeded`; those files are off-limits until the other session lands, so this hook is the last task of Phase 3.**
4. **`RecentPhotoProvider`** (`Features/AI/RecentPhotoProvider.swift:63-80`): add `RecentPhoto { assetID, image }`, `recentPhotoSet(limit:)`, and `recentAssetIDs(limit:)` (fetch only, no decode) for cache validity. Keep `recentPhotos(limit:)` for the three existing callers.
5. **Deep links.** `Core/Intents/DeepLink.swift`: `enum DeepLink { project(UUID), exportLast, collection(String), template(String), carouselTemplate(String), settings }` with `parse(URL)` and `parse(NSUserActivity)` (Spotlight `CSSearchableItemActionType` via `SpotlightIndexer.projectID(fromIdentifier:)`). Extend `IntentRouter.Request` (`CollageAppIntents.swift:32-36`) with matching cases; its pending queue already makes cold launch safe. `SceneDelegate`: handle `connectionOptions.urlContexts` / `userActivities` in `willConnectTo` after `start()`, plus `openURLContexts` and `continue userActivity`. `AppDelegate`: become `UNUserNotificationCenter` delegate, route `userInfo["deepLink"]`. `project.yml` `info.properties`: `CFBundleURLTypes` with scheme `caroullage` (regenerate and commit `Info.plist`). `AppCoordinator.handle(_:)` (`AppCoordinator.swift:221-234`) gains arms reusing `openProject(id:)` (`:649`), `openTemplate` (`:563`), `openCarouselTemplate` (`:609`). Add a `-deepLink <url>` launch argument under `-UITestMode` for UI tests. Widget links stay dead until the App Group entitlement exists; Spotlight and Live Activity links work immediately.
6. **Gallery preselect APIs.** `TemplateGalleryViewController.preselect(category:)` (state `selectedCategory` `:26`, `applyFilters` `:151-183`) and `CarouselGalleryViewController.preselect(type:)` (`selectedType` `:34`, `applyFilters` `:187-216`); both no-op the reload when the view is not loaded. Coordinator keeps weak refs to both galleries (like `homeViewController` `:38`), pops the tab to root, then selects it. `CategoryChipCell` (`TemplateGalleryCells.swift:17-52`) gets `categoryChip-<title>` identifiers and the `.selected` trait.
7. **Component hooks.** `SectionHeaderView` gains `titleIdentifier:` and an optional `badge:` ("NEW", `accentSoft` fill / `accentStrong` ink, same recipe as the selected category chip). Move `ProjectCardCell` and `HomeEmptyStateView` out of `HomeViewController.swift` into `Features/Home/ProjectCardCell.swift`.

Tests: `DeepLinkTests`, `EntitlementStoreNotificationTests`, `ProjectLibraryTests` extensions (ordering, limit, thumbnail intact with `propertiesToFetch`), `AnalyticsTests` (spy receives events), `DeepLinkUITests` (route → screen).

### Phase 2: Home information architecture

1. **Collections.** `Resources/Collections/home_collections.json` → `HomeCollection` (id, titleKey, subtitleKey?, kind photo/video/carousel, templateIDs, window {start "MM-dd", end}?, isNew?, creatorKinds?, galleryCategory? / carouselType?, priority?). `HomeCollectionCatalog` loads it (bundle-injected like `SampleContentCatalog.swift:60-66`; falls back to today's three strips from `featuredTemplateIDs` / `featuredCarouselIDs` if missing). `HomeCollectionPlanner.plan(_:now:creatorKind:calendar:maxStrips:)` is pure: drop out-of-window seasonal (year-wrapping compare), pin in-window and `isNew` to the top, boost `creatorKinds` matches, rotate the remainder by ISO week, cap at 5. Ids resolve against `TemplateService.shared.templates` / `.carouselTemplates` (dressed check as in `showcasedCarouselTemplates`) / `videoShowcases`; unresolved ids skip; an empty collection hides. Initial content authored from what exists: "New this week" (rotating pick), "Autumn" (seasonal category, window 09-01 to 11-15), "Holiday" (11-16 to 01-05), "For Instagram carousels" (matched + story carousels, affinity `.carousels`), "For Reels" (video showcases + story templates, affinity `.reels`), "Pinterest-ready" (grid + travel, affinity `.pinterest`), plus the three pillar collections. Debug override `-debug.homeDate YYYY-MM-DD` for seasonal QA.
2. **Strips → collections in Home.** One `makeStripSection` per planned collection, cell class by kind, the existing `photoCard/videoCard/carouselCard` dispatched through a `strips` array instead of three `case` labels. Identifiers `collectionStrip-<kind>-<id>`, `sectionHeader-<id>`, `collectionSeeAll-<id>`. Card size goes to 160×200 for photo/video and 240×200 for carousel (the size the 08-29 spec asked for; titles stop truncating), so `cardHeight` moves to 200 and the fold comment is re-derived and re-measured. Rebuild sections only when the planned id list changes; otherwise `reloadData`.
3. **Continue editing.** `recentProjectsProvider` → `store.recentSummaries(limit: 6)`, `onOpenProject` → `openProject(id:)`, "See All" → Projects tab. Reuses `ProjectCardCell` at 140×176. Hidden when `projectCount() == 0`. Identifier `collectionStrip-recents`.
4. **Hero by CreatorKind.** Pure `HeroOrdering.order(_:for:)` (stable partition: carousels → carousel first, reels → video first, pinterest → template first, fun/nil unchanged) applied in `makeHeroPages` (`HomeViewController.swift:386-430`); `applyOnboardingPreference` already calls `home.reload()`.
5. **Photo-real suggestions.** `Core/Rendering/SuggestionPreviewCache.swift` (`@MainActor`, owned by `AppCoordinator` beside `recentPhotos`): result cache keyed on joined asset ids (skips Vision until the library changes) and thumbnail cache keyed on template + asset ids + `rendererRevision` (make it internal), memory + PNGs under `Caches/SuggestionThumbnails`, pruned to ~12, in-flight guard. Render path copies the carousel navigator (`CarouselEditorViewController.swift:302-322`): build the request on the actor via `GridEditorViewModel(state:)` + `setImage` + `renderRequestSnapshot()` + `thumbnailScale(maxDimension: 300)`, `Task.detached(priority: .utility)` render (`CollageRenderer.render` is nonisolated and `@unchecked Sendable`), `MainActor.run` store. `suggestedLayoutsProvider` returns `[HomeSuggestion { template, thumbnail }]`; cells become `ShowcaseTemplateCell` (identifier `suggestedLayout-<template>`), dropping `LayoutSchematicCell`. The `.notDetermined` state shrinks to a single-row tinted button with the same copy at 83 pt so the fold does not move. Section title becomes "From your photos".
6. **Home wiring in `AppCoordinator.start()`** (`:47-83`): new closures `recentProjectsProvider`, `onOpenProject`, `onBrowseCollection`, `creatorKindProvider`.

Tests: `HomeCollectionPlannerTests` (window wrap, week determinism, rotation across weeks, affinity, cap, missing-file fallback), `HomeCollectionCatalogTests` against the bundle (every id resolves, every titleKey translated), `HeroOrderingTests`, `SuggestionPreviewCacheTests` (renders differ from the empty well via the `pixelData` technique in `ShowcasePreviewTests.swift:38-40`; second call does not re-render; changed ids invalidate). UI tests rewritten: `HomeShowcaseUITests.testHomeShowsHeroAndThreePillars` asserts one strip per kind by `identifier BEGINSWITH 'collectionStrip-photo-'`; `testTheCatalogHeaderClearsTheStartEditingPill` becomes "no `sectionHeader-*` intersects the pill band" so it holds with and without projects (the sim keeps projects between tests); route tests find cards by prefix; `TabBarShellUITests.testSeeAllSwitchesToTheCollageTab` taps `collectionSeeAll-<id>` and asserts `categoryChip-<x>.isSelected`; new `HomeRecentsUITests` (create via `newProjectButton`, back, `collectionStrip-recents` shows `projectCard-grid`, tap resumes). `AccessibilityAuditUITests.testHome` covers the new sections.

### Phase 3: Return triggers

1. **Settings sheet.** `Features/Settings/SettingsView.swift`, `SettingsViewModel.swift` (`@MainActor ObservableObject`, injected `PurchaseService`, `UserDefaults`, notification seam), `SettingsHostingController.swift` (`static func sheet`, `.large()` detent, id `settingsScreen`; same shape as `PaywallHostingController.swift:16-72`). Rows: Notifications toggle (requests authorization through the seam; denied → the Open Settings route Home uses at `HomeViewController.swift:576-578`; off → cancel all), Restore Purchases (`PurchaseService.restore()` `:229-242`, reusing `PaywallViewModel.restore` result strings so no new translations), Manage Subscription (App Store subscriptions URL), Terms and Privacy (lift `PaywallView.termsURL/privacyURL` into `Core/Services/LegalLinks.swift`), Version. Entry: a `gearshape` bar button (`homeSettingsButton`) left of Pro in `setupNavigationBar` (`:447-463`); Pro keeps `hidesSharedBackground`, the gear keeps the system glass. Rows use `.buttonStyle(.plain)` with identifiers on controls (see `swiftui-accessibility-id-propagation` memory).
2. **Reminders.** Generalise `TrialNotificationScheduling` → `LocalNotificationScheduling` (typealias kept), add `deepLink: URL?` to `TrialReminderRequest` written into `userInfo`, add `pendingIdentifiers()`. `Core/Services/EngagementReminderPolicy.swift` is a pure value over injected `UserDefaults` like `RatingPromptPolicy`: kinds `unfinishedProject` (project edited in the last 7 days, never exported, fires updatedAt + 24 h, never within 2 h of the last open, single identifier that replaces) and `seasonalDrop` (10:00 local on a collection's window start, once per collection id, never for a window already open); disabled → none; nothing in the first 24 h after onboarding; ≤1 per 7 days, ≤2 per 30. `EngagementReminderScheduler.refresh(...)` / `cancelAll()` driven from `AppCoordinator` on background (schedule) and foreground (record open, cancel unfinished); skipped under `-UITestMode`. Notification taps route through the Phase 1 deep-link path.
3. **`markExported` hooks** in the three editors beside `RatingPrompt.exportSucceeded` (`GridEditorViewController.swift:1274`, `VideoEditorViewController.swift:1586`, `CarouselEditorViewController.swift:494, 541`). **Do this only after the other session's edits to those files are committed.** Until then the unfinished-project reminder is gated off (policy returns none when `lastExportedAt` support is absent).

Tests: `SettingsViewModelTests` (stub gateway from `PurchaseServiceTests.swift:35-40`, spy seam), `EngagementReminderPolicyTests` (every rule with fixed dates and suite-named defaults), `EngagementReminderSchedulerTests` mirroring `TrialReminderTests`, `SettingsUITests` (gear → sheet, restore message, version label, premium launch hides nothing but Pro).

### Phase 4: Polish and delight

1. **Hero cross-fade.** Replace the body of `HeroShowcaseView.advance(to:)` (`:170-175`): stop visible players (a live `AVPlayerLayer` snapshots black), set the page dot, `UIView.transition(with: collectionView, .transitionCrossDissolve, Theme.Motion.slow)` around a non-animated `setContentOffset`, `updateLoopPlayback()` in completion. Swipe paging, dots sync, drag pause/settle, `HeroRotationController` and all identifiers untouched. Reduce Motion never reaches it (rotation is not started).
2. **Favourites.** `Core/Services/FavoritesStore.swift` (`@MainActor`, `UserDefaults` namespaced ids `photo:/carousel:`, insertion-ordered, `didChangeNotification`, testable with a suite-named defaults like `RatingPromptPolicyTests`). Cells stay single accessibility elements: "Save / Remove from Saved" via a context menu on every strip and gallery grid (mutate only in `willEndContextMenuInteraction` with `animator.addCompletion`; `UIPreviewParameters.visiblePath` at `Theme.Radius.lg`, per `uikit-context-menu-traps` memory) plus a VoiceOver custom action; a non-interactive `heart.fill` badge top-trailing on `ShowcaseTemplateCell` and in the top band of `BrowseTemplateCell`; "saved" appended to `accessibilityValue`. Home adds "Saved Collages" (160 wide) and "Saved Carousels" (240 wide) strips after the collections, hidden when empty. Video showcases are not favouritable in v1.
3. **Create chips.** `QuickStartChip` gains a `caption` sublabel (`Theme.Typography.caption`, `textSecondary`): "1:1 post", "freeform", "9:16 reel", "4:5 swipe". Same identifiers, same actions. Re-measure the chip row height in the fold comment.
4. **Performance.** Pre-warm the hero and first-strip previews off the main actor at launch (detached render, same pattern as suggestions) so a cold cache never hitches the first scroll; cap `SampleContentCatalog.imageCache` and `TemplateService.thumbnailCache` with `NSCache`-backed storage; shimmer placeholder (`cellWell` with a slow alpha pulse honouring Reduce Motion) instead of a flat well.
5. **Analytics wired** at every Home touchpoint, collection impression on first display, See All, hero tap, resume, suggestion tap, favourite toggle, settings, restore, reminder scheduled/opened, deep link opened.
6. **Device QA pass** (owed already per `STEPS_INDEX.md:455`): hero fade over a video page, scroll performance with loops, notification delivery and tap routing, iPad width.

## Files

**Add:** `Core/Services/{Analytics, HomeCollections, HomeCollectionPlanner, HeroOrdering, FavoritesStore, EngagementReminderPolicy, EngagementReminderScheduler, LegalLinks}.swift`, `Core/Intents/DeepLink.swift`, `Core/Rendering/SuggestionPreviewCache.swift`, `Resources/Collections/home_collections.json`, `Features/Settings/{SettingsView, SettingsViewModel, SettingsHostingController}.swift`, `Features/Home/ProjectCardCell.swift`, the unit and UI test files named per phase.

**Modify:** `Features/Home/HomeViewController.swift`, `HeroShowcaseView.swift`, `Coordinators/AppCoordinator.swift`, `App/SceneDelegate.swift`, `App/AppDelegate.swift`, `project.yml` + regenerated `App/Info.plist`, `Core/Intents/CollageAppIntents.swift`, `Core/Services/{ProjectStore, EntitlementStore, TrialReminderScheduler, TemplateService}.swift`, `Core/Models/CollageProject.swift`, `Features/AI/RecentPhotoProvider.swift`, `Features/TemplateGallery/{TemplateGalleryViewController, TemplateGalleryCells}.swift`, `Features/CarouselGallery/CarouselGalleryViewController.swift`, `Core/DesignSystem/Components/{SectionHeaderView, ShowcaseTemplateCell, BrowseTemplateCell}.swift`, `Features/Paywall/PaywallView.swift` (LegalLinks), `Resources/Localizable.xcstrings`, `AccessibilityConventionsTests.swift`, the Home/TabBar UI tests listed in Phase 2. The three editors only in Phase 3 step 3, after the other session lands.

## Risks
1. Localization gate: every new key × 11 languages by hand; budget it per phase, not at the end.
2. Home UI tests now run in two states (projects or not) on a shared simulator; assertions must be state-agnostic.
3. `lastExportedAt` is a schema change; `ModelContainerFactory` swallows migration failure into an in-memory store. Verify on a device with existing projects.
4. Swift 6 strict concurrency on detached renders and PhotoKit callbacks (`swift6-dispatchworkitem-mainactor-trap` memory); copy the carousel navigator and `RecentPhotoProvider` shapes exactly.
5. Cross-dissolve over a live player layer is device-QA territory.
6. Two right bar items on iOS 26 glass: confirm Pro's `hidesSharedBackground` renders beside a system gear.
7. Widget deep links stay dead until the App Group entitlement lands; set expectations.

## Verification (per phase, end to end)

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && cd /Users/irony/Claude/Projects/ClaudeCollage && xcodegen generate && xcodebuild test -project Caroullage.xcodeproj -scheme "Caroullage (Dev)" -destination "platform=iOS Simulator,name=iPhone 17" -derivedDataPath /tmp/caroullage-dd
```

- Unit suites green for the phase's new tests plus `LocalizationTests`, `PrivacyManifestTests`, `AccessibilityConventionsTests`, `ThemeContrastTests`.
- UI suites: `HomeShowcaseUITests`, `HomeHeaderUITests`, `TabBarShellUITests`, `AccessibilityAuditUITests.testHome`, `AppStoreScreenshotUITests`, plus the new `HomeRecentsUITests`, `SettingsUITests`, `DeepLinkUITests`. Run one simulator job at a time.
- Install the build from the explicit derived-data path (stat the Mach-O, not the bundle) and screenshot Home on iPhone 17 in light and dark, in three states: no projects (frames must match today's first-run fold), with projects (recents visible, no header in the 733–779 band), and photo access granted (three photo-real suggestions). Repeat at AX-XXXL Dynamic Type.
- Deep links: `xcrun simctl openurl <dev> caroullage://project/<uuid>` lands in the editor; Spotlight result for a project opens it.
- Reminders: with `-debug.homeDate` and a fixed policy clock, confirm scheduled identifiers via the spy in tests, then one real delivery on a device.
