# Video collage templates — design

**Date:** 2026-09-27 · **Branch:** `feature/video-templates` · **Owner request:** "Make video collage
templates like these references accurately, and enhance the video collage editor so a user can make
collages like these easily with top-class UX."

## 1. The references, decoded

Four screen recordings (Pinterest + one landscape clip). Measured frame-by-frame at 4–12 fps.

| # | Look | Canvas | Layout | Motion / text |
|---|------|--------|--------|---------------|
| R1 | **Travel filmstrip** | landscape (≈16:9) | 4–5 full-height vertical clips of *different widths* side by side on a strip ~2.5 viewports wide | The whole strip **pans left at a steady speed**. A heart doodle + handwritten "Hey !" ride on one panel; a handwritten place name rides on a later one. |
| R2 | **Title grid** | 9:16 | uniform 2×2, zero gap | Editorial title over the centre seam: `COLLAGE` in a high-contrast Didone serif, a thin italic script line tucked under it and offset right. Visible from the start, **fades out at ≈2.4 s**. |
| R3 | **Lyric stack** | 9:16 | three equal full-width rows, zero gap | Kinetic lyrics: condensed bold caps in cream, one word per line, left of centre around the first seam. **Words appear one at a time**; phrases replace each other on the beat. |
| R4 | **Caption stack** | 9:16 | three equal full-width rows, zero gap | A centred serif caption on a **cream label box** in the middle row. Words **fade in one by one**; a second caption replaces the first. |

## 2. What the editor could not do

| Gap | Needed by |
|-----|-----------|
| Video canvases are **4:5 only** (`AppCoordinator.startVideoCollage`) | R1 (16:9), R2–R4 (9:16) |
| No **three stacked rows** / three columns grid | R3, R4 |
| `TextAnimation` is **reserved — nothing renders it** | R2 (fade), R3 (word by word), R4 (word fade) |
| No rectangular **label box** text treatment (`.pill` couples its radius to its padding) | R4 |
| No Didone / condensed / handwriting faces in the text sheet | R1–R4 |
| No **camera pan** over a canvas wider than the frame | R1 |
| No video templates at all — Home's video row only presets a grid | all |
| One clip per picker round-trip | every multi-slot template |

## 3. Design

### 3.1 Model (all additive, all decode with fallbacks)

- `GridTemplate` gains `.threeRows` and `.threeColumns`.
- `TextAnimation` gains `.words` ("Word by word", a near-instant per-word reveal) and `.wordFade`
  (soft per-word fade). The existing reserved cases (`fade`, `slide`, `pop`, `typewriter`) are now
  implemented. Stored as the raw string already, so an older build opens a new case as `.none`.
