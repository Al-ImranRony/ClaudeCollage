# Step 06 — items blocked on an Apple Developer account

Caroullage is being built through Step 06 without a paid Apple Developer
account or an App Store Connect record. Everything that *can* be done locally is
being done; everything that cannot is listed here so it is picked up the day the
account exists rather than discovered at submission.

Each entry says what is blocked, and what was done locally in its place.

---

## Phase 6.1 — StoreKit 2

| Blocked | Stand-in until then |
|---|---|
| Register the four products in App Store Connect | They are defined in `StoreKit/Caroullage.storekit`, wired into the **Caroullage (Dev)** run scheme, and a unit test asserts the app's product IDs match that file. |
| Enable **Family Sharing** on all four products | `familyShareable: true` is already set in the local configuration, so the app's handling of a shared entitlement can be exercised. |
| Add the **7-day free trial** to the yearly plan | The local configuration carries a `free` introductory offer of `P1W` on yearly; `PurchaseService.isEligibleForTrial(_:)` reads it through the gateway. |
| **App Store Server Notifications V2** endpoint (server-side validation) | Not started. The app verifies transactions client-side via StoreKit 2's own signature checking (`.verified` only), which is the correct client behaviour regardless; the server endpoint is defence against a jailbroken client and can be added at any time. |
| Real sandbox purchase testing (a sandbox Apple ID) | Local StoreKit testing covers purchase, cancel, pending, restore, renewal, and revocation. |

**Product identifier note.** The brief in `Steps/Step_06_Deployment.md` writes the
IDs as `com.devron.caroullage.premium.*`, while `StoreKit/Caroullage.storekit`
uses `net.pixeltouch.caroullage.premium.*`. The app follows the `.storekit`
file, since that is the artifact local testing actually runs against. The bundle
ID is `com.devron.caroullage`. **Product IDs do not have to match the bundle ID,
but they are permanent once created in App Store Connect** — pick the prefix
deliberately before creating them, and update `PremiumProduct.idPrefix` plus the
`.storekit` file together if the answer is `com.devron`.

---

## Phase 6.2 — Paywall

| Blocked | Stand-in until then |
|---|---|
| Real localized prices from the App Store | Prices come from the store objects the local configuration vends, so the paywall renders `$24.99` / `$4.99` / `$2.99` / `$49.99` exactly as it would in production — but only in the `en_US` storefront the config declares. |
| Automated coverage of the store-backed paywall | See "Local StoreKit does not reach automated tests" below. |
| Terms of Use and Privacy Policy URLs must resolve | The footer links point at the URLs named in the brief (`devron.com/legal/caroullage/…`). App Review rejects dead links, so these must be live before submission. |

---

## Phase 6.2b — Credits and the Special Offer

| Blocked | Stand-in until then |
|---|---|
| Registering the three consumables in App Store Connect | Defined in `StoreKit/Caroullage.storekit` as `net.pixeltouch.caroullage.credits.{single,pack5,pack15}` at $1.99 / $4.99 / $9.99. |
| **Credits surviving a reinstall or a new device** | They do not. The App Store never restores consumables, so `CreditStore` keeps the balance in `UserDefaults` — and the paywall says "credits stay on this device" *before* the user pays. **CloudKit private-database sync is the real fix** and is blocked on the same account; until then expect occasional "I lost my credits" support mail. |
| The Special Offer being a genuine promotional offer | It is currently a **second product** (`…premium.yearly.offer`, $14.99) sold from its own screen, which means it renews at $14.99 rather than the standard $24.99. With an account this should become a **promotional offer on the yearly product**, signed server-side, so it renews at the standard price. Until that swap, the copy is written to be true of what is actually sold: the struck-through figure is the standard plan's real price and the terms name the price actually charged. |

Consumables also cannot be Family Shared, and must never be described as a
subscription in the UI or in App Store Connect metadata — both are reflected in
the copy that ships.

---

## Local StoreKit does not reach automated tests

Xcode attaches `StoreKit/Caroullage.storekit` to the scheme's **Run** action, so
launching the app from Xcode (⌘R, Dev scheme) gives the paywall real products.
That configuration does **not** reach a test run:

- XcodeGen 2.45.4 writes `storeKitConfiguration` into the Run action only; the
  Test action has no equivalent key, and hand-patching the generated scheme's
  `TestAction` with a `StoreKitConfigurationFileReference` changed nothing.
