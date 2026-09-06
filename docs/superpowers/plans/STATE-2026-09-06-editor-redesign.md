# Editor redesign — state as of 2026-09-06

Resume point for the two-plan editor redesign. Everything below is committed on
branch `editor-chrome-redesign` in the worktree
`/Users/irony/Claude/Projects/ClaudeCollage/.claude/worktrees/editor-chrome-redesign`.

**Merged into `dev` as `381ca59` (2026-09-06).** The worktree has been removed; the
`editor-chrome-redesign` branch ref is kept.

### Post-merge verification on `dev` (2026-09-07)

Both suites run against **committed** `dev` in a throwaway worktree:

| | Result |
|---|---|
| Unit | **958 tests, 0 failures** |
| UI | **87 tests, 1 skipped, 0 failures** (the PaywallUITests flake passed this time) |

Every done-criterion of both plans was checked against code and tests, and all are met. The one
gap found was **coverage, not behaviour**: the music lane is named in Plan 2's criteria alongside
the clip and text lanes and was the only one of the three with no test at all. Now covered, with
an assertion that the lane is actually LAID OUT rather than merely configured — without that,
deleting its `addArrangedSubview` left the row object alive and configured, and a text-only
assertion passed against a timeline showing no music lane.

> **The unit suite is RED in the main checkout, and it is not this branch.** An uncommitted
> `Localizable.xcstrings` there adds 5 keys with no translations, which
> `LocalizationTests.testEveryStringIsTranslatedIntoAllElevenLanguages` reports as ~110 assertion
> failures. Confirmed by provenance: the failing keys are absent from `dev` HEAD and present only
> in the working copy. Left alone — it is another session's work in progress.

---

## Where we are

| | Plan 1 — chrome + collage editor | Plan 2 — video timeline + timed text |
|---|---|---|
| Status | **Complete, 11 / 11** | **Complete, 10 / 10** |
| Doc | `2026-09-05-editor-chrome-and-collage-editor.md` | `2026-09-06-video-editor-timeline-and-timed-text.md` |

**Unit suite: 956 tests, 0 failures.** **Full UI suite run 2026-09-06: 83 tests, 1 skipped, 1 failure** — `PaywallUITests
.testTheCloseButtonIsThereFromTheFirstFrameAndDismisses`, load-sensitive, passes 4/4 alone, on a
path this branch never touches. `VideoEditorUITests` is 8/8.

### Plan 2 task status

| Task | State |
|---|---|
| 1 · `TextOverlay` timing | ✅ done, reviewed, 1 Critical fixed (fail-open) |
| 2 · Export honours timing | ✅ done, reviewed, cache bounded + coverage added |
| 3 · Preview honours timing | ✅ done, reviewed, observer lifecycle fixed |
| 4 · `VideoTimelineGeometry` | ✅ done, reviewed, coverage gaps closed |
| 5 · `VideoTimeline` view | ✅ done, reviewed, API defects fixed (edit phase, selection, play) |
| 6 · Video editor adopts chrome | ✅ done, spec + quality reviewed, 2 Critical playback bugs fixed, control coverage added |
| 7 · Wire timeline to document | ✅ done, reviewed, 3 defects fixed (drag death, frozen playhead, inert lanes) |
| 8 · Timing panel | ✅ done, reviewed |
| 9 · `startOffset` | ✅ done, reviewed, now reachable from the timeline |
| 10 · UI test updates | ✅ done — nothing had moved; added chrome coverage, found an a11y defect |

---

## Tomorrow's queue, in order

**Nothing is queued.** Both plans are complete and the pre-merge refactor has landed.

Carried forward for whoever picks this up next, in the owner's court rather than an
engineering task:

- **A clip can be shortened from the timeline but never lengthened.** The trailing clamp is the
  composition duration, and the ruler spans the composition — so the position meaning "longer
  than the composition" is physically off the right edge. Fixing it means deciding what the
  ruler spans (the composition, or the longest available SOURCE). The Trim panel's sliders do
  carry the full source range, so the capability exists and the two surfaces disagree.
- **Tier-3 text animation.** `TextOverlay.animation` is reserved and decoding; nothing reads it.
  Its own spec, per the design doc's Out of Scope.
- The rest of the debt list below.

---

## `EditorPanelPresenter` — done 2026-09-06