- `TextStyle.Kind` gains `.box` — a painted rectangle like `.pill` but with a small corner radius and
  more vertical than horizontal padding (R4's label).
- `VideoProjectData.pan: CanvasPan?` — `axis` (horizontal/vertical) + `extent` (how many frames long
  the strip is, 1…4). `nil` = no pan, i.e. every project saved before today.
- `VideoTemplate` + `VideoTemplateCatalog` — a Swift catalog (ids, localized names, aspect, layout,
  pan, border, captions, stickers). Swift rather than JSON: four entries, strongly typed, localizable.

### 3.2 One animation function, two renderers

`TextAnimationMath.frame(for:at:)` is a pure function of `(overlay, time)` returning opacity, scale,
a normalized offset, and per-character alpha ranges. It is the ONLY place animation is computed:

- **Export** — `VideoOverlayRenderer` draws each frame with that state (`TextRendering.draw` gains an
  optional animation frame: clip → transform about the frame centre → alpha → per-range glyph alpha).
  The per-frame overlay cache is re-keyed on the quantized animation state, so a caption at rest still
  costs one render per run of identical frames.
- **Preview** — `TextOverlayView` applies the same frame (content-view transform + alpha + attributed
  per-range alpha). The VC drives it from a display link while playing (10 Hz is too coarse for motion)
  and from the playhead when paused.
- A **paused** preview shows every on-screen caption in its rest state; captions move only while
  playing. (First built as "only the selected caption rests" — but a template opens paused at 0:00,
  where a fade or a word reveal has not begun, so Title Grid opened looking title-less.)

Timing rules: entrance runs from `startTime ?? 0`; exit (fade) only when `endTime` is set. Word
reveals spread across ≈60 % of the window, clamped to 0.12–0.45 s per word.

### 3.3 Camera pan

The strip is laid out by the ordinary layout engine at `strip size = canvas × extent` along the axis,
so every cell keeps its normal fill/crop/pan-zoom math. The composition adds a translation ramp to each
layer instruction (`0 → −(extent−1)·frame` over the composition), composed with any intro transition by
splitting the ramp at the transition's boundaries.

Overlays live in **strip space**: in the preview the cell chrome, captions and stickers sit in one
container view translated by the same offset, so dragging a caption normalizes it against the strip
(it rides with its panel, as in R1) and tapping a slot hit-tests through the offset. The export renders
the overlay layer per frame translated by the offset.

### 3.4 Templates (`VideoTemplateCatalog`)

| id | name | canvas | layout | text |
|----|------|--------|--------|------|
| `travel-filmstrip` | Travel Filmstrip | 16:9, pan ×2.5 | 5 panels, widths .62/.26/.58/.46/.58 frames | Noteworthy "Hey !" 64 pt + outline heart by the narrow panel, place name 54 pt on panel 4 |
| `title-grid` | Title Grid | 9:16 | 2×2 | Didot `COLLAGE` 104 pt + Didot Italic subtitle offset right, `fade`, 0–2.6 s |
| `lyric-stack` | Lyric Stack | 9:16 | 3 rows | DIN Condensed Bold `#FCF8E0` caps at x 0.155, `words`, four phrases in sequence (placeholder lyrics — never real song lyrics) |
| `caption-stack` | Caption Stack | 9:16 | 3 rows, 4 px hairlines | Bodoni 72 Bold `#120F08` on a `#FCF8D2` `box`, `wordFade`, two captions |

All borders 0 (the references are seamless); cells loop.

### 3.5 UX

- **Video start sheet** — tapping *Video* (Start sheet / Home) opens a picker: the templates as live,
  animated preview cards (drawn with the real layout + `TextAnimationMath` + pan over bundled sample
  photos, so the card shows exactly what the template does) and a *Blank* row with aspect chips
  (9:16 · 4:5 · 1:1 · 16:9).
- **Fill every slot at once** — when a project has several empty slots, tapping one offers a
  multi-select picker that fills the empty slots in order.
- **Text sheet** — new faces (Didot, Didot Italic, DIN Condensed, Bradley Hand, Georgia Bold, Bodoni)
  and an **Animation** row of preset cards; choosing one replays it on the canvas.
- **Layout sheet** — shows the two new grids.
- **Home** — the Video Collages row leads with the four templates.

## 4. Out of scope

Per-word *scale* pops (would need glyph-by-glyph drawing), timed stickers, sticker animation, a pan
speed control independent of the clip length, changing a project's aspect inside the editor.

## 5. Verification

Typography and geometry were measured on the recordings at native resolution (video rect located by
pixel analysis, seams by row/column gradients, colours sampled) and compared side by side with frames
of the baked loops. `VideoTemplateCompositionTests` proves the pan and the animated captions in real
exported files (pixel read-back at chosen times). `VideoTemplatesUITests.testCaptureEveryTemplateFilled`
captures every template filled with the sample loops — run it on an iOS 26.x simulator (27.0 cannot
display an `AVVideoComposition`).

Home's loops are rendered, not filmed: `VideoTemplateLoopBakeTests` (skipped unless
`TEST_RUNNER_CAROULLAGE_BAKE_DIR` is set) writes `sample_loop_tpl_*.mp4` + posters from
`VideoTemplatePreviewRenderer`. Re-bake after changing a template.

## 6. Follow-ups

- Pan speed follows the composition length (the longest clip). The reference glides ~0.56 frames/s;
  a clip-independent speed control would let a long clip keep that pace.
- Personal (subject-lift) stickers in the video editor — the filmstrip reference uses photo cut-outs.
- Per-word scale ("pop") and timed stickers.