- `SKTestSession(configurationFileNamed:)` from either test bundle resolves the
  file (a bogus name throws; the real one does not) but `Product.products(for:)`
  still returns an empty array, with or without retries.

So under `xcodebuild test` the paywall renders its honest "Plans are unavailable
right now" state. Coverage is split accordingly:

- **Unit tests** (`PurchaseServiceTests`, `PaywallViewModelTests`) cover the
  entitlement state machine and every string on the paywall against the gateway
  stub — 44 tests.
- **UI tests** (`PaywallUITests`) cover what does not need a store: a locked
  template opens the paywall, the close button works on the first tap, and the
  restore path and terms line are on screen.
- **Manual, before submission:** run the app from Xcode with the Dev scheme and
  confirm the four plans, the prices, the "Best Value" badge, the trial CTA, and
  a completed purchase. This is the brief's own "tested with local StoreKit
  config in Xcode" step and is the only part of 6.1/6.2 not automated.

One real bug came out of this: with no store behind the simulator,
`AppStore.sync()` never returns, so Restore sat there silently. `PurchaseService`
now bounds it (15s) and reports "The App Store didn't respond." rather than
hanging — which is also the right behaviour on a bad connection in production.

---

## Phase 6.4 — Localization

The String Catalog (`Caroullage/Resources/Localizable.xcstrings`, plus a small
one in `CaroullageWidgets/` because an extension cannot read the app's bundle)
ships all 11 day-one languages, and the project declares them as known regions,
so every `.lproj` is in the built app. Tests assert that no key is missing a
language and that no translation drops a format specifier — a translation that
loses its `%@` crashes when the string is used, and nothing else catches it.

**The translations need a human pass before submission.** The brief calls for a
professional service (Smartling, Lokalise, Crowdin); these were written in-house
and are good enough to demo and to test layout against, but two categories
should be reviewed by a native speaker who has seen the screen:

1. **Anything with a price or renewal terms.** These are legally load-bearing
   and are what App Review reads. The sentences are localized whole, per billing
   period, rather than assembled from a translated price and a translated noun —
   assembling them produces broken grammar in Japanese, Korean and Arabic — so a
   reviewer only needs to check complete sentences.
2. **Arabic and the CJK languages**, where register and line-breaking are easy to
   get subtly wrong.

**What is not localized yet.** This pass covered the launch-critical, reviewer-
facing surfaces: onboarding, the paywall, the special offer, the credits path,
the widget, and the App Intents (already `LocalizedStringResource`). The older
editor chrome — the export sheet's format and quality controls, the alert copy
in the editors, template category names — is still English-only and needs the
same treatment before submission. `Tools/` has no generator for the catalog; it
is edited directly, in Xcode's String Catalog editor.

Verified on the simulator in Spanish, Arabic and Japanese: onboarding and the
paywall render translated, and Arabic mirrors correctly (close button, feature
grid, footer and the page indicator all flip). The plan rows could not be
verified translated because the local StoreKit configuration does not reach an
app launched by `simctl` — see the section above.

---

## Blocked capabilities (entitlements the account unlocks)

These need a paid team to register identifiers in the Developer portal:

- **App Group** — the Recent Collages widget reads the app's snapshot. Until the
  group exists, `WidgetSnapshotStore` resolves the app's own container and the
  widget renders its empty state. (Deferred here from Step 05 batch C.)
- **iCloud / CloudKit** — project sync. (Deferred here from Step 05.)
- **In-App Purchase capability** — not required for local StoreKit testing, but
  required for a real purchase on device.
- **Push-updated Live Activities** — the export Live Activity runs locally
  today; remote updates would need a push key.

A free Apple ID can install on a physical device via 7-day personal-team
provisioning, but cannot enable any of the above.

---

## Later phases (recorded now, not yet started)

- **6.6** — the App Store Connect side: age-rating questionnaire, DSA trader
  status, encryption export compliance. The repo-side work (privacy manifest,
  permission strings, licence docs) is not blocked.
- **6.11–6.15** — metadata and ASO, Featuring nomination, pre-orders, TestFlight
  cohorts, Apple Search Ads, submission, and post-launch monitoring are entirely
  App Store Connect work.
