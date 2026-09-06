# Editor redesign — state as of 2026-09-06

Resume point for the two-plan editor redesign. Everything below is committed on
branch `editor-chrome-redesign` in the worktree
`/Users/irony/Claude/Projects/ClaudeCollage/.claude/worktrees/editor-chrome-redesign`.

Working tree is clean. **51 commits** ahead of `dev`.

---

## Where we are

| | Plan 1 — chrome + collage editor | Plan 2 — video timeline + timed text |
|---|---|---|
| Status | **Complete, 11 / 11** | **6 / 10 implemented** |
| Doc | `2026-09-05-editor-chrome-and-collage-editor.md` | `2026-09-06-video-editor-timeline-and-timed-text.md` |

**Unit suite: 880 tests, 0 failures.** UI suite last run green on the four suites the
redesign touched (19/19); a full UI run has not been done since Plan 2 began.

### Plan 2 task status

| Task | State |
|---|---|
| 1 · `TextOverlay` timing | ✅ done, reviewed, 1 Critical fixed (fail-open) |
| 2 · Export honours timing | ✅ done, reviewed, cache bounded + coverage added |
| 3 · Preview honours timing | ✅ done, reviewed, observer lifecycle fixed |
| 4 · `VideoTimelineGeometry` | ✅ done, reviewed, coverage gaps closed |
| 5 · `VideoTimeline` view | ✅ done, reviewed, API defects fixed (edit phase, selection, play) |
| 6 · Video editor adopts chrome | ✅ done, spec reviewed, desync + undo fixed. **Quality review was in flight when we stopped** |
| 7 · Wire timeline to document | ⬜ **next** |
| 8 · Timing panel | ⬜ |
| 9 · `startOffset` | ⬜ (deliberately last; droppable) |
| 10 · UI test updates | ⬜ |

---

## Tomorrow's queue, in order

**1. Task 6 code-quality review** (was in flight when we stopped; re-run it).
Base `c343efe`, head `de9c6e1`. Ask it to judge, specifically:
- the new flaky test (`VideoEditorPlaybackControlTests.testPausingSurvivesACompositionRebuild`)
  — diagnose the actual race, recommend a fix that keeps the test meaningful rather than
  loosening it into uselessness;
- `VideoEditorViewController`'s size after this task, and whether the panel factories should move out;
- **cross-editor duplication** — `VideoEditorViewController` now closely mirrors
  `GridEditorViewController`'s `setupRail` / `toolTapped` / `openPanel` / `closePanel` /
  `animateStageResize` / `revalidateSelection`. Worth a shared base type, or would that couple
  two screens that should stay independent? Want a definite recommendation;
- whether the `activeContextKind` tri-state still earns its place now the desync is fixed;
- test quality, especially whether the contextual panels' controls actually fire.

Fix whatever it finds before starting Task 7.

**2. `TextOverlay.animation`** — owner confirmed 2026-09-06: **add it.**
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

**3. Task 7** — wire the timeline to the document. Plan lines 914 onward.

**4. Tasks 8, 9, 10** — timing panel, `startOffset` (last, droppable), UI test updates.

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

1. **New flaky test** — `VideoEditorPlaybackControlTests.testPausingSurvivesACompositionRebuild`
   failed once under full-suite load, passed in isolation and on rerun. Real `AVPlayer` +
   generated fixture + polling. Diagnosis was the first question of the in-flight quality review.
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
