# Caroullage — Launch Readiness Plan

**Date:** 2026-11-02 (rev. 2 — organic-first, spend gated on $100 revenue) · **Branch at writing:** `dev`
**Developer account:** enrolment started 2026-11-02.

## Goals and the spending rule

| Milestone | What | How we get there | Paid spend |
|---|---|---|---|
| **M0** | Approved on the first App Review submission | Phases 0–1 | $99 developer fee only |
| **M1 — the gate** | **$100 in customer purchases** (gross, App Store Connect → Sales & Trends) | Organic only: Phases 2–4, launch weeks | **$0** |
| **M2** | 100 purchases | M1 traffic + revenue-funded ads (Phase 6) | Funded by proceeds |

Owner's rule: **no money on ads or promotion until real users have paid $100.**
This is a good rule — it proves people pay before money is spent to find more of
them — so the plan is rebuilt around it:

- Everything before M1 is free: store-page quality, content, pre-orders, creators
  paid in lifetime codes (not cash), community launches.
- M1 alone is a small sample (≈ 5–40 purchases). The gate therefore also checks
  the funnel is healthy before spending (Phase 6.1), so the first ad dollar goes
  into a funnel that converts.
- After M1, spending grows only as fast as the numbers justify (reinvestment ladder, Phase 6.2).

Nothing can *guarantee* App Review approval — it is a human judgement. Phase 1
removes every rejection cause we control.
**Estimates:** first-pass approval 65–75% today → **90%+** after Phase 1.
Reaching M1 ($100) within 30 days of launch, organic only: **≈ 50–65%** if Phase 4
is done properly, ≈ 25–35% without it.

---

## Phase 0 — Apple Developer account (in progress)

### 0.1 Decisions to get right during enrolment — hard to undo later

| Decision | What to know | Recommendation |
|---|---|---|
| **Individual or Organization** | The App Store shows the *seller name*. Individual = your personal legal name. Organization = the company name, but needs a registered legal entity, a free **D-U-N-S number** (can take days to weeks), a website on the company's own domain and an email on that domain. Converting Individual → Organization later is possible via Apple Support but slow. | If Devron is (or soon will be) a registered company, enrol as **Organization** now. If not, Individual is fine — don't wait weeks for a company just for the seller name. |
| **Which Apple ID** | The Account Holder is the only person who can accept agreements and is hard to transfer. | A dedicated Apple ID you'll control for years (not a personal throwaway, not an employee's). Two-factor auth on, at least two trusted phone numbers. |
| **Legal name** | Must exactly match your government ID; identity is verified (often through the **Apple Developer app** on iPhone). Mismatches stall enrolment. | Use the exact name on your ID/passport. |
| **EU DSA trader status** | If you sell in the EU as a *trader*, your **address, phone and email are shown publicly** on the EU App Store page. | Have a business address/phone/email ready (not your home) — or launch outside the EU first and add it later. |

### 0.2 Right after the account is approved — in this order

1. **Agreements, Tax & Banking** in App Store Connect: accept the **Paid Apps
   agreement**, add the bank account (in the account holder's / company's name;
   confirm your country and bank are supported), and complete the tax form
   (non-US: **W-8BEN** for individuals, **W-8BEN-E** for companies — claim treaty
   benefits if your country has a tax treaty with the US, otherwise 30% US withholding
   applies to US sales). *Without an Active Paid Apps agreement, in-app purchases don't
   load — for the reviewer too — and the app is rejected.*
2. **Enrol in the App Store Small Business Program** (apply in the developer account).
   Commission drops from 30% to **15%**. It is *not* automatic — apply immediately.
   This alone means $100 of sales pays you ~$85 instead of ~$70.
3. **Register the bundle IDs** `com.devron.caroullage` and `com.devron.caroullage.widgets`
   (Identifiers). If either was ever registered on the old PixelTouch team it can't be
   reused — check now, not at upload time.
