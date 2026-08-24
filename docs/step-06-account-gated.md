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