The last queued item before the merge. `openPanel` / `closePanel` / `animateStageResize` and the
two properties they lean on were verbatim identical in both editors, and now live in
`Caroullage/Core/DesignSystem/Editor/EditorPanelPresenter.swift`.

**A collaborator, not a base class**, as the Task 6 review recommended — the two screens'
`toolTapped` / `setupRail` / `revalidateSelection` share almost nothing.

The presenter **creates the collapsed-height constraint itself** (the owner just activates it
alongside its own), so the constraint-ordering trap is in one file rather than split between
owner and helper. It also **wires `EditorPanel.onClose` itself**, so neither controller can
route the panel's own close button around it; owners hook `presenter.onClose` instead, which is
what the video editor uses to drop the Timing panel's overlay id.

Behaviour-preserving: 956 unit tests and both editors' UI suites (10/10) unchanged.

---

## Task 10 — done 2026-09-06

**Nothing had moved.** Task 6's decision to preserve `videoLayoutButton` / `videoMusicButton` /
`videoAddTextButton` / `videoAddStickerButton` / `videoCanvas` / `videoExportButton` when the
toolbar became a rail did its job: every existing `VideoEditorUITests` case passed untouched. The
plan's Step 2 ("follow the controls into the rail") had no work in it.

So the task became adding the coverage the redesign lacked. Four new UI tests: the five-tool
rail is present AND hittable, a tool opens a panel that closes again, the preview can always be
paused, and the timeline is collapsed by default and expands. These exist because the unit suites
build the editor in a synthetic window — the real app path (navigation, hidden tab bar, safe
areas) is where this branch has twice shipped bugs no unit test could see.

### They immediately found a third

**`VideoTimeline`'s play/pause and expand controls are bare `UIControl`s** — not accessibility
elements, and carrying no `.button` trait. Both were typed `Other` in the accessibility tree, so
`app.buttons["videoPlayButton"]` matched nothing.

Not a test problem: **VoiceOver announced the only way to pause the preview as an unlabelled
container** rather than something you can press. Fixed in the app; being an element also stops
the chevron's inner image view leaking its SF Symbol name ("go down") into the tree. Pinned in
the unit suite so it cannot regress without a 15-minute UI run.

Diagnosed by dumping the real accessibility tree rather than guessing — the identifiers were all
present and correct, which is exactly why the failure looked like a test bug at first.

**Known flake, unrelated:** `PaywallUITests.testTheCloseButtonIsThereFromTheFirstFrameAndDismisses`
failed once in the full run on `waitForExistence(timeout: 5)` and passes 4/4 alone. Same family
as [[flaky-photos-success-moment-test]] — long-run load, not a regression.

---

## Tasks 8 and 9 quality review — done 2026-09-06

Reviewing Task 9's offsets surfaced a **Critical that had been in Task 7 since it landed**.

**1. Critical — timeline trimming destroyed the source in-point.** A lane is drawn in
COMPOSITION time and begins at the clip's entry; the trim it edits is in SOURCE time. Passing
the lane's numbers straight through as a `VideoTrim` rewrote the in-point to the lane's origin,
so a clip taken from the middle of its footage **jumped back to the head** the instant its
out-point was touched.

Only one edge moves per drag, so each is now converted against the OTHER, which the drag leaves
alone: trailing keeps the in-point (`trim.start + newDuration`), leading keeps the out-point
(`trim.end - newDuration`). Anchoring on the fixed edge is also what stops a drag **compounding**
— every tick recomputes from a value that tick cannot have changed. The result is clamped to the
SOURCE length, which the timeline's own composition-duration clamp says nothing about.

**Why Task 7's tests missed it:** every one of them trimmed a clip that already started at 0,
where the bug is invisible. Same shape as the drag-death defect — the test set up the one case
the bug does not reach.

**2. High — the timeline drew every clip at zero regardless of `startOffset`.** Once Task 9
landed, the timeline actively misrepresented the composition it is a picture of. Lanes now start
at their offset and the ruler spans the last clip to END rather than the longest one.

**This also answers "Task 9 has no UI".** Dragging a lane's leading edge now moves the clip's
entry, which is both what an NLE does and what the block's left edge means. Without it the block
would snap back to its old start on the next refresh and appear to move its right edge instead.
`startOffset` is reachable, not dead weight.