4. **Create the app record** to reserve the name "Caroullage" before someone else does.
5. **Decide the product-ID prefix, then register the 8 products** (IDs are permanent).
   Recommended `com.devron.caroullage.*`. Change `StoreKit/Caroullage.storekit`,
   `PremiumProduct.idPrefix` and `CreditProduct.idPrefix` together — a unit test checks they match.
   One subscription group "Premium" (weekly, monthly, yearly, yearly offer); 7-day free
   trial on yearly; Family Sharing on subscriptions + lifetime, **never** on credits.
6. **Wire the repo to the new team** (Claude can do this once you send the IDs):
   `project.yml` `DEVELOPMENT_TEAM` (still `VS9574SDLX`, the old team), `Fastlane/Appfile`
   (`apple_id`, `team_id`, `itc_team_id` are blank), `Fastlane/Matchfile` (`git_url`).
   Remember: the Team ID is the certificate's **OU**, not the ID in parentheses.
7. Age rating (expect 4+), export compliance (`ITSAppUsesNonExemptEncryption = NO`), DSA status.
8. Sandbox tester account; run every purchase path once on a real device (Phase 1.6).

Full list of account-gated engineering items: `docs/step-06-account-gated.md`.

---

## Phase 1 — Review-proofing (M0)

Ordered by rejection risk. App Review's biggest buckets: Performance (2.1 —
crashes, broken flows, purchases that don't load), Legal (privacy/terms),
Design (4.3 spam/copycat), Business (3.1 subscriptions).

### 1.1 Legal pages a reviewer can open — *highest risk*
`Caroullage/Core/Services/LegalLinks.swift` points at
`devron.com/legal/caroullage/{terms,privacy}.html`, and the whole domain sits behind
a bot-check. A challenge page instead of a policy = rejection.
- Host both on a plain static host (GitHub Pages / Cloudflare Pages with the
  challenge off for `/legal/*`). Free — fits the $0 budget.
- Policy matches the app: no account, nothing leaves the device, photo access is
  local, StoreKit handles payment, anonymous usage analytics (if 2.1 ships).
- Terms reference Apple's standard EULA.
- **Done when:** both URLs return `200` HTML from a fresh network and the same
  URLs are in ASC and the description.

### 1.2 Guideline 4.3(b) — "indistinguishable from other apps"
Collage makers are a saturated category. Make the difference obvious in 10 seconds:
- Screenshots lead with **seamless carousel → video templates with animated text →
  draw-your-own shapes → cutout stickers**; plain grids last.
- Name/subtitle say "carousel" (Phase 3); review notes list the differentiators.
- **Done when:** a stranger can name two features no other collage app has from the first 3 screenshots.

### 1.3 Every promise is true
`PaywallClaimsTests` already guards paywall copy and screenshot counts. Extend to all text a reviewer reads:
- Description, promo text, captions: every number checked against the build.
- Nothing "coming soon" (the AI-background seam stays hidden).
- No trademarks ("Instagram", "TikTok") in name, subtitle, keywords, screenshots.
- Don't upload `Marketing/Screenshots/iPad-Pro-13-inch--M4/` — v1 is iPhone-only.
- **Done when:** `docs/launch/claims-check.md` (claim → evidence) is fully ticked.

### 1.4 Subscription & paywall compliance (3.1.1 / 3.1.2)
Already in code: ✕ from t=0, whole-sentence price/period/trial terms, Restore,
Terms/Privacy, credits "stay on this device" disclosure. Remaining:
- The special offer (`…yearly.offer`, $14.99, same group as yearly) must say it
  **renews at $14.99/year**, and the review notes explain when it appears.
- Credits never called a "subscription" anywhere.
- App fully usable free; a reviewer reaches content within 2 taps of dismissing the paywall.
- **Done when:** every paywall variant screenshotted in en, ar, ja shows price, period, trial, renewal, Restore, Terms, Privacy, ✕.

### 1.5 App Review notes
`docs/launch/review-notes.md`, pasted into ASC, plus a 60–90 s screen recording:
no login; optional photo access; exact taps to each premium feature and the
paywall; what credits are; when the special offer appears; what makes the app distinct.

