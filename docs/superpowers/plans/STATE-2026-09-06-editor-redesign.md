# Editor redesign — state as of 2026-09-06

Resume point for the two-plan editor redesign. Everything below is committed on
branch `editor-chrome-redesign` in the worktree
`/Users/irony/Claude/Projects/ClaudeCollage/.claude/worktrees/editor-chrome-redesign`.

Working tree is clean. **55 commits** ahead of `dev`.

---

## Where we are

| | Plan 1 — chrome + collage editor | Plan 2 — video timeline + timed text |
|---|---|---|
| Status | **Complete, 11 / 11** | **6 / 10 implemented** |
| Doc | `2026-09-05-editor-chrome-and-collage-editor.md` | `2026-09-06-video-editor-timeline-and-timed-text.md` |

**Unit suite: 884 tests, 0 failures.** UI suite last run green on the four suites the
redesign touched (19/19); a full UI run has not been done since Plan 2 began.

### Plan 2 task status

| Task | State |
|---|---|
| 1 · `TextOverlay` timing | ✅ done, reviewed, 1 Critical fixed (fail-open) |
| 2 · Export honours timing | ✅ done, reviewed, cache bounded + coverage added |
| 3 · Preview honours timing | ✅ done, reviewed, observer lifecycle fixed |
| 4 · `VideoTimelineGeometry` | ✅ done, reviewed, coverage gaps closed |
| 5 · `VideoTimeline` view | ✅ done, reviewed, API defects fixed (edit phase, selection, play) |
| 6 · Video editor adopts chrome | ✅ done, spec + quality reviewed, 2 Critical playback bugs fixed, control coverage added |
| 7 · Wire timeline to document | ⬜ **next** |
| 8 · Timing panel | ⬜ |
| 9 · `startOffset` | ⬜ (deliberately last; droppable) |
| 10 · UI test updates | ⬜ |

---

## Tomorrow's queue, in order

**1. `TextOverlay.animation`** — owner confirmed 2026-09-06: **add it.**
- Reserved field per spec §4.1, defaulted `.none`, nothing reads it yet.
- Must decode with a `decodeIfPresent` fallback like every other field on this type, so existing
  saved projects are unaffected — `TextStyle` and the Task 1 timing fields are the pattern.
- Do **not** wire any rendering. Tier-3 animation (fade / slide / pop / typewriter) is its own
  spec; both render paths are already per-frame, so it will be a change to two call sites rather
  than a migration.
- Test: round-trips; a snapshot written **without** the key decodes to `.none`; an unknown raw
  value from a future build falls back rather than throwing (the `TextStyle.Kind` precedent).
- Watch the raw-string trap: use `##"..."##`, since a single-hash raw string self-terminates on
  the `"#` inside a hex colour.

**2. Task 7** — wire the timeline to the document. Plan lines 914 onward.

**3. Tasks 8, 9, 10** — timing panel, `startOffset` (last, droppable), UI test updates.

**4. After Task 10, before the branch merges: extract `EditorPanelPresenter`.** See "Cross-editor
duplication" under the Task 6 review below — a definite recommendation, deliberately sequenced
after the video editor stops changing.

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