**3. Medium — `compositionDuration(cellDurations:)` was a trap, and is gone.** It took the plain
maximum, correct only while every cell starts together, and after fix (2) had no callers left.
Deleted rather than deprecated: a silently-wrong-with-offsets function sitting beside the right
one invites a future caller to pick it.

**4. Low — the Timing panel's overlay id is now cleared in `closePanel`**, so the invariant is
local to the panel's lifetime rather than spread across every caller that can change the
selection. No live defect: `EditorPanel.hide` detaches the steppers, so a stranded id was inert.

### Answers to the other queued questions

- **Stranded steppers: not reachable.** Every path that changes the selection closes the panel,
  and hiding it detaches the controls. Hardened anyway (4) because the invariant was non-local.
- **`timingCeiling`'s 60s fallback is arbitrary but harmless.** It only applies when there is no
  composition at all. If a window is typed against it and a shorter clip is added later, the
  stepper clamps what it SHOWS on the next open, and the next edit writes the clamped pair —
  silently truncating an out-point that was already past the end of the composition. Judged
  correct rather than sharp: an out-point beyond the composition means nothing.
- **Looping + offset** fills offset → end of collage, which matches "loop until the collage
  finishes". Pinned by a test.

---

## Tasks 8 and 9 — done 2026-09-06

### Task 8 — the Timing panel

`TimingStubPanelView` replaced by real numeric in/out refinement.

**Steppers, not text fields.** A decimal keypad in a bottom panel has no return key to dismiss
it and covers the very timeline being timed against. 0.1s steps refine a dragged window precisely
without one.

**"Whole Video" is not a convenience.** `nil` timing — "always visible" — is a real state a pill
drag can never reach, because a pill always has two edges. The panel is the only way back.

**Both bounds clamp so the window cannot invert**, sharing `VideoTimeline.minimumTrimDuration`
(made `internal` for exactly this) so typing and dragging cannot produce different minimums. This
matters more than it looks: `isVisible(at:)` treats an inverted window as ALWAYS VISIBLE
(fail-open by design), so an inverted window entered here would silently turn a timed caption
back into a permanent one.

Also strengthened the Style panel's test, which only COUNTED preset buttons — the exact gap a
Plan 1 review found. Every preset is now tapped and its effect checked.

### Task 9 — `startOffset`

The backwards-compatibility test was written first, as the plan asked, and every pre-existing
composition suite still passes untouched.

Four call sites had to agree: composition duration is the LAST cell to finish rather than the
longest; `insertLooping`'s `fillTo` became an absolute time rather than a length (so a looping
cell fills offset → end while a plain one stops at offset + duration); `CellTransition.startTime`
shifts by the offset, since it is relative to the CELL; and beat sync subtracts the offset,
because its `startTimes` are absolute.

**One plan instruction turned out to be belt-and-braces.** The explicit `insertEmptyTimeRange`
before the first insert makes no difference — inserting past a track's end already extends it
with empty time, and deleting the call changed no test. Kept for readability, with the comment
saying so plainly rather than implying a test guards it. This was caught by deliberately breaking
it; the test that was *supposed* to pin it could not tell the two apart, and its assertion
message was corrected rather than left overclaiming.

**Task 9 ships with no UI** — see the review queue above.

**Plan deviation:** the plan said append to `CaroullageTests/Unit/VideoCompositionTests.swift`,
which does not exist. Tests live in a new `VideoStartOffsetTests.swift`.

---

## Task 7 quality review — done 2026-09-06

Three defects, two visible on the first interaction with the feature.