### 1.6 Zero crashes, zero dead ends (2.1)
- **Device QA:** smallest iPhone, a mid phone, a Pro Max; iOS 17.x and 26.x. Covers
  the open items: video templates + smoothness, on-device a11y sign-off, Instruments memory during 4K/video export.
- **Sandbox purchase matrix:** each of 8 products → buy, cancel, Ask-to-Buy pending,
  restore on a 2nd device, trial start, credit spent + refunded on failed export, offline launch.
- **Hostile-reviewer pass:** photo access denied / Limited, airplane mode, low storage,
  AX-XXXL text, VoiceOver on paywall, kill mid-export.
- **External TestFlight**, 20–50 testers × 7 days (doubles as Phase 4 audience):
  crash-free ≥ 99.8%, no open P0/P1.
- Make the Fastlane `beta`/`release` lanes bump `CURRENT_PROJECT_VERSION` (it never durably bumps today).

### 1.7 Privacy manifest & nutrition label
If 2.1 adds analytics, update `PrivacyInfo.xcprivacy` (pinned by `PrivacyManifestTests`)
and the ASC label ("Usage Data — not linked, not tracking") in the same change.
**Done when:** the archive's privacy report matches the ASC label line for line.

### 1.8 Translation sanity
Native-speaker check of paywall + renewal sentences in each of the 11 languages; any
language not checked ships its store listing in English only (in-app localization stays).

---

## Phase 2 — In-app conversion (makes M1 reachable without ads)

With no ad budget, every visitor is precious. These changes raise how many installs
pay, and give the data the spend gate needs.

### 2.1 Analytics that report somewhere — *required for the gate*
`Core/Services/Analytics.swift` only prints. Wire **TelemetryDeck** (free tier,
privacy-first, no tracking prompt) behind it, plus funnel events:
`onboarding_step`, `paywall_shown(source)`, `paywall_product_selected`,
`purchase_started/succeeded/cancelled(product)`, `trial_started`, `credit_spent`,
`export_completed(kind)`, `share_completed`.
**Done when:** a dashboard shows install → first export → paywall → purchase by day.

### 2.2 Paywall at the moment of value
Show a soft, dismissable paywall on **Export** of a design that used premium
content or would carry the watermark; hero image = *their own design*
("Export this without the watermark"); offer the **$1.99 single credit** right there
as the easiest first purchase. **Done when:** `paywall_shown(source: export)` is live.

### 2.3 Pricing for the $100 gate
Weekly $2.99 · monthly $4.99 · yearly $24.99 (7-day trial) · lifetime $49.99 · credits $1.99 / $4.99 / $9.99.
- **No blanket launch discount.** At current prices $100 is ≈ 4 yearly *or* 2 lifetime
  *or* ~20 credits; discounting just moves the gate further away.
- Keep the yearly trial — but trials only become revenue on day 8, so expect M1 to
  lag first installs by about a week.
- The $14.99 special offer (exit intent) stays: it recovers users who said no.
- **Done when:** prices set in ASC; the dashboard separates trials from paid.

### 2.4 Watermark as free distribution
Free exports carry `WatermarkRenderer`'s mark — make it "Made with Caroullage",
readable on carousels, and end every export/share with "Remove watermark" → paywall/credit.
Every free user's post becomes a free ad.

### 2.5 Ratings early
`RatingPromptPolicy`: ask after the **2nd successful export** and after a purchase;
never at launch or after a failure. Add Settings → "Rate Caroullage". Ratings move
search rank — the main free traffic source.

### 2.6 Onboarding check with TestFlight data
Time to first preview < 30 s; if > 40% drop before the preview beat, cut a value slide.

---

## Phase 3 — Store listing & search ranking (free traffic engine)

Before M1, App Store search is the main traffic source, so this phase matters
more than in the paid version of the plan. Metadata goes in `Fastlane/metadata/<locale>/`
(none exists yet) so `deliver` uploads it and it's reviewed like code.

