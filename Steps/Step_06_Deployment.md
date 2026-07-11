# Step 06 — Deployment: Monetization, Compliance & App Store Launch
**Part:** 2 — Deployment (SECONDARY but ESSENTIAL — the entire launch sprint)
**Weeks:** 36–42
**Depends on:** Step 05 complete (Development 100% done)
**Unlocks:** Live app on App Store + post-launch growth

---

## Goal

Take the feature-complete, polished, simulator-ready app from Step 05 and ship it. Every task in this step is about turning a working app into a live App Store product: monetization (StoreKit 2 + paywall + onboarding funnel), compliance (privacy manifest, age rating, DSA, account deletion), localization, accessibility, App Store assets, Featuring Nomination, App Review submission, and post-launch monitoring.

> **Do not start this step until Step 05's Done Criteria are all checked.** Deployment is not a place to "finish features." If a feature is incomplete, it goes back to Step 05.

---

## How This Step Is Organized

This is one large step covering 15 phases. Treat each phase like its own mini-step. Work through them sequentially — most have dependencies on earlier phases (e.g., screenshots can't be taken until the final app icon is in place).

| Phase | Deliverable | Est. Days |
|-------|-------------|-----------|
| 6.1 | StoreKit 2 subscription implementation | 4 |
| 6.2 | Paywall screen | 3 |
| 6.3 | Onboarding funnel (industry-standard pattern) | 4 |
| 6.4 | Localization (11 languages) | 5 |
| 6.5 | Accessibility audit + fixes | 3 |
| 6.6 | App Store compliance (privacy manifest, age rating, DSA, etc.) | 3 |
| 6.7 | App icon, screenshots & App Previews | 5 |
| 6.8 | Watermark system (free vs. premium) | 1 |
| 6.9 | Rating prompt trigger logic | 0.5 |
| 6.10 | Performance profiling final pass | 2 |
| 6.11 | App Store Connect setup (metadata, ASO) | 2 |
| 6.12 | Pre-launch growth setup (Featuring, pre-orders, TestFlight) | 5 |
| 6.13 | Submission to App Review | 1 |
| 6.14 | Post-launch monitoring (first 30 days) | 30 |
| 6.15 | Ongoing operations (post-30-days) | indefinite |

Total active development time: ~6 weeks. Calendar time including App Review wait + the 30-day post-launch watch period: ~10 weeks.

---

## Phase 6.1 — StoreKit 2 Subscription Implementation

### Goal
A single source of truth for the user's subscription tier, real-time entitlement updates, and a clean restore-purchase flow. No race conditions, no UI showing locked features to paid users.

### Checklist
- [ ] Create `Core/Services/PurchaseService.swift` — `@MainActor` `ObservableObject`
- [ ] Load all 4 products at app launch:
  ```swift
  let products = try await Product.products(for: [
      "com.devron.claudecollage.premium.weekly",
      "com.devron.claudecollage.premium.monthly",
      "com.devron.claudecollage.premium.yearly",
      "com.devron.claudecollage.premium.lifetime"
  ])
  ```
- [ ] Handle purchase: `product.purchase()` → verify `Transaction.currentEntitlement`
- [ ] Handle restore: `AppStore.sync()`
- [ ] Listen to `Transaction.updates` async stream for real-time renewal/cancellation
- [ ] Persist subscription state to UserDefaults to avoid re-fetching every launch
- [ ] Register App Store Server Notifications V2 endpoint (minimal Cloudflare Worker is fine) for server-side validation
- [ ] Enable Family Sharing on all subscription products in App Store Connect
- [ ] Add 7-day free trial to yearly plan in App Store Connect; test with local StoreKit config

**Entitlement enum (single source of truth):**
```swift
enum SubscriptionTier {
    case free
    case premium  // weekly, monthly, yearly, or lifetime — same feature set
}

// PurchaseService.currentTier: @Published var — every gated view observes this
```

### Premium Gate Audit
- [ ] All premium templates check `PurchaseService.currentTier == .premium`
- [ ] All polygon shapes beyond the basic free set are gated
- [ ] 4K + HEVC export gated
- [ ] Carousel video slideshow export gated
- [ ] Image Playground generative background gated
- [ ] Watermark removal gated
- [ ] CloudKit sync — opt-in but free (drives retention)

### Trial-End Local Notification
- [ ] Schedule a `UNUserNotificationCenter` local notification for the trial end date during onboarding
- [ ] Copy: "Your free trial ends tomorrow — you'll be charged $24.99/year unless you cancel."
- [ ] Apple has tightened review on dark patterns here — keep copy honest

---

## Phase 6.2 — Paywall Screen

### Goal
The paywall is the highest-stakes screen in the app. Annual-default pricing, transparent terms, clear restore path. Modeled on the patterns that top freemium creative apps (CapCut, VSCO, Photoroom) use in 2025–2026.

**Framework:** **SwiftUI**. The paywall is a static form (header carousel + bullet list + plan picker + CTAs). SwiftUI gives faster iteration on layout, animation, and A/B test variants — and the screen has no gesture or canvas requirements. Present via `UIHostingController` from any UIKit editor.

### Checklist
- [ ] Create `Features/Paywall/PaywallView.swift` (SwiftUI)
- [ ] Create `Features/Paywall/PaywallHostingController.swift` (thin `UIHostingController<PaywallView>` wrapper for presentation from UIKit)
- [ ] Triggered when a free user taps any premium-gated feature
- [ ] Layout (top → bottom):
  - **Header:** 3 auto-scrolling preview cards of premium templates (1.5s per card)
  - **Title:** "Unlock ClaudeCollage Premium"
  - **Feature list (5 bullets):**
    - 200+ templates + carousel types
    - All polygon shapes + custom bezier
    - 4K video export, no watermark
    - Generative AI backgrounds (Image Playground)
    - Unlimited project saves + iCloud sync
  - **Plan picker:**
    - **Yearly — $24.99 ($2.08/mo)** — **pre-selected**, "Best Value" badge
    - **Monthly — $4.99**
    - **Weekly — $2.99** — framed as worse value (smaller chip, no badge)
    - **Lifetime — $49.99**
  - **CTA:** "Start 7-Day Free Trial" (if trial available) → switches to "Subscribe" once trial is used
  - **Below CTA:** subscription terms in 11pt gray text — exact price + renewal terms (App Store §3.1.1)
  - **Footer:** Restore Purchase | Terms | Privacy Policy
- [ ] Close X button visible from t=0 (do not hide; Apple has rejected apps for delayed/illegible close buttons)
- [ ] On successful purchase: dismiss paywall with success haptic; show "Welcome to Premium" toast
- [ ] On purchase failure: clear error message + retry; never silent
- [ ] Tested with local StoreKit config in Xcode

---

## Phase 6.3 — Onboarding Funnel

### Goal
Industry-standard "hard paywall after value preview" funnel. Drives ~25% trial-to-paid conversion (vs. ~8% for soft paywalls). Modeled on SCRL, VSCO, Picsart, CapCut current 2026 funnels.

**Framework:** **SwiftUI**. Each onboarding step is a small content view with a swipe pager. SwiftUI's declarative animation makes the value slides shine. Presented at app launch by `AppCoordinator` via `UIHostingController` if `!hasSeenOnboarding`.

### Funnel Sequence
1. **Welcome slide** — large logo + 1-line value prop
2. **Value slide 1** — animated demo of grid mode
3. **Value slide 2** — animated demo of carousel mode (this is your hero)
4. **Value slide 3** — animated demo of video + AI subject lift
5. **Personalization question** — "What do you create most?"
   - Instagram Carousels
   - TikTok / Reels
   - Pinterest Boards
   - Just for fun
   *(answer stored, used for first-template suggestion)*
6. **Permission priming screen** — "We need access to your photos to..." + Continue button → triggers `PhotosPicker` system prompt (no library permission needed; this is the first-tap UX hook)
7. **Gallery preview** — uses the user's own 3 most recent photos to render a sample carousel template — this is the "hook" beat
8. **Paywall** (Phase 6.2) — annual-default, hard paywall

### Checklist
- [ ] Create `Features/Onboarding/OnboardingView.swift` (SwiftUI `TabView` with `.page` style)
- [ ] Create `Features/Onboarding/OnboardingHostingController.swift` (`UIHostingController<OnboardingView>`)
- [ ] Implement all 8 steps with smooth page transitions
- [ ] **Skip** button visible on all value slides (small grey, upper-right corner) — Apple-compliant
- [ ] Track completion: `UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")`
- [ ] Onboarding shown only on first launch
- [ ] Analytics: log funnel step completion to TelemetryDeck for funnel optimization
- [ ] If user closes paywall: app drops into home screen with free tier active (do not force a relaunch)

---

## Phase 6.4 — Localization (11 Languages Day 1)

### Languages
English (base) + Spanish, French, German, Portuguese (Brazil), Japanese, Korean, Simplified Chinese, Hindi, Italian, Arabic.

*Apple's editorial team explicitly lists localization as a Featuring criterion. Shipping with 11 languages day 1 is a featuring signal.*

### Checklist
- [ ] Enable localization in Xcode project settings
- [ ] Export all strings via Xcode's String Catalog (`.xcstrings`, iOS 17+ standard)
- [ ] Use professional translation service (Smartling, Lokalise, or Crowdin — not Google Translate)
- [ ] All `Localizable.strings` keys translated
- [ ] Translate App Intent titles + descriptions (`AppShortcutsProvider.localizedAppShortcuts`)
- [ ] Translate widget titles + descriptions
- [ ] Translate paywall feature bullets and CTA
- [ ] **RTL layout support** for Arabic:
  - Test every screen by setting `Edit Scheme → Arguments → Application Language → Arabic`
  - Mirror layouts using SwiftUI's automatic RTL inversion; manually fix any directional icons (arrows, sliders)
  - Test all toolbars, frame navigators, and timeline scrubbers in RTL
- [ ] Date/number formatting uses `Locale.current` everywhere (never hardcode formats)
- [ ] App Store metadata localized in all 11 languages (Phase 6.11)
- [ ] Screenshots localized in all 11 languages (Phase 6.7)

---

## Phase 6.5 — Accessibility Audit

### Goal
Pass Apple's accessibility quality bar — this is checked for Featuring nominations and reviewed at App Review.

### Checklist
- [ ] **VoiceOver:** every interactive element has a `.accessibilityLabel` and (where helpful) `.accessibilityHint`
- [ ] **Dynamic Type:** all text uses semantic font styles (`Font.body`, `.headline`, `.title`) — zero hardcoded `.system(size:)`
- [ ] **Minimum tap targets:** 44×44pt for every button (verify with Accessibility Inspector)
- [ ] **Color contrast:** body text ≥ 4.5:1, large text ≥ 3:1 (Accessibility Inspector → Audit)
- [ ] **Reduce Motion:** disable spring animations + auto-scrolling paywall when `UIAccessibility.isReduceMotionEnabled`
- [ ] **VoiceOver canvas:** allow VoiceOver users to inspect each cell ("Cell 1, photo of beach, double-tap to edit")
- [ ] **Switch Control:** verify entire onboarding + first export flow is reachable via Switch Control
- [ ] **Bold Text / Increase Contrast:** test both settings; no layout breakage
- [ ] **VoiceOver rotor:** add custom rotor entries for "Cells" and "Frames" in editors

---

## Phase 6.6 — App Store Compliance (2026 Requirements)

### Privacy Manifest (`PrivacyInfo.xcprivacy`)
Required since May 2024; enforced for all 2026 submissions.

- [ ] Add `PrivacyInfo.xcprivacy` to main app bundle
- [ ] Declare collected data types: `NSPrivacyCollectedDataTypes`
  - None if no analytics PII; otherwise declare analytics events
- [ ] Declare Required Reason API usage:
  - `UserDefaults` → **CA92.1** (this app's own settings)
  - `fileTimestamp` → **C617.1** (PhotoKit file timestamps)
  - `diskSpace` → **E174.1** (checking space before video export)
  - `systemBootTime` → only if you log uptime metrics
- [ ] Confirm all third-party SDKs ship their own privacy manifests + signatures:
  - Firebase Crashlytics ✓
  - TelemetryDeck ✓
  - Any others added → audit

### Age Rating (New 2026 System)
- [ ] Complete the **new App Store Connect Age Rating questionnaire** (mandatory for all updates since Jan 31, 2026)
- [ ] Target: 4+ (no UGC moderation needed; no objectionable content)

### DSA Trader Status (EU)
- [ ] Declare trader status in App Store Connect → Business Information (required since Feb 17, 2025)
- [ ] Solo developers: declare as trader if commercial activity (selling subscriptions counts)

### Account Deletion (Guideline 5.1.1)
- [ ] **Skip if no sign-in offered.** ClaudeCollage doesn't require an account — all data is local + iCloud (user owns).
- [ ] If sign-in is later added: provide in-app account deletion within 1 tap

### Permission Strings (`Info.plist`)
- [ ] `NSPhotoLibraryAddUsageDescription` — "Save your collages directly to your photo library."
- [ ] `NSMicrophoneUsageDescription` — only if recording is supported (skip otherwise)
- [ ] No `NSPhotoLibraryUsageDescription` needed (we use `PhotosPicker`, not full library access)

### Misc Compliance
- [ ] No private API usage — verify via `otool -L $(find . -name *.app)` on the archive
- [ ] IDFA / AdSupport framework NOT linked (no ad SDK)
- [ ] Encryption export compliance: check **"Uses standard encryption only"** in App Store Connect
- [ ] Content rights: confirm all fonts, stickers, and template art are licensed (keep license docs in `/Licenses/` in the repo)

---

## Phase 6.7 — App Icon, Screenshots & App Previews

### App Icon
- [ ] Final 1024×1024 PNG (no alpha channel) — designed and added to `Assets.xcassets/AppIcon.appiconset`
- [ ] Auto-generates all required iOS icon sizes via Asset Catalog
- [ ] Tested at small sizes (29pt notification, 40pt Spotlight) for readability

### Screenshots (Required for Submission)
**6.7" iPhone 16 Pro Max (REQUIRED):**
- [ ] Screen 1 — Hero: carousel preview with swipe animation freeze-frame. Caption: "Create stunning Instagram carousels"
- [ ] Screen 2 — Grid + polygon shapes. Caption: "Geometric layouts that stand out"
- [ ] Screen 3 — Template gallery. Caption: "200+ hand-crafted templates"
- [ ] Screen 4 — Video collage. Caption: "Mix photos and videos seamlessly"
- [ ] Screen 5 — AI features: subject lift before/after. Caption: "One-tap background removal"

**12.9" iPad Pro (STRONGLY RECOMMENDED):**
- [ ] Same 5 screens, iPad-optimized layout

### Localized Screenshots
- [ ] Render screenshots with localized UI text + captions for all 11 languages
- [ ] Use a tool like Fastlane `snapshot` or `screenshot-builder` to automate

### App Preview Videos (Optional but converts +~20%)
- [ ] 3 App Previews (30s each, vertical 1080×1920):
  - Preview 1: Carousel creation (10s) + export (10s) + result on Instagram (10s)
  - Preview 2: Subject lift demo
  - Preview 3: Video collage with auto-beat-sync

---

## Phase 6.8 — Watermark System

- [ ] Create `Core/Rendering/WatermarkRenderer.swift`
- [ ] Composites "Made with ClaudeCollage" in bottom-right corner of exported files
- [ ] Watermark applied only when `PurchaseService.currentTier == .free`
- [ ] Watermark baked into export file (not shown in in-app preview)
- [ ] Watermark size: 4% of canvas height, white text with 50% opacity drop shadow
- [ ] On video exports: watermark composited via `CALayer` in `AVVideoCompositionCoreAnimationTool`

---

## Phase 6.9 — Rating Prompt Trigger Logic

- [ ] Call `SKStoreReviewRequest.requestReview(in:)` after the user's **first successful export**
- [ ] Guarded by: `PurchaseService.totalExportCount == 1` (track in UserDefaults)
- [ ] Never on first launch, never after an error
- [ ] Apple enforces the once-per-365-days rule; add your own guard as well to be safe

---

## Phase 6.10 — Performance Profiling Final Pass

Run Instruments on a real device (iPhone 13 minimum) and verify all metrics:

- [ ] **Allocations:** peak memory < 200 MB during full video editing on iPhone 12 (4 GB)
- [ ] **Core Animation:** 60fps sustained during all editor interactions on iPhone 13+
- [ ] **Leaks:** 0 leaks after a complete edit → export → home cycle
- [ ] **Time Profiler:** export pipeline CPU usage < 80% average (not pegged at 100%)
- [ ] **Launch time:** cold launch < 2.0s on iPhone 13
- [ ] **Energy:** export does not trigger thermal throttling on iPhone 12 within 30s of a typical video collage

Fix any failures before submission.

---

## Phase 6.11 — App Store Connect Setup

### Metadata (all 11 languages)
- [ ] **App name:** ClaudeCollage
- [ ] **Subtitle (30 chars):** "Carousel & Video Collage Maker"
- [ ] **Promotional text (170 chars):** updateable without submission — use for "New: Generative AI backgrounds!"
- [ ] **Description (4000 chars):** structured with feature sections, social proof, monetization terms
- [ ] **Keywords (100 chars):** strategic ASO selection (see below)
- [ ] **Support URL:** `https://devron.com/support/claudecollage`
- [ ] **Marketing URL:** `https://devron.com/claudecollage`
- [ ] **Privacy Policy URL:** `https://devron.com/legal/claudecollage/privacy.html`

### ASO Keyword Strategy
**Avoid:** `collage` alone (Pic Stitch + Layout dominate this keyword).

**Target intent verticals:**
```
instagram,carousel,reels,story template,photo grid,
photo dump,panoramic,scrl,unfold,canva alternative,
video collage,tiktok,9:16,4:5
```

### Categories
- Primary: **Photo & Video**
- Secondary: **Graphics & Design**

### App Review Notes
- [ ] Brief notes for App Review team:
  - Explain freemium model (free tier is fully functional)
  - Subscription pricing displayed clearly on paywall
  - Provide test credentials if any backend features require it (none expected)
  - Flag AI features as on-device only (Vision, VisionKit, Image Playground)

### Content Rights Declaration
- [ ] Confirm all bundled assets are licensed (fonts via Google Fonts SIL OFL, stickers via PixelTouch original art, templates via in-house design)

---

## Phase 6.12 — Pre-Launch Growth Setup

### Featuring Nomination (DO THIS FIRST — needs 12-week lead time)
- [ ] Submit Featuring Nomination in App Store Connect at least 8 weeks before launch (ideally 12)
- [ ] Pitch angle: highlight platform tech use — Image Playground integration, App Intents, Live Activities, Action Button compatibility
- [ ] Include 3 screenshots + 1 App Preview in the nomination
- [ ] Pitch a launch story tied to a seasonal event if possible

### Pre-Orders
- [ ] Enable pre-orders in App Store Connect (one of the few ways to accumulate downloads before the install counter starts)
- [ ] Set pre-order date 14 days before public launch

### In-App Event (Launch Week)
- [ ] Schedule an In-App Event: "Launch Week — 20 new templates"
- [ ] Surface in App Store search + Today tab during launch week
- [ ] Event runs 7 days starting on launch day

### TestFlight Cohorts
**Closed creator beta (50–200 testers):**
- [ ] Recruit Instagram + TikTok micro-creators (5k–50k followers) via DM outreach
- [ ] Offer lifetime Pro in exchange for: 1 review + 1 social post + bug feedback
- [ ] Invite via TestFlight email
- [ ] 2-week beta window

**Public TestFlight link (up to 10k):**
- [ ] Post on r/iOSBeta, Indie Hackers, Product Hunt Ship
- [ ] Generate one TestFlight public link (in App Store Connect)
- [ ] 10k cap = use as a soft pre-launch email list

### Apple Search Ads
- [ ] Set up campaigns bidding on competitor brand terms: SCRL, Pic Stitch, Unfold, Mojo, Layout from Instagram
- [ ] Daily budget: $50–$100 to start
- [ ] CPT typically low for these terms; incumbents underbid

### Creator Seeding
- [ ] Pay 10–20 micro-creators (10k–100k followers) $200–$1,000 per post
- [ ] Content format: creator's "boring grid" → ClaudeCollage carousel transformation
- [ ] Stagger posts across launch week to drive sustained downloads

### Product Hunt Launch
- [ ] Schedule launch for Tuesday or Wednesday
- [ ] Pre-stage assets: gallery, GIF demo, maker comment, hunter outreach
- [ ] Aim for #1 of the day (typically 3–8k downloads + Apple editorial social signal)

---

## Phase 6.13 — App Review Submission

- [ ] Version: `1.0.0 (1)` set in Xcode project
- [ ] Archive with **ClaudeCollage (Release)** scheme — NOT Debug, NOT Staging
- [ ] Validate archive in Xcode Organizer → 0 errors, 0 critical warnings
- [ ] Upload to App Store Connect
- [ ] Confirm:
  - All 11 languages have complete metadata
  - All 5 screenshots uploaded for 6.7" iPhone (and 12.9" iPad if doing iPad)
  - App Preview videos uploaded
  - Privacy details questionnaire completed in App Store Connect
  - Age Rating questionnaire completed
- [ ] Submit for App Review
- [ ] Monitor App Store Connect daily for reviewer feedback
- [ ] Respond to any reviewer questions within 24 hours

### Done Criteria for Submission
- [ ] All 3 critical UI tests pass (re-run before submission)
- [ ] All prior step unit/integration tests still pass (no regressions)
- [ ] Code coverage on `Core/Rendering/` ≥ 75%
- [ ] Instruments: 0 memory leaks on a full edit cycle
- [ ] Paywall shows correct pricing, trial terms, and restore button
- [ ] Onboarding shown on first launch only
- [ ] Watermark correctly applied on free exports; absent on premium exports
- [ ] App launches in < 2s cold on iPhone 13
- [ ] Arabic RTL layout renders correctly on all key screens
- [ ] Xcode Organizer validate: 0 errors, 0 critical warnings
- [ ] App submitted to App Store Review

---

## Phase 6.14 — Post-Launch Monitoring (First 30 Days)

### Daily Monitoring
- [ ] **Crashlytics dashboard** — day-1 crash-free rate target: ≥ 99.5%
- [ ] **App Store Connect reviews** — respond to every review within 48 hours
- [ ] **TelemetryDeck analytics** — funnel completion, most-used feature, churn signals
- [ ] **StoreKit analytics** — trial-to-paid conversion target: ≥ 25%

### Weekly Reports
- [ ] Compile a 1-page weekly report: downloads, paid conversions, top crashes, top complaints, top requested features
- [ ] Share with stakeholders + use to plan v1.1

### Hotfixes
- [ ] Any crash affecting > 0.5% of users → hotfix via `hotfix/` branch within 72 hours
- [ ] App Review will expedite hotfix submissions if you tag them as critical bug fixes

### Subscription Restore UI Test
- [ ] Add to UI test suite: `testSubscriptionRestoreFlow()` — verify the restore button works without crashing
  *(This test moves here from the original Step 05 because StoreKit only exists in production now)*

---

## Phase 6.15 — Ongoing Operations (Post-30-Days)

### Content Cadence
- [ ] **10 new templates per month** (mix of standard + carousel)
- [ ] Seasonal drops: Valentine's, Spring, Summer, Halloween, Holiday, Back-to-School
- [ ] Surface via In-App Events + push notifications

### Paywall Optimization
- [ ] A/B test paywall pricing via StoreKit promotional offers
- [ ] A/B test paywall copy and feature ordering via remote config
- [ ] Iterate quarterly based on conversion data

### Platform Expansion
- [ ] iPad layout optimization (side-by-side navigator + canvas)
- [ ] macOS Catalyst evaluation (is the engineering cost worth the additional revenue?)
- [ ] visionOS evaluation (templates are well-suited to immersive viewing)

### Community
- [ ] Monitor `#claudecollage` on Instagram + TikTok
- [ ] Repost user content to PixelTouch's social accounts
- [ ] Build a Discord or community space for power users

---

## Done Criteria (= App is Live and Healthy)

**Submission:**
- [ ] App approved by App Review
- [ ] Live on App Store in all configured regions
- [ ] All 11 languages live

**First 30 days:**
- [ ] Crash-free rate ≥ 99.5%
- [ ] Average rating ≥ 4.6
- [ ] Trial-to-paid conversion ≥ 25%
- [ ] All App Store reviews responded to within 48 hours
- [ ] No P0/P1 bugs outstanding

**Growth:**
- [ ] Featuring nomination submitted (whether selected or not)
- [ ] Apple Search Ads running on competitor brand terms
- [ ] Product Hunt launch executed
- [ ] At least 10 creator posts live across IG/TikTok
- [ ] In-App Event ran successfully during launch week

> When every Done Criteria is checked, deployment is complete. Move into Phase 6.15 (ongoing) and start planning v1.1.

---

## Final Note on the Development → Deployment Boundary

If during Step 06 you find a feature that "isn't quite right," resist the urge to fix it here. Deployment is about *shipping what you built*, not building more. Log the issue, ship the app, fix it in v1.1.

The one exception: **App Review blockers**. If App Review rejects the app for a missing feature or behavior (e.g., missing restore button, broken sign-in), fix that immediately and resubmit — that is part of deployment.

Everything else is v1.1.