**1. Critical — trimming and retiming did not work at all through a real gesture.**
`VideoTimeline` renders a drag *through its model*; it never moves a block itself. So the owner
is REQUIRED to feed each `onTrim` tick back via `setModel` for the block to follow the finger —
but `setModel` cancelled any in-flight drag (Task 5's defence against acting on stale indices).
Every drag therefore killed itself on its own first tick, `.committed` never arrived,
`commitInteractive()` never ran, and the edit was left applied **with no undo step** — undo
jumped past it to the start of the session.

The cancellation's real purpose is a change arriving from *elsewhere* that invalidates what the
drag captured. That is an identity question and is now checked by identity (clip index still
present and filled / pill id still present). Deliberately NOT by geometry: a drag changes its own
target's duration every tick, so validating that would cancel the drag it exists to protect.
Task 5's own `testReplacingTheModelMidDrag…` still passes.

**Why Task 7's tests missed it:** they called `onTrim` / `onRetimeText` directly. That proves the
handlers work but not that a real drag can reach them — the exact "test seam bypasses the broken
path" signature this run keeps hitting. Replaced with real gestures driven through the hosted
timeline; those failed before the fix.

**2. High — the playhead never moved during playback.** The periodic observer drove only the
canvas, so the timeline's playhead and its `0:00 / 0:08` readout sat frozen at the origin for the
whole video. Both now go through one `playbackTimeAdvanced(to:)`, which also updates the time
`refreshTimeline` re-pushes — otherwise any document change mid-playback yanked the playhead back
to wherever the last scrub left it.

**3. Medium — tapping an EMPTY lane raised five inert buttons.** It selected the slot, showing
Swap/Trim/Volume/Transition against a cell that has none of them; every one no-ops. The canvas
does not select an empty slot either. Only filled lanes are selectable now.

### Answers to the other queued questions

- **The duration cache is safe.** Every pick calls `setVideo(assetID: UUID(), …)` with a FRESH
  id, so a Swap can never resolve to a stale duration under a reused key. It grows unboundedly
  (an orphan Double per swap), which matches `assets`' own deliberate never-evict policy and
  costs nothing.
- **`refreshTimeline`'s frequency is not a problem — it is now a requirement.** Since the drag
  renders through the model, the per-tick `setModel` is what makes trimming visible at all.
  Rebuilding is O(cells + overlays) over value types.
- **The scrub seek stays tolerant, and there is no exact seek to finish it** — because `onScrub`
  carries no phase, so the owner cannot tell a mid-drag tick from the last one. Left as is:
  **Task 8 should decide**, since it is numeric caption timing that would actually feel a frame
  of error. The fix without an API change is a short debounced exact seek after scrubbing settles.

### One limitation reported, deliberately NOT fixed

**A clip cannot be lengthened from the timeline, only shortened.** The trailing-edge clamp is
`model.duration`, which IS the longest clip's duration — so the longest clip (and any single
clip) can never grow. This is not a stray clamp: the ruler spans the composition, so the position
representing "longer than the composition" is physically off the right edge. Fixing it means
deciding what the ruler spans (composition, or the longest available SOURCE), which is a design
call, not a review's. The Trim panel's sliders do carry the full source range, so the capability
exists — it is the two surfaces disagreeing that makes this worth an owner decision.

---

## Task 7 — done 2026-09-06

Timeline wired to the document. `VideoTimelineModelBuilder` is pure and separate from both the
view and the view model, so lane arithmetic is testable with no screen attached.

**Two conventions worth not re-deriving:**

- A lane's length is its **trimmed** length, never the source's — the lane's edges ARE the trim
  handles, so a disagreement would make a block jump before it moved.
- **Every clip starts at zero.** A video collage plays its cells simultaneously in separate
  regions of one canvas; it is not a sequential edit. `Clip.start` exists for Task 9's
  `startOffset` and is otherwise always 0.

**Durations are async, lanes are not.** An unset trim (`end == 0`, "to the end") only becomes a
real length once the source's duration is known. `VideoEditorViewModel` now caches those by
`videoID` and `loadMissingSourceDurations()` fills them after each rebuild. Until a load lands
the lane reports **zero** rather than inventing a length.

**Scrubbing bypasses the periodic observer**, as the carried-forward note required — the canvas
is told directly and synchronously, because a seek while paused is not guaranteed to reach
`addPeriodicTimeObserver`. The seek is tolerant in both directions (an exact seek per drag tick
decodes far more than it needs to).

`videoTimelineModel` is gone. The model is derived from the document on every change; the one
piece that is not — whether the user asked for playback — is now an explicit `isPlayingIntent`.

**Plan deviation, deliberate:** the plan said append to `VideoTimelineTests.swift`. That file is
the timeline VIEW's own suite; these tests are the controller/view-model seam and live in
`VideoEditorTimelineTests.swift`, beside `VideoEditorRailTests`.

**Every wiring test was verified to fail against a deliberately broken version** (scrub not
reaching the canvas; a trim recording per tick instead of coalescing; the retime callback not
connected at all) before being kept.

---

## `TextOverlay.animation` — done 2026-09-06

