# Video editor: no blink, smooth layout changes, a timeline that feels like an editor

2026-09-28 · branch `fix/video-editor-smoothness` (off `dev` at 2347ab0)

The owner reported three things in the video collage editor:

1. every overlay edit (caption position, sticker) made the video **blink**;
2. a layout change **snapped** ("updates with a flip"), and overlays should update smoothly too;
3. the timeline looked dull and should feel like a world-class editor.

## 1. The blink — root cause

Every document change reaches `viewModel.onChanged`, which called `rebuildComposition()`
unconditionally. That builds a new `AVPlayerItem` and calls `replaceCurrentItem(with:)`,
and the player layer shows **nothing** between losing the old item and drawing the new
one's first frame. The preview composition carries no overlays at all (the canvas draws
captions and stickers as live views), so for a caption drag, a sticker, a selection tap
or an overlay-only undo the rebuild was pure cost: 250 ms after the edit, a blank frame.

Confirmed with a failing test (`VideoEditorSmoothUpdateTests`: the player's item must be
the same object after an overlay edit) and on a screen recording: per-frame luminance of
the canvas crop showed no uniform (blank) frames anywhere in the session after the fix.

**Fix:** `VideoEditorViewModel.compositionSignature` — the undo snapshot minus the
overlays — and the view controller rebuilds only when it differs from the signature last
**scheduled** (not last shown, so an overlay edit inside a real rebuild's debounce doesn't
cancel it). Derived from the snapshot rather than listing fields, so a new snapshot field
(the templates branch's `pan`) is part of the composition by default.

A second, smaller cause: `updateStickerOverlays` tore down and rebuilt every sticker view
on every change — including each tick of a sticker's own drag. Overlays are now pooled by
identity (caption id, sticker id).

## 2. Smooth layout and overlay changes

A composition that really changes (trim, layout, border…) still has to swap items, so the
swap is covered: `VideoFreezeFrameView` holds the frame on screen over the gap and
crossfades away once the new item draws (polled per display frame; 1.5 s ceiling). The
frame comes from `AVPlayerLayer.displayedPixelBuffer()` while paused and from an
`AVPlayerItemVideoOutput` attached to every preview item while playing (the layer refuses
at a non-zero rate). A paused rebuild now seeks exactly, so the crossfade lands on the
frame that was held.

A **layout change** cuts the held frame along the old slots; each piece glides (settled
spring, no overshoot) to its slot in the new layout while the slot chrome glides with it,
new slots fade in, removed ones fade out, and the rebuilt composition crossfades in
underneath. Reduce Motion gets the crossfade without the travel.

Trap found on the way: `AVPlayerLayer` draws its video in a private sublayer, so the cover
inserted at subview index 0 sat *under* the video — it must go directly below the first
real subview (`keepFreezeFrameBelowContent`; pinned by a mutation-checked test).

Overlays: a new caption/sticker pops in, one moved by undo/redo glides back, a restyle
crossfades, a deleted one fades out (and stops taking touches at once); an overlay under
the finger is never animated.

## 3. The timeline

Kept: the public API, the fit-to-width geometry every test pins, the one-drag-one-undo
contract. The collage's clips play *in parallel*, and most collages are seconds long, so
the whole piece fitting the width is the right model; a pinch-zoom scrolling timeline was
considered and left out.

- **Collapsed strip:** a filmstrip of the *composed collage* (frames of the preview
  composition, regenerated per rebuild), caption track beneath, a shadowed playhead.
- **Clip lanes:** each clip's own frames, sampled across its whole source and **anchored
  in source time**, so trimming the leading edge uncovers frames instead of sliding them;
  a `1 · 2.5s` badge; the selected clip wears the accent as a frame with grab handles.
  Empty slots show a dashed "+" chip.
- **Caption lane:** pills show the caption's text. **Music lane:** a real waveform
  (AVAssetReader, 8 kHz mono, peak per slice), cut to the trim window and to the collage.
- **Ruler:** labelled ticks at a readable interval (½ s, 1 s, 2 s, 5 s…) with minor ticks.
- **Header:** an ink play disc with an animated play/pause glyph, a `0:03.2 / 0:08.0`
  readout (accent while scrubbing), a chevron that rotates.
- **Feel:** the playhead runs at display rate between the player's 10 Hz reports (never
  more than 0.5 s past the last one); scrubs snap to cuts and caption edges, trims snap to
  the playhead, captions also to cuts, with a selection tick; hitting a limit gives a
  boundary tick; taps pop the block; expand/collapse crossfades; model changes that did not
  come from the finger glide.

No new String Catalog keys: times and durations format through Foundation's `Duration`
styles (localised digits and unit words), so the 11-language policy needs no new rows.

## Merging with `feature/video-templates`

That branch reshapes `VideoCanvasView` (strip view, display link) and the view controller.
A dry-run merge against its committed state conflicts in `VideoCanvasView.swift` (10
hunks: chrome creation, overlay pooling, layout) and `VideoEditorViewController.swift`
(1 hunk: `configure(…, pan:, animated:)`). The timeline files do not overlap.