| Field | Recommendation |
|---|---|
| **Name (30)** | `Caroullage: Carousel & Collage` |
| **Subtitle (30)** | `Seamless posts, video templates` |
| **Keywords (100)** | Long-tail, no repeats of name/subtitle words, no trademarks: `seamless,panorama,swipe,post,maker,grid,layout,story,reel,photo,frame,shape,template,editor,text,edit` |
| **Promotional text (170)** | Changeable without review — use for "new templates this week". |
| **Screenshots** | Re-order the 6 framed ones: carousel → video → shapes → templates → timeline → home. |
| **App Preview video** | 15–25 s: carousel swipe → video template with animated text → custom shape. Biggest free product-page lever. |
| **Category** | Primary Photo & Video, secondary Graphics & Design. |
| **Localized listings** | Every checked language (1.8) is a separate set of search results — free reach in 10 more storefronts. |
| **Product Page Optimization** | After launch, A/B test the first screenshot (free, built into ASC). |

---

## Phase 4 — Free pre-launch audience (start now, while the account is pending)

All $0 cash. This is what makes M1 likely rather than lucky.

| # | Action | Target by launch |
|---|---|---|
| 4.1 | **App Store pre-orders** — submit 2–3 weeks before the public date; all pre-orders download on day 1, which lifts early search rank. | 300+ pre-orders |
| 4.2 | Short-form video (TikTok, Reels, Shorts), 1 post/day from real screen recordings: "carousel in 20 seconds", before/after, template reveals. | 30 posts |
| 4.3 | TestFlight testers from design / small-business / photography communities (follow each community's self-promo rules). | 50 testers, 10 who'll post on day 1 |
| 4.4 | One-page site with App Store badge, pre-order link, 3 video loops (same free host as legal pages). | Live |
| 4.5 | Micro-creators (5–20k followers, carousel/design niche): **lifetime offer codes** (ASC offer codes — no cash) for an honest post during launch week. | 5–10 confirmed |
| 4.6 | **App Store featuring nomination** (ASC → Featuring → Nominations), 3+ weeks before launch: design quality, accessibility work, 11 languages. | Submitted |

Offer codes and the nomination need the account — prepare the lists and copy now, send the day it's approved.

---

## Phase 5 — Submission and organic launch (to M1)

### Submission
1. Release build via Fastlane `release`, build number bumped.
2. Submit **with manual release**, ~2 weeks before the public date — a rejection never moves launch day.
3. If rejected: reply in Resolution Center the same day; fix-only resubmission; answer 4.3 with screenshots + notes of the differentiators.

### Launch weeks (no paid spend)
| When | Action |
|---|---|
| D0 | Release; pre-orders deliver; launch video on all channels; creators post. |
| D1 | Product Hunt; one Reddit post where self-promo days allow. |
| D0–D30 | 1 video/day; reply to every review within 24 h; new template or two each week + promotional text update. |
| Weekly | Product Page Optimization test on screenshot 1; tune keywords from ASC "Search" source data. |

### Daily dashboard (TelemetryDeck + ASC Sales & Trends)
- Cumulative gross sales vs **$100** (ASC Sales & Trends, ~1 day delay; trials excluded until they convert).
- Product-page conversion (impressions → installs), target ≥ 30% from search.
- Install → paywall view ≥ 60%; paywall view → purchase or trial ≥ 3%.

### If M1 is slow (organic levers only)
| Signal | Action |
|---|---|
| < $30 by D14 | Re-cut screenshot 1 + preview video first 3 s; double video posting; chase the creators who haven't posted. |
| Page conversion < 20% | New screenshot 1 via Product Page Optimization. |
| Paywall conversion < 1.5% | Make the export-moment paywall (2.2) the main one; test credit-first layout. |
| Rating < 4.3 | Fix release within 7 days; mention it in What's New. |

---

## Phase 6 — Revenue-funded promotion (after M1)

### 6.1 The gate — start paid spend only when all are true
- [ ] **≥ $100 gross purchases** in ASC Sales & Trends (≈ $85 proceeds with the Small Business Program).
- [ ] Paywall view → purchase or trial **≥ 2%** over at least 300 paywall views.
- [ ] Refunds < 5% of purchases.
- [ ] Rating ≥ 4.3 with ≥ 10 ratings.
- [ ] Crash-free sessions ≥ 99.5%.

If $100 is reached but a funnel check fails, fix the funnel first — ads would only
buy more of the same leak.

### 6.2 Reinvestment ladder (Apple Search Ads Advanced first)
Search Ads first because the person is already searching for an app like this and
cost per purchase is measurable inside Apple's own data.

| Step | Budget | Move to the next step when |
|---|---|---|
| 1 | **$100 over 14 days** (≈ $7/day) — the first $100 earned goes back in. Exact-match long-tail ("carousel maker", "seamless carousel", "photo carousel", "panorama post") + a small Discovery campaign to find terms. | Cost per purchase ≤ **70% of average first payment** (measured during M1) |
| 2 | $250 over 14 days; drop keywords above the target; add the best Discovery terms as exact match. | Same rule holds for 2 weeks |
| 3 | Up to **50% of the previous month's proceeds**; add Custom Product Pages per keyword theme (carousel vs video). | Same rule holds |
| 4 | Small creator *paid* posts (only the creator types whose free code posts drove installs in Phase 4). | — |

Stop rule at any step: if cost per purchase stays above target for 7 days, drop
back one step and fix the page or paywall before spending again.

### 6.3 Toward M2 (100 purchases)
With M1 traffic continuing plus Step 1–2 spend, 100 purchases typically follows within
4–8 weeks of M1. When reached: lock in what worked, start v1.1 (CloudKit credit sync,
server-signed promotional offers, App Group widget).

---

## Timeline

| Week | Claude | Owner |
|---|---|---|
| 1 (now) | 1.3 claims audit, 1.5 review-notes draft, 2.1 analytics, build-number bump, legal pages content | Enrolment (0.1); host legal pages (1.1); start daily videos (4.2) |
| 2 | 2.2 export paywall, 2.4 watermark, 2.5 rating triggers, 1.4 paywall screenshots | Account approved → 0.2 steps 1–8; send Team/ASC IDs; TestFlight external; device QA (1.6) |
| 3 | Wire new team IDs, Phase 3 metadata, screenshot re-order, preview-video storyboard, 1.7 manifest | Native checks (1.8), record App Preview, creator codes (4.5), featuring nomination (4.6) |
| 4 | Final regression, release build | Submit (manual release); pre-orders live |
| 5–6 | Fix anything review / TestFlight finds | Pre-order push, content daily |
| 6 | — | **Launch D0 — $0 ad spend** |
| 6–10 | Weekly metric reviews, fix releases | Organic launch to **M1 ($100)** |
| After M1 | Help set up Search Ads campaigns + keyword lists | Phase 6 ladder |

## Budget

| Before M1 | Cost |
|---|---|
| Developer Program | $99/yr |
| Hosting, analytics (free tiers), creator lifetime codes, Product Hunt, featuring nomination | $0 |
| **Total cash before $100 earned** | **$99** |

After M1 the spend comes from proceeds per 6.2, starting at $100.

---

## Definition of "ready to submit"

- [ ] Paid Apps agreement Active, tax + banking done, Small Business Program applied (0.2)
- [ ] All 8 products Ready to Submit with the final prefix (0.2)
- [ ] Legal URLs return 200 without challenge pages (1.1)
- [ ] Claims table fully ticked (1.3)
- [ ] Paywall compliance screenshots in en / ar / ja (1.4)
- [ ] Review notes + screen recording attached (1.5)
- [ ] Device + purchase + hostile matrices passed; TestFlight crash-free ≥ 99.8% (1.6)
- [ ] Privacy manifest == nutrition label (1.7)
- [ ] Every listing language checked or English-only (1.8)
- [ ] Analytics funnel visible on a dashboard (2.1)
- [ ] `fastlane deliver` dry-run clean (3)