The reserved field is in, defaulted `.none`, nothing reading it. Two tests pin that "nothing
reads it" so a render path wired ahead of the tier-3 spec fails here rather than shipping quietly.

Stored as `animationRaw` (the `alignmentRaw` precedent on this same type) rather than as a
decoded enum like `style`. That matters for a field whose whole purpose is forward
compatibility: a project written by a build that ships tier 3 opens here as `.none`, and
re-saving it here does **not** downgrade the user's choice for the build that understands it.

---

## Task 6 quality review — done 2026-09-06

Re-ran the review that was in flight. Every question in the old brief is answered below.

### Two Critical playback defects, both fixed

Both live in the same mechanism, and together they were the **actual race** behind
`VideoEditorPlaybackControlTests`' "fails only under full-suite load" flakiness. Neither was a
test problem, so neither was fixed by touching the test.

**1. The loop restart overrode a deliberate pause.** `loopPlaybackForever` observed
`.AVPlayerItemDidPlayToEndTime` with `object: nil` and called `setPlaying(true)`
*unconditionally*. AVFoundation posts that notification from its own thread, so the block is
merely **enqueued** on the main queue: a 0.5s fixture that reaches its end while the main actor
is busy can deliver **after** the user's pause has already landed, at which point the block
seeks to zero and starts playing again. `rebuildComposition` then read a `.playing` player and
faithfully "preserved" playback nobody asked for.

Two guards added: the ended item must be `player.currentItem` (`object: nil` observes *every*
`AVPlayerItem` in the process — every `LoopingPreviewPlayerView`, every player alive behind a
presented sheet — so an unrelated preview finishing used to yank this editor's playhead to
0:00), and `videoTimelineModel.isPlaying` must be true.

Proven first: `testAnEndOfItemNotificationDoesNotOverrideADeliberatePause` posts the
notification explicitly, making the ordering deterministic instead of reachable by luck. It
**failed against the unfixed code** on all three assertions (player playing, intent flag true,
icon reading "Pause") and passes now.

Mechanical note: `Notification` is not `Sendable`, so the item's identity is reduced to an
`ObjectIdentifier` before crossing into `MainActor.assumeIsolated`.

**2. A rebuild resumed against transient player state, not intent.** `rebuildComposition` read
`player.timeControlStatus == .playing` — a *transient* value — a 250ms debounce plus an async
`buildBundle()` after the edit. A clip that reaches its end (or is still buffering) in that
window reports something other than `.playing` while the user's intent is unchanged, so editing
any control at a loop boundary silently froze a preview the user had left playing. It now reads
`videoTimelineModel.isPlaying`. Intent defaults to `false`, so the first build still gets the
correct "don't autoplay on load" that the old comment credited to `timeControlStatus`.

This is what makes `testPlayingSurvivesACompositionRebuildToo` deterministic rather than lucky.
**No dedicated new test:** post-fix, "intent true but player stalled" cannot be constructed
cleanly (the loop observer legitimately restarts playback whenever intent is true), and a
timing-dependent test for it would have exactly the toothlessness this plan keeps warning about.
A draft test for it was written and then **deleted** for that reason.

### Test coverage gap, closed

Opening a panel is not evidence it works — the P1 T9 defect class (sliders re-homed into a panel
with **no `addTarget`**: visible, inert, suite green). Only the Frame panel's Border slider had a
drag test. **Volume, Mute and Transition had none**: deleting any of their `setupRail` wirings
would have broken the screen with every test still passing.

Three tests added to `VideoEditorRailTests`, each **verified to fail** against deliberately
removed wiring before being kept:
`testDraggingTheVolumeSliderThenReleasingRecordsExactlyOneUndoStep`,
`testTogglingMuteAppliesImmediatelyAndIsUndoableInOneStep`,
`testPickingATransitionStyleAndDraggingItsDurationBothReachTheModel`.

Trim's two sliders and its loop switch are still unfired — `presentTrimPanel` is async on the
source's duration, which `VideoEditorRailTests`' never-decoded fake asset resolves to 0. Worth a
fixture-backed test; **carried forward as debt item 6 below**, not blocking.

### Cross-editor duplication — definite recommendation

**Extract a helper object, not a shared base class. Do it after Task 10, before the branch
merges.**

The genuinely identical surface is smaller than it looks: `openPanel`, `closePanel` and
`animateStageResize` are verbatim identical (~26 lines) along with the `openToolID` and
`collapsedPanelHeight` properties. `toolTapped` shares only its one-line guard — every case
differs. `setupRail` differs. `revalidateSelection` is *substantially* different: the video
editor's handles a model-owned selection and a synchronous re-entrancy hazard the grid editor
simply does not have.

A base class would inherit ~26 lines into two 1,450-line controllers and couple two screens that
should stay independent. The right shape is a small owned collaborator — `EditorPanelPresenter`
— holding `openToolID`, the collapsed-height constraint, and the show/hide/animate sequence,
which each VC owns one of.

The argument for doing it at all is **not** line count: those 26 lines encode a subtle UIKit
constraint-ordering trap (deactivate before `show`; un-animated `hide` before reactivating) that
is currently documented at length in *two* files. A duplicated trap is one that gets half-fixed
later. The argument for doing it *after* Task 10 is that Tasks 7–10 keep changing this
controller, and they touch the timeline and timing panel rather than this plumbing — so
deferring adds no duplication.

### `activeContextKind` — keep it, with one correction

`.clip` genuinely earns its place even with the desync fixed. It is not a restatement of
`viewModel.selectedIndex`: the two can legitimately disagree (an undo restoring a snapshot whose
`selectedIndex` is nil while the rail still shows Clip tools), and it is what makes
`revalidateSelection` re-entrancy-safe.

`.text` is **write-only** — text selection is tracked entirely by `selectedTextID`, which is the
VC's own state and cannot drift the way the model-owned clip selection can. Kept as a case
(rather than collapsing to a `Bool`) because it names the state honestly at each assignment site
and Task 8's timing panel is the obvious first reader, but the doc comment now says so plainly
instead of implying both cases are load-bearing.

### Controller size — no split needed beyond one extraction

1,492 lines, against `GridEditorViewController`'s 1,470 — its sibling, not an outlier. The
*view* code was already correctly extracted to `VideoEditorPanels.swift`, and the remaining
factories are thin bindings that set values on VC-owned controls; moving them out would need a
delegate interface back to the VC for a modest line saving. **Net complexity increase, not
worth it.**

The one real outlier was `makeTransitionStyleRow` — 75 lines building its own buttons and
managing its own highlight state, which is pure layout and broke `VideoEditorPanels.swift`'s own
stated convention. Extracted as `ClipTransitionStyleRow` (the controller now supplies only a
"style was picked" callback; the row owns its highlight). Controller is 1,445 lines.

### Environment

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
xcrun simctl shutdown all
DEV=$(xcrun simctl list devices available | grep -E 'iPhone 17 \(' | head -1 | grep -oE '[0-9A-F-]{36}')
xcrun simctl boot "$DEV"; xcrun simctl bootstatus "$DEV" -b
```

Never run two simulator jobs at once. Do **not** `erase all` (resets Photos auth, breaks
`ExportSaveUITests`). Bundle id is `com.devron.caroullage`. Debug builds with
`-warnings-as-errors`, so any deprecation is a hard build failure.

---

## Open items, carried forward

**Blocking nothing, but Task 7 should know:**

- **Task 7 must call `canvasView.setPreviewTime(_:)` directly and synchronously from the scrub
  gesture** — not via the periodic observer. `addPeriodicTimeObserver` has no documented
  guarantee of firing on a seek while paused, and `AVPlayer` coalesces rapid seeks, so a drag
  would be laggy or dropped. `VideoTimeline` already reports `.changed` / `.committed` phases
  so a drag can be one undo step.
- **A fresh composition now starts paused** (Task 6 fix), which is what scrubbing needs.

**Known debt, none blocking:**

1. ~~**New flaky test**~~ — **RESOLVED 2026-09-06.** Root-caused to two real playback defects,
   not test flakiness; see the Task 6 review above. Fixed in the product, tests kept strict.
2. **`VideoTimeline.swift` is ~1000 lines** with six private lane views. A reviewer recommended
   splitting the lane views into their own file; deliberately deferred so an API-change diff
   stayed reviewable. The mechanical caveat: `pixelSnapped`, `videoTimelineHairline`,
   `videoTimelinePlayheadWidth` and `formatTimelineTime` are file-scope `private` and used by
   both halves, so they must become `internal` for the split.
3. **`ExpandedLanesView`'s vertical scroll vs the timeline's own pan recogniser** is unverified.
   `CollapsedStripView` disables its scroll view's pan for exactly this reason; the expanded one
   genuinely scrolls and has no equivalent treatment. **Needs on-device checking with a
   multi-clip composition**, not a speculative fix — no unit test can catch it, because the
   `simulatePan*` seams bypass both real recognisers.
4. **VoiceOver cannot trim or retime.** Timeline clip/pill blocks have labels but no custom
   actions, and all gesture dispatch is centralised on the timeline itself, so drag-based
   interactions are structurally unreachable. Minimal fix is `accessibilityCustomActions` set
   from `VideoTimeline` (which owns the callbacks) rather than plumbing callbacks into rows.
5. **Layout and Audio tools still open pre-existing modals** rather than inline panels like the
   collage editor's. Judged acceptable scoping, not a spec violation.
6. **Trim/Volume/Transition panels use plain controls**, not a reproduction of
   `VideoCellControlsSheet`'s draggable filmstrip; the full sheet stays reachable as
   "More Options…".
7. **The Trim panel's controls are untested.** Volume, Mute and Transition now have
   fire-the-control tests; Trim's two sliders and loop switch do not, because
   `presentTrimPanel` awaits the source's real duration and `VideoEditorRailTests`' fake asset
   never decodes. Needs a fixture-backed editor like `VideoEditorPlaybackControlTests`
   builds. Same silent-breakage exposure as the gap that was just closed.

---

## Decisions

### ✅ Settled 2026-09-06 — declarative style continues for Tasks 7–10

The owner confirmed the remaining tasks stay specified **declaratively** (API, invariants and
failure modes; not full implementation code). Do not rewrite them into prescriptive code blocks.

Rationale is at the end of the Plan 2 document: Plan 1 carried complete code for every task and
**ten defects were found in that code, all mine**, four of which would have shipped — and they
passed spec review precisely *because* the implementation matched the plan.

**Known cost of this style, and how to compensate.** Declarative plans fail differently: instead
of specifying wrong code, they under-specify an invariant, and an agent fills the gap with a
locally-sound choice that compounds. Every Plan 2 defect so far has that shape — an invariant
defined too narrowly (T1 fail-open), a cache with no bound (T2), a test too weak to fail (T2),
a lifecycle not thought through (T3), a callback with no gesture phase (T5), an API with no play
callback (T5/T6). None were implementer errors.

So the compensating discipline is in the **review briefs**, not the plan:

- Tell every reviewer explicitly that the plan may be wrong, and ask for plan defects **listed
  separately** from implementation issues. This is what has found all sixteen.
- Ask reviewers to trace **specific named mechanisms** ("can a stale completion fire after a
  newer call?"), not to confirm conformance.
- Ask "what did the plan fail to say?" as its own question.
- When a fix is dispatched, require the test to be **proven to fail first** — three tests in this
  run passed against deliberately broken code and only got teeth when someone tried to break them.

### ✅ Settled 2026-09-06 — add `TextOverlay.animation`

Owner confirmed: add the reserved field. Plan 2 originally omitted it as YAGNI (defensive
decoding makes adding it later a one-liner, not a migration) — that reasoning still holds, but
the owner wants the spec honoured, so it goes in. Details in the queue above, item 2.

No decisions remain open.

---

## What this run has actually been about

Sixteen defects have been found in the **plans**, not the implementations. Six would have
shipped:

| Where | Defect | Visible? |
|---|---|---|
| P1 T4 | Zero-height hit target — the tool rail could not be tapped | No |
| P1 T5 | Stale animation completion destroyed the *next* panel's content | No |
| P1 T7 | Pill/highlight text appeared only after export, never in the editor | On export only |
| P1 T9 | Sliders re-homed into a panel with no `addTarget` — visible, inert | No |
| P1 T10 | Rail buttons stayed live after undo removed the cell they pointed at | No |
| P2 T6 | Video editor briefly had **no way to pause** | Immediately |

They share a signature: **the code matched the plan, so spec review passed; the UI rendered, so
a screenshot passed; the test seam bypassed the broken path, so the suite passed.** What caught
them was telling reviewers the plan itself might be wrong, and asking them to trace specific
mechanisms rather than confirm conformance.

Three tests in this run were also found to pass against deliberately broken code, and were
strengthened only because someone tried to break them on purpose.
