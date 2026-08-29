# Home Showcase Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the Home tab into a photo-real template showcase (hero + three pillar strips: Photo Collage, Video Collage, Carousel), where every preview is composited from bundled licensed model photography through the app's own renderer, and tapping a card opens the matching editor with empty photo zones.

**Architecture:** A bundled `SampleContent` catalog (photos + manifest + baked video loops) feeds a `SampleContentCatalog` service; `TemplateService` grows disk-cached `showcasePreview` renders that inject sample photos into the existing `CollageRenderer` pipeline; `HomeViewController` is rebuilt around a `HeroShowcaseView` and three `ShowcaseTemplateCell` strips; `AppCoordinator` gains two routes (carousel template → `CarouselService.buildCarousel(from:)` → carousel editor; video showcase → `VideoEditorViewModel` with a preset layout).

**Tech Stack:** Swift 6 / UIKit, XcodeGen, Core Graphics (`CollageRenderer`), AVFoundation (`AVPlayerLooper`), XCTest + XCUITest. Spec: `docs/superpowers/specs/2026-08-29-home-showcase-redesign-design.md`.

**Read first:** `Caroullage/Features/Home/HomeViewController.swift`, `Caroullage/Core/Services/TemplateService.swift`, `Caroullage/Coordinators/AppCoordinator.swift:40-90,400-600`, `Caroullage/Core/Services/CarouselService.swift:179-200`, `Caroullage/Core/Rendering/CollageRenderer.swift:16-90`.

**Environment (every shell session):**
```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
cd "/Users/irony/Claude/Projects/ClaudeCollage"
```
Build: `xcodegen generate` then
`xcodebuild build -project Caroullage.xcodeproj -scheme "Caroullage (Dev)" -destination "platform=iOS Simulator,name=iPhone 17"`.
Tests: same with `test`. The working tree carries unrelated step-06 WIP — **stage only files this plan creates or names**, never `git add -A`.

**Conventions that are law here:** every color/spacing/font from `Theme` tokens (no system defaults); `Haptics.tap()` on taps; `navigationItem.title` not `title` on tab roots; Reduce Motion via `Theme.Motion.duration()`; new cells follow `FeaturedTemplateCell`'s task-based thumbnail pattern; accessibility identifiers on everything a test touches.

---

### Task 0: Branch

- [ ] **Step 1: Create the working branch off current HEAD**

```bash
git checkout -b step-07-home-showcase
git log --oneline -1   # expect 85a53b1 or later
```

Do not commit the pre-existing modified step-06 files; they ride along untouched.

---

### Task 1: Inventory the templates (data the manifest needs)

The manifest must map template IDs → per-photo-zone assets. Zone counts come from the JSON, not guesswork.

**Files:**
- Create: `/private/tmp/claude-501/-Users-irony-Claude-Projects-ClaudeCollage/6169005e-8b67-4e8f-a2d8-772af07f0211/scratchpad/inventory.py` (scratch, not committed)

- [ ] **Step 1: Dump every template's id, aspect, and photo-zone count**

```python
# inventory.py
import json, glob
for path in sorted(glob.glob("Caroullage/Resources/Templates/*.json")):
    if path.endswith("template_schema.json"): continue
    d = json.load(open(path))
    photos = [c for c in d.get("cells", []) if c.get("type") == "photo"]
    print(f"{d['id']:28} {d.get('canvasAspectRatio','1:1'):5} photos={len(photos)} premium={d.get('isPremium', False)}")
print("--- carousels ---")
for path in sorted(glob.glob("Caroullage/Resources/CarouselTemplates/*.json")):
    if "schema" in path: continue
    d = json.load(open(path))
    per_frame = [len([c for c in f.get("cells", []) if c.get("type") == "photo"]) for f in d.get("frames", [])]
    print(f"{d.get('id','?'):28} {d.get('canvasAspectRatio','1:1'):5} framePhotos={per_frame} premium={d.get('isPremium', False)}")
```

Run: `python3 <scratchpad>/inventory.py` from the repo root. Keep the output — Task 3's manifest is written from it.

- [ ] **Step 2: Choose the showcased set** — pick **8 free photo templates** (spread across categories: at least one birthday, one minimal, one story 9:16, one travel, one grid) and **6 free carousel templates** (at least one `matched`, one `gridpreview`; skip `panoramic` — it needs a source photo and cannot open empty). Record the chosen IDs; they go in the manifest and in Task 3's integrity test.

---

### Task 2: Curate and bundle the sample photos

**Files:**
- Create: `Caroullage/Resources/SampleContent/` (photos + `ATTRIBUTION.md`)

- [ ] **Step 1: Download ~24 Pexels photos.** Use the `/browse` skill (per CLAUDE.md, never claude-in-chrome) on `https://www.pexels.com/search/<query>/` for queries: `portrait woman smiling`, `friends laughing`, `couple golden hour`, `travel beach`, `food flatlay`, `autumn portrait`, `family picnic`. Selection criteria: bright, warm, editorial-quality, **faces engaging the camera where possible**, no visible brand logos, no recognizable public figures. Pexels image CDN URLs are directly curl-able:

```bash
mkdir -p Caroullage/Resources/SampleContent
curl -L -o Caroullage/Resources/SampleContent/sample_portrait_01.jpg \
  "https://images.pexels.com/photos/<PHOTO_ID>/pexels-photo-<PHOTO_ID>.jpeg?auto=compress&w=1200"
```

Naming (exact, the manifest depends on it): `sample_portrait_01..06.jpg`, `sample_couple_01..03.jpg`, `sample_friends_01..03.jpg`, `sample_travel_01..04.jpg`, `sample_food_01..03.jpg`, `sample_seasonal_01..03.jpg`, `sample_family_01..02.jpg`.

- [ ] **Step 2: Downsample and cap size**

```bash
cd Caroullage/Resources/SampleContent
for f in sample_*.jpg; do sips -Z 1200 -s formatOptions 72 "$f" --out "$f"; done
du -sh .   # expect ≤ 6MB total; recompress outliers with formatOptions 60
cd -
```

- [ ] **Step 3: Write `ATTRIBUTION.md`** — one line per photo: filename, photographer, Pexels page URL, "Pexels License". Header states: all photos are Pexels-licensed for commercial use; no likeness of public figures is bundled.

- [ ] **Step 4: Verify bundling** — `xcodegen generate` then the build command from the header. Resources under `Caroullage/Resources` are bundled flat automatically (the `sample_` prefix keeps names collision-free). Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add Caroullage/Resources/SampleContent
git commit -m "feat(step07): bundle curated sample photography with attribution"
```

---

### Task 3: `SampleContentCatalog` + manifest (TDD)

**Files:**
- Create: `Caroullage/Resources/SampleContent/sample_content_manifest.json`
- Create: `Caroullage/Core/Services/SampleContentCatalog.swift`
- Test: `CaroullageTests/Unit/SampleContentCatalogTests.swift`

- [ ] **Step 1: Write the manifest** from Task 1's inventory. Exact schema (example entries shown; fill every chosen ID, photo array length == that template's photo-zone count, `framePhotos` outer length == frame count, inner length == that frame's photo-cell count):

```json
{
  "version": 1,
  "templates": {
    "birthday-bash": { "photos": ["sample_family_01"] },
    "grid-4cell-square": { "photos": ["sample_portrait_01", "sample_travel_01", "sample_couple_01", "sample_food_01"] }
  },
  "carousels": {
    "carousel-matched-team": { "framePhotos": [["sample_portrait_02"], ["sample_portrait_03"], ["sample_portrait_04"], ["sample_portrait_05"]] }
  },
  "videoShowcases": [
    { "id": "duo-motion",  "loop": "sample_loop_duo",  "poster": "sample_loop_duo_poster",  "title": "Duo Motion",  "layout": "twoUpVertical" },
    { "id": "quad-motion", "loop": "sample_loop_quad", "poster": "sample_loop_quad_poster", "title": "Quad Motion", "layout": "fourSquare" },
    { "id": "solo-motion", "loop": "sample_loop_solo", "poster": "sample_loop_solo_poster", "title": "Spotlight",   "layout": "oneCell" }
  ],
  "hero": [
    { "kind": "template", "id": "<photo template id>" },
    { "kind": "video",    "id": "duo-motion" },
    { "kind": "carousel", "id": "<carousel template id>" },
    { "kind": "template", "id": "<photo template id>" },
    { "kind": "carousel", "id": "<carousel template id>" }
  ]
}
```

`layout` values are `GridTemplate` raw values (`oneCell`, `twoUpHorizontal`, `twoUpVertical`, `threeLeft`, `threeRight`, `fourSquare`, `sixGrid`, `nineGrid`).

- [ ] **Step 2: Write the failing tests**

```swift
//  CaroullageTests/Unit/SampleContentCatalogTests.swift
import XCTest
@testable import Caroullage

@MainActor
final class SampleContentCatalogTests: XCTestCase {

    private var catalog: SampleContentCatalog!
    private var service: TemplateService!

    override func setUp() async throws {
        catalog = SampleContentCatalog()
        service = TemplateService()
        service.loadBundledTemplates()
        service.loadBundledCarouselTemplates()
    }

    func testManifestLoads() {
        XCTAssertNotNil(catalog.manifest, "bundled manifest must parse")
        XCTAssertGreaterThanOrEqual(catalog.manifest?.version ?? 0, 1)
    }

    /// Every asset the manifest references exists in the bundle.
    func testAllReferencedPhotoAssetsExist() {
        for name in catalog.allReferencedPhotoNames() {
            XCTAssertNotNil(catalog.image(named: name), "missing bundled photo: \(name)")
        }
    }

    /// Every showcased template ID resolves against the parsed catalogs,
    /// and photo counts match the template's photo zones exactly.
    func testTemplateEntriesMatchCatalog() {
        guard let manifest = catalog.manifest else { return XCTFail("no manifest") }
        for (id, entry) in manifest.templates {
            guard let template = service.templates.first(where: { $0.id == id }) else {
                return XCTFail("manifest references unknown template \(id)")
            }
            let photoZones = template.cells.filter { $0.type == .photo }.count
            XCTAssertEqual(entry.photos.count, photoZones, "photo count mismatch for \(id)")
            XCTAssertFalse(template.isPremium, "showcased templates must be free: \(id)")
        }
        XCTAssertGreaterThanOrEqual(manifest.templates.count, 8)
    }

    func testCarouselEntriesMatchCatalog() {
        guard let manifest = catalog.manifest else { return XCTFail("no manifest") }
        for (id, entry) in manifest.carousels {
            guard let template = service.carouselTemplates.first(where: { $0.id == id }) else {
                return XCTFail("manifest references unknown carousel \(id)")
            }
            XCTAssertEqual(entry.framePhotos.count, template.frames.count, "frame count mismatch for \(id)")
            for (i, frame) in template.frames.sorted(by: { $0.index < $1.index }).enumerated() {
                let photoCells = frame.cells.filter { $0.type == .photo }.count
                XCTAssertEqual(entry.framePhotos[i].count, photoCells, "frame \(i) photo mismatch for \(id)")
            }
            XCTAssertFalse(template.isPremium, "showcased carousels must be free: \(id)")
        }
        XCTAssertGreaterThanOrEqual(manifest.carousels.count, 6)
    }

    func testVideoShowcasesResolve() {
        guard let manifest = catalog.manifest else { return XCTFail("no manifest") }
        XCTAssertGreaterThanOrEqual(manifest.videoShowcases.count, 3)
        for showcase in manifest.videoShowcases {
            XCTAssertNotNil(GridTemplate(rawValue: showcase.layout), "bad layout \(showcase.layout)")
            XCTAssertNotNil(catalog.image(named: showcase.poster), "missing poster \(showcase.poster)")
            XCTAssertNotNil(catalog.videoURL(named: showcase.loop), "missing loop \(showcase.loop)")
        }
    }

    func testHeroEntriesResolve() {
        guard let manifest = catalog.manifest else { return XCTFail("no manifest") }
        XCTAssertGreaterThanOrEqual(manifest.hero.count, 4)
        let kinds = Set(manifest.hero.map(\.kind))
        XCTAssertTrue(kinds.isSuperset(of: [.template, .video, .carousel]), "hero must cover all three pillars")
        for ref in manifest.hero {
            switch ref.kind {
            case .template: XCTAssertNotNil(manifest.templates[ref.id])
            case .carousel: XCTAssertNotNil(manifest.carousels[ref.id])
            case .video:    XCTAssertTrue(manifest.videoShowcases.contains { $0.id == ref.id })
            }
        }
    }

    /// A missing entry degrades to nil, never crashes.
    func testUnknownTemplateReturnsNil() {
        XCTAssertNil(catalog.samplePhotos(forTemplateID: "no-such-template"))
    }
}
```

- [ ] **Step 3: Run to verify failure** — `xcodebuild test … -only-testing:CaroullageTests/SampleContentCatalogTests`. Expected: compile failure, `SampleContentCatalog` undefined.

- [ ] **Step 4: Implement**

```swift
//
//  SampleContentCatalog.swift
//  Caroullage
//
//  Step 07 — resolves the bundled sample-content manifest: which licensed
//  sample photos dress which template in the Home showcase. Missing entries
//  degrade per-item (callers fall back to schematic thumbnails); a missing or
//  corrupt manifest degrades the whole showcase the same way. Never fatal.
//

import Foundation
import UIKit

public struct SampleContentManifest: Decodable, Sendable {
    public struct TemplateEntry: Decodable, Sendable { public let photos: [String] }
    public struct CarouselEntry: Decodable, Sendable { public let framePhotos: [[String]] }
    public struct VideoShowcase: Decodable, Sendable {
        public let id: String
        public let loop: String
        public let poster: String
        public let title: String
        public let layout: String
    }
    public enum HeroKind: String, Decodable, Sendable { case template, video, carousel }
    public struct HeroRef: Decodable, Sendable {
        public let kind: HeroKind
        public let id: String
    }

    public let version: Int
    public let templates: [String: TemplateEntry]
    public let carousels: [String: CarouselEntry]
    public let videoShowcases: [VideoShowcase]
    public let hero: [HeroRef]
}

@MainActor
public final class SampleContentCatalog {

    public static let shared = SampleContentCatalog()

    private let bundle: Bundle
    public private(set) var manifest: SampleContentManifest?
    private var imageCache: [String: UIImage] = [:]

    public init(bundle: Bundle = .main) {
        self.bundle = bundle
        if let url = bundle.url(forResource: "sample_content_manifest", withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            manifest = try? JSONDecoder().decode(SampleContentManifest.self, from: data)
        }
    }

    /// The manifest version, folded into preview cache keys so re-authored
    /// sample content invalidates stale renders.
    public var version: Int { manifest?.version ?? 0 }

    public func samplePhotos(forTemplateID id: String) -> [UIImage]? {
        guard let names = manifest?.templates[id]?.photos else { return nil }
        let images = names.compactMap { image(named: $0) }
        // All or nothing: a half-dressed preview looks broken, not aspirational.
        return images.count == names.count ? images : nil
    }

    public func sampleFramePhotos(forCarouselID id: String) -> [[UIImage]]? {
        guard let frames = manifest?.carousels[id]?.framePhotos else { return nil }
        var out: [[UIImage]] = []
        for names in frames {
            let images = names.compactMap { image(named: $0) }
            guard images.count == names.count else { return nil }
            out.append(images)
        }
        return out
    }

    public var videoShowcases: [SampleContentManifest.VideoShowcase] {
        manifest?.videoShowcases ?? []
    }

    public var heroRefs: [SampleContentManifest.HeroRef] { manifest?.hero ?? [] }

    public func image(named name: String) -> UIImage? {
        if let cached = imageCache[name] { return cached }
        guard let url = bundle.url(forResource: name, withExtension: "jpg"),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        imageCache[name] = image
        return image
    }

    public func videoURL(named name: String) -> URL? {
        bundle.url(forResource: name, withExtension: "mp4")
    }

    /// Every photo asset name the manifest mentions anywhere (integrity tests).
    public func allReferencedPhotoNames() -> Set<String> {
        guard let m = manifest else { return [] }
        var names = Set(m.templates.values.flatMap(\.photos))
        m.carousels.values.forEach { $0.framePhotos.forEach { names.formUnion($0) } }
        m.videoShowcases.forEach { names.insert($0.poster) }
        return names
    }
}
```

Note: `template.cells.filter { $0.type == .photo }` — check `TemplateCell`'s actual type-discriminator property name in `Caroullage/Core/Services/TemplateParser.swift` before writing the test (it may be `kind` or an enum with different casing); adjust the test and any code to the real name.

- [ ] **Step 5: Run tests to green** (video-showcase test will fail until Task 6 bundles loops — mark it with `try XCTSkipIf(catalog.videoURL(named: "sample_loop_duo") == nil, "loops bundled in a later task")` for now and remove the skip in Task 6). Expected: PASS (with 1 skip).

- [ ] **Step 6: Commit**

```bash
git add Caroullage/Core/Services/SampleContentCatalog.swift \
        Caroullage/Resources/SampleContent/sample_content_manifest.json \
        CaroullageTests/Unit/SampleContentCatalogTests.swift
git commit -m "feat(step07): sample-content manifest + catalog with integrity tests"
```

---

### Task 4: Showcase previews in `TemplateService` (TDD)

**Files:**
- Modify: `Caroullage/Core/Services/TemplateService.swift`
- Test: `CaroullageTests/Unit/ShowcasePreviewTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
//  CaroullageTests/Unit/ShowcasePreviewTests.swift
import XCTest
@testable import Caroullage

@MainActor
final class ShowcasePreviewTests: XCTestCase {

    private var service: TemplateService!
    private var catalog: SampleContentCatalog!

    override func setUp() async throws {
        service = TemplateService()
        catalog = SampleContentCatalog()
        service.loadBundledTemplates()
        service.loadBundledCarouselTemplates()
    }

    func testShowcasePreviewRendersForEveryManifestTemplate() {
        for id in Array(catalog.manifest?.templates.keys ?? [String: SampleContentManifest.TemplateEntry]().keys) {
            guard let template = service.templates.first(where: { $0.id == id }) else { continue }
            let image = service.showcasePreview(for: template, sampleContent: catalog)
            XCTAssertNotNil(image, "showcase preview failed for \(id)")
        }
    }

    /// A template with no manifest entry falls back to nil (caller shows the
    /// schematic thumbnail instead) rather than rendering empty wells.
    func testShowcasePreviewNilWithoutManifestEntry() throws {
        let orphan = service.templates.first { catalog.manifest?.templates[$0.id] == nil }
        guard let orphan else { throw XCTSkip("all templates showcased") }
        XCTAssertNil(service.showcasePreview(for: orphan, sampleContent: catalog))
    }

    func testCarouselShowcaseCompositesFrames() {
        for id in Array(catalog.manifest?.carousels.keys ?? [String: SampleContentManifest.CarouselEntry]().keys) {
            guard let template = service.carouselTemplates.first(where: { $0.id == id }) else { continue }
            let image = service.showcasePreview(for: template, sampleContent: catalog)
            XCTAssertNotNil(image, "carousel showcase failed for \(id)")
            // Side-by-side composite of up to 3 frames: wider than a lone frame.
            if let image, template.frames.count >= 2 {
                XCTAssertGreaterThan(CGFloat(image.width) / CGFloat(image.height), 1.0)
            }
        }
    }

    /// Second call must come from cache (disk or memory) — same pixels object
    /// identity is not guaranteed, but it must not be nil and must be fast.
    func testShowcasePreviewIsCached() {
        guard let id = catalog.manifest?.templates.keys.first,
              let template = service.templates.first(where: { $0.id == id }) else {
            return XCTFail("no showcased template")
        }
        _ = service.showcasePreview(for: template, sampleContent: catalog)
        let start = Date()
        XCTAssertNotNil(service.showcasePreview(for: template, sampleContent: catalog))
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.05, "second render should be cached")
    }
}
```

- [ ] **Step 2: Run to verify failure** — expected: `showcasePreview` undefined.

- [ ] **Step 3: Implement in `TemplateService.swift`** (same file so the private disk-cache helpers are reachable):

```swift
    // MARK: - Showcase previews (Step 07)

    /// Renders the template with licensed sample photos composited into its
    /// photo zones, through the SAME renderer the editor and export use — the
    /// Home showcase's "you can make exactly this" guarantee. Returns nil when
    /// the manifest has no (complete) entry; callers fall back to `thumbnail`.
    public func showcasePreview(
        for template: CollageTemplate,
        sampleContent: SampleContentCatalog = .shared,
        maxDimension: CGFloat = 640
    ) -> CGImage? {
        guard let photos = sampleContent.samplePhotos(forTemplateID: template.id) else { return nil }
        let key = "showcase-\(template.id)-\(Self.contentFingerprint(of: template))"
            + "-s\(sampleContent.version)-r\(Self.rendererRevision)@\(Int(maxDimension))"
        if let cached = thumbnailCache[key] { return cached }
        if let disk = loadDiskThumbnail(key: key) {
            thumbnailCache[key] = disk
            return disk
        }
        let request = renderRequest(for: template, maxDimension: maxDimension)
        var photoIterator = photos.makeIterator()
        let filledCells: [RenderCell] = request.cells.map { cell in
            guard cell.image == nil, let sample = photoIterator.next()?.cgImage else { return cell }
            return RenderCell(
                frame: cell.frame, image: sample, transform: cell.transform,
                cornerRadius: cell.cornerRadius, clipShape: cell.clipShape)
        }
        let filled = RenderRequest(
            canvasSize: request.canvasSize, background: request.background,
            cells: filledCells, textOverlays: request.textOverlays,
            textFontScale: request.textFontScale,
            stickerOverlays: request.stickerOverlays, stickerImages: request.stickerImages)
        guard let image = renderer.render(filled, scale: 1) else { return nil }
        thumbnailCache[key] = image
        storeDiskThumbnail(image, key: key)
        return image
    }

    /// Carousel showcase: the first three frames (all, when fewer) side by
    /// side with small gaps, first frame full-height and the rest slightly
    /// inset, so a card-sized preview reads as "a multi-frame post".
    public func showcasePreview(
        for template: CarouselTemplate,
        sampleContent: SampleContentCatalog = .shared,
        frameMaxDimension: CGFloat = 480
    ) -> CGImage? {
        guard let framePhotos = sampleContent.sampleFramePhotos(forCarouselID: template.id)
        else { return nil }
        let key = "showcase-carousel-\(template.id)-s\(sampleContent.version)"
            + "-r\(Self.rendererRevision)@\(Int(frameMaxDimension))"
        if let cached = thumbnailCache[key] { return cached }
        if let disk = loadDiskThumbnail(key: key) {
            thumbnailCache[key] = disk
            return disk
        }

        let sortedFrames = template.frames.sorted { $0.index < $1.index }
        let shown = Array(zip(sortedFrames, framePhotos).prefix(3))
        var rendered: [CGImage] = []
        for (frame, photos) in shown {
            // editorLayout resolves TemplateCell photo zones the same way the
            // carousel editor does (see CarouselService.buildCarousel(from:)).
            let layout = TemplateService.editorLayout(
                templateID: "\(template.id)-showcase-\(frame.index)", name: template.name,
                aspectRatio: template.canvasAspectRatio, cells: frame.cells)
            let canvas = Self.canvasSize(
                forAspectRatio: template.canvasAspectRatio, maxDimension: frameMaxDimension)
            var photoIterator = photos.makeIterator()
            let cells: [RenderCell] = layout.cells.map { cell in
                RenderCell(
                    frame: CGRect(
                        x: cell.frame.origin.x * canvas.width,
                        y: cell.frame.origin.y * canvas.height,
                        width: cell.frame.width * canvas.width,
                        height: cell.frame.height * canvas.height),
                    image: photoIterator.next()?.cgImage,
                    transform: .init(), cornerRadius: 0, clipShape: .rectangle)
            }
            let request = RenderRequest(
                canvasSize: canvas, background: template.background, cells: cells,
                textOverlays: frame.cells.compactMap(\.textStyle),
                textFontScale: canvas.height / CanvasSize.size(
                    forAspectRatio: template.canvasAspectRatio).height)
            guard let image = renderer.render(request, scale: 1) else { return nil }
            rendered.append(image)
        }
        guard let composite = Self.compositeCarouselStrip(rendered) else { return nil }
        thumbnailCache[key] = composite
        storeDiskThumbnail(composite, key: key)
        return composite
    }

    /// Frames side by side: gap = 2% of frame width, later frames inset 4%
    /// vertically so the strip reads as swipeable pages, not one wide image.
    private static func compositeCarouselStrip(_ frames: [CGImage]) -> CGImage? {
        guard let first = frames.first else { return nil }
        let frameSize = CGSize(width: first.width, height: first.height)
        let gap = frameSize.width * 0.02
        let total = CGSize(
            width: frameSize.width * CGFloat(frames.count) + gap * CGFloat(frames.count - 1),
            height: frameSize.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: total, format: format)
        return renderer.image { _ in
            for (i, frame) in frames.enumerated() {
                let inset: CGFloat = i == 0 ? 0 : frameSize.height * 0.04
                UIImage(cgImage: frame).draw(in: CGRect(
                    x: CGFloat(i) * (frameSize.width + gap), y: inset / 2,
                    width: frameSize.width, height: frameSize.height - inset))
            }
        }.cgImage
    }
```

Adaptation notes for the engineer: (a) `contentFingerprint`, `rendererRevision`, `loadDiskThumbnail`, `storeDiskThumbnail`, `renderRequest(for:maxDimension:)` all already exist in this file — reuse, do not duplicate. (b) `Self.canvasSize(forAspectRatio:maxDimension:)` — if no such helper exists, derive from `CanvasSize.size(forAspectRatio:)` scaled so its longest side equals `maxDimension`. (c) `RenderCell.transform: .init()` — use whatever the identity `CellTransform` initializer actually is (check `CollageRenderer.swift` / `CellTransform` definition; `renderRequest(for:)` shows the file's own idiom — copy it). (d) `editorLayout(templateID:name:aspectRatio:cells:)` signature is at `TemplateService.swift:300` — match it exactly. (e) `TemplateLayoutCell` may carry `clipShape`/`cornerRadius` — carry them through instead of hardcoding `.rectangle`/0 if present.

- [ ] **Step 4: Run tests to green.** Expected: all `ShowcasePreviewTests` PASS.

- [ ] **Step 5: Commit**

```bash
git add Caroullage/Core/Services/TemplateService.swift CaroullageTests/Unit/ShowcasePreviewTests.swift
git commit -m "feat(step07): photo-real showcase previews through the export renderer"
```

---

### Task 5: `HeroRotationController` (TDD)

**Files:**
- Create: `Caroullage/Features/Home/HeroRotationController.swift`
- Test: `CaroullageTests/Unit/HeroRotationControllerTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
//  CaroullageTests/Unit/HeroRotationControllerTests.swift
import XCTest
@testable import Caroullage

@MainActor
final class HeroRotationControllerTests: XCTestCase {

    private var fired: [Int] = []

    private func makeController(count: Int = 4, reduceMotion: Bool = false)
        -> (HeroRotationController, () -> Void)
    {
        var tick: () -> Void = {}
        let controller = HeroRotationController(
            pageCount: count,
            reduceMotion: { reduceMotion },
            scheduler: { handler in tick = handler; return { tick = {} } })
        controller.onAdvance = { [weak self] page in self?.fired.append(page) }
        return (controller, { tick() })
    }

    func testAdvancesAndWraps() {
        let (controller, tick) = makeController(count: 3)
        controller.start()
        tick(); tick(); tick(); tick()
        XCTAssertEqual(fired, [1, 2, 0, 1])
    }

    func testPauseSuppressesAdvance() {
        let (controller, tick) = makeController()
        controller.start()
        controller.pause()
        tick()
        XCTAssertEqual(fired, [])
        controller.resume()
        tick()
        XCTAssertEqual(fired, [1])
    }

    func testReduceMotionNeverAutoAdvances() {
        let (controller, tick) = makeController(reduceMotion: true)
        controller.start()
        tick()
        XCTAssertEqual(fired, [])
    }

    func testManualSwipeResyncsPage() {
        let (controller, tick) = makeController(count: 4)
        controller.start()
        controller.noteUserMoved(to: 2)
        tick()
        XCTAssertEqual(fired, [3])
    }

    func testSinglePageNeverAdvances() {
        let (controller, tick) = makeController(count: 1)
        controller.start()
        tick()
        XCTAssertEqual(fired, [])
    }
}
```

- [ ] **Step 2: Run to verify failure.** Expected: `HeroRotationController` undefined.

- [ ] **Step 3: Implement**

```swift
//
//  HeroRotationController.swift
//  Caroullage
//
//  Step 07 — the hero card's auto-advance brain, kept off UIKit so it is
//  testable with an injected scheduler. Reduce Motion turns auto-advance off
//  entirely (swiping still works); pause/resume brackets user touches.
//

import Foundation

@MainActor
final class HeroRotationController {

    /// Installs a repeating tick and returns a cancellation closure.
    typealias Scheduler = (@escaping () -> Void) -> () -> Void

    var onAdvance: ((Int) -> Void)?

    private let pageCount: Int
    private let reduceMotion: () -> Bool
    private let scheduler: Scheduler
    private var cancel: (() -> Void)?
    private var paused = false
    private var currentPage = 0

    init(
        pageCount: Int,
        reduceMotion: @escaping () -> Bool,
        scheduler: @escaping Scheduler
    ) {
        self.pageCount = pageCount
        self.reduceMotion = reduceMotion
        self.scheduler = scheduler
    }

    /// The production scheduler: a 4-second repeating timer on the main runloop.
    static func timerScheduler(interval: TimeInterval = 4) -> Scheduler {
        { handler in
            let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
                MainActor.assumeIsolated { handler() }
            }
            return { timer.invalidate() }
        }
    }

    func start() {
        guard cancel == nil, pageCount > 1, !reduceMotion() else { return }
        cancel = scheduler { [weak self] in self?.tick() }
    }

    func stop() {
        cancel?()
        cancel = nil
    }

    func pause() { paused = true }
    func resume() { paused = false }

    /// The user swiped; future auto-advances continue from where they landed.
    func noteUserMoved(to page: Int) { currentPage = page }

    private func tick() {
        guard !paused, pageCount > 1, !reduceMotion() else { return }
        currentPage = (currentPage + 1) % pageCount
        onAdvance?(currentPage)
    }
}
```

- [ ] **Step 4: Run tests to green.**

- [ ] **Step 5: Commit**

```bash
git add Caroullage/Features/Home/HeroRotationController.swift CaroullageTests/Unit/HeroRotationControllerTests.swift
git commit -m "feat(step07): timer-injectable hero rotation controller"
```

---

### Task 6: Bake and bundle the video loops

**Files:**
- Create: `Caroullage/Resources/SampleContent/sample_loop_{duo,quad,solo}.mp4` + `_poster.jpg` each

- [ ] **Step 1: Install ffmpeg** (dev-machine tool, not a project dependency): `brew install ffmpeg`. If Homebrew is unavailable, stop and tell the owner — do not hand-roll AVFoundation compositing for a build-time asset.

- [ ] **Step 2: Download 5 short Pexels stock *video* clips** via `/browse` on `https://www.pexels.com/search/videos/<query>/` (queries: `woman smiling portrait`, `friends beach`, `city walk`, `coffee pour`, `dancing`). Criteria: bright, people-forward, ≥720p. Download the SD/HD mp4 file each page links, into the scratchpad.

- [ ] **Step 3: Composite the loops.** Each loop mirrors its manifest `layout` at 4:5 (720×900), 2.5s, muted, H.264:

```bash
S=/private/tmp/claude-501/-Users-irony-Claude-Projects-ClaudeCollage/6169005e-8b67-4e8f-a2d8-772af07f0211/scratchpad
OUT=Caroullage/Resources/SampleContent
# duo — twoUpVertical: two clips stacked, thin gap
ffmpeg -y -i "$S/clip1.mp4" -i "$S/clip2.mp4" -filter_complex \
"[0:v]scale=720:446:force_original_aspect_ratio=increase,crop=720:446,trim=0:2.5,setpts=PTS-STARTPTS[a];\
 [1:v]scale=720:446:force_original_aspect_ratio=increase,crop=720:446,trim=0:2.5,setpts=PTS-STARTPTS[b];\
 [a][b]vstack,pad=720:900:0:4:white" \
-an -c:v libx264 -pix_fmt yuv420p -crf 28 -movflags +faststart "$OUT/sample_loop_duo.mp4"
# quad — fourSquare: 2x2 grid (xstack), same trim/scale pattern at 358x446 per pane
# solo — oneCell: one clip, full-bleed 720x900 crop
ffmpeg -y -i "$S/clip5.mp4" -vf "scale=720:900:force_original_aspect_ratio=increase,crop=720:900,trim=0:2.5,setpts=PTS-STARTPTS" \
-an -c:v libx264 -pix_fmt yuv420p -crf 28 -movflags +faststart "$OUT/sample_loop_solo.mp4"
# posters — first frame of each loop
for n in duo quad solo; do ffmpeg -y -i "$OUT/sample_loop_$n.mp4" -frames:v 1 "$OUT/sample_loop_${n}_poster.jpg"; done
ls -la $OUT/sample_loop_*   # each mp4 ≤ 1.5MB; recompress with -crf 32 if over
```

For `quad`, build the 2×2 with `xstack=inputs=4:layout=0_0|w0+8_0|0_h0+8|w0+8_h0+8` over four 356×446 panes padded to 720×900 — same trim/scale idiom as duo.

- [ ] **Step 4: Add clip credits to `ATTRIBUTION.md`** (same format as photos).

- [ ] **Step 5: Remove the `XCTSkipIf` from `testVideoShowcasesResolve`** (Task 3 Step 5), `xcodegen generate`, run `SampleContentCatalogTests`. Expected: PASS, no skips.

- [ ] **Step 6: Commit**

```bash
git add Caroullage/Resources/SampleContent CaroullageTests/Unit/SampleContentCatalogTests.swift
git commit -m "feat(step07): baked video showcase loops with posters and credits"
```

---

### Task 7: Showcase UI components

**Files:**
- Create: `Caroullage/Core/DesignSystem/Components/ShowcaseTemplateCell.swift`
- Create: `Caroullage/Core/DesignSystem/Components/LoopingPreviewPlayerView.swift`

No unit tests here (pure UIKit chrome); exercised by Task 9's UI tests. Follow `FeaturedTemplateCell` (task-based image load, `prepareForReuse` cancel) and `ProjectCardCell` (spring press-down) as house patterns.

- [ ] **Step 1: `ShowcaseTemplateCell`**

```swift
//
//  ShowcaseTemplateCell.swift
//  Caroullage
//
//  Step 07 — one card in a Home showcase strip: a photo-real preview under a
//  bottom scrim carrying the template name, with optional premium-lock and
//  frame-count badges. The preview comes in via an async provider so a cold
//  render never stalls the strip; the schematic fallback means a manifest gap
//  shows the old-style thumbnail, never a blank card.
//

import UIKit

final class ShowcaseTemplateCell: UICollectionViewCell {
    static let reuseID = "ShowcaseTemplateCell"

    private let imageView = UIImageView()
    private let scrim = GradientScrimView()
    private let nameLabel = UILabel()
    private let badgeLabel = UILabel()
    private let lockBadge = UIImageView()
    private var loadTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = Theme.Color.cellWell
        imageView.layer.cornerRadius = Theme.Radius.lg
        imageView.layer.cornerCurve = .continuous
        imageView.translatesAutoresizingMaskIntoConstraints = false

        scrim.layer.cornerRadius = Theme.Radius.lg
        scrim.layer.cornerCurve = .continuous
        scrim.clipsToBounds = true
        scrim.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = Theme.Typography.subheadline
        nameLabel.textColor = .white   // always on a dark scrim, both themes
        nameLabel.numberOfLines = 1
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        badgeLabel.font = Theme.Typography.caption
        badgeLabel.textColor = .white
        badgeLabel.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        badgeLabel.layer.cornerRadius = 9
        badgeLabel.layer.cornerCurve = .continuous
        badgeLabel.clipsToBounds = true
        badgeLabel.textAlignment = .center
        badgeLabel.isHidden = true
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false

        lockBadge.image = UIImage(
            systemName: "lock.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        lockBadge.tintColor = Theme.Color.textOnAccent
        lockBadge.backgroundColor = Theme.Color.accentStrong
        lockBadge.contentMode = .center
        lockBadge.layer.cornerRadius = 11
        lockBadge.clipsToBounds = true
        lockBadge.isHidden = true
        lockBadge.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(imageView)
        contentView.addSubview(scrim)
        contentView.addSubview(nameLabel)
        contentView.addSubview(badgeLabel)
        contentView.addSubview(lockBadge)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            scrim.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            scrim.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),
            scrim.heightAnchor.constraint(equalTo: imageView.heightAnchor, multiplier: 0.38),

            nameLabel.leadingAnchor.constraint(
                equalTo: imageView.leadingAnchor, constant: Theme.Spacing.sm),
            nameLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: imageView.trailingAnchor, constant: -Theme.Spacing.sm),
            nameLabel.bottomAnchor.constraint(
                equalTo: imageView.bottomAnchor, constant: -Theme.Spacing.sm),

            badgeLabel.topAnchor.constraint(equalTo: imageView.topAnchor, constant: Theme.Spacing.xs),
            badgeLabel.trailingAnchor.constraint(
                equalTo: imageView.trailingAnchor, constant: -Theme.Spacing.xs),
            badgeLabel.heightAnchor.constraint(equalToConstant: 18),
            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 34),

            lockBadge.topAnchor.constraint(equalTo: imageView.topAnchor, constant: Theme.Spacing.xs),
            lockBadge.leadingAnchor.constraint(
                equalTo: imageView.leadingAnchor, constant: Theme.Spacing.xs),
            lockBadge.widthAnchor.constraint(equalToConstant: 22),
            lockBadge.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            UIView.animate(
                withDuration: Theme.Motion.duration(Theme.Motion.quick), delay: 0,
                usingSpringWithDamping: Theme.Motion.effectiveSpringDamping,
                initialSpringVelocity: Theme.Motion.effectiveSpringVelocity,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                self.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        loadTask = nil
        imageView.image = nil
        badgeLabel.isHidden = true
        lockBadge.isHidden = true
    }

    /// `preview` runs off the first layout pass; return the showcase render,
    /// or the schematic thumbnail as the degradation path.
    func configure(
        name: String, identifier: String, badge: String? = nil, locked: Bool = false,
        preview: @escaping () -> CGImage?
    ) {
        nameLabel.text = name
        accessibilityIdentifier = identifier
        accessibilityLabel = name
        badgeLabel.isHidden = badge == nil
        badgeLabel.text = badge.map { " \($0) " }
        lockBadge.isHidden = !locked
        loadTask?.cancel()
        loadTask = Task { @MainActor [weak self] in
            let rendered = preview()
            guard !Task.isCancelled else { return }
            self?.imageView.image = rendered.map { UIImage(cgImage: $0) }
        }
    }
}

/// Bottom-up black gradient used under showcase card titles.
final class GradientScrimView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        let gradient = layer as! CAGradientLayer
        gradient.colors = [
            UIColor.black.withAlphaComponent(0).cgColor,
            UIColor.black.withAlphaComponent(0.55).cgColor,
        ]
        gradient.locations = [0, 1]
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
```

House-rule check: the scrim is the view's **backing layer** (`layerClass`), not an inserted sublayer — see memory `uikit-gradient-sublayer-trap`.

- [ ] **Step 2: `LoopingPreviewPlayerView`**

```swift
//
//  LoopingPreviewPlayerView.swift
//  Caroullage
//
//  Step 07 — a muted, looping, poster-backed preview player for Home's video
//  showcase cards. The poster shows instantly and is the permanent state under
//  Reduce Motion or Low Power Mode; playback starts only when told the view is
//  on screen, so an off-screen strip never decodes video.
//

import AVFoundation
import UIKit

final class LoopingPreviewPlayerView: UIView {

    private let posterView = UIImageView()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?
    private var loopURL: URL?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        posterView.contentMode = .scaleAspectFill
        posterView.frame = bounds
        posterView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(posterView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var motionAllowed: Bool {
        !UIAccessibility.isReduceMotionEnabled && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    func configure(loopURL: URL?, poster: UIImage?) {
        posterView.image = poster
        self.loopURL = loopURL
        stop()
    }

    /// Called by the owning cell when it becomes visible.
    func play() {
        guard motionAllowed, let url = loopURL, player == nil else { return }
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer()
        queue.isMuted = true
        looper = AVPlayerLooper(player: queue, templateItem: item)
        let layer = AVPlayerLayer(player: queue)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        self.layer.addSublayer(layer)
        playerLayer = layer
        player = queue
        queue.play()
    }

    func stop() {
        player?.pause()
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        looper = nil
        player = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }
}
```

- [ ] **Step 3: Build** (command from header). Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Caroullage/Core/DesignSystem/Components/ShowcaseTemplateCell.swift \
        Caroullage/Core/DesignSystem/Components/LoopingPreviewPlayerView.swift
git commit -m "feat(step07): showcase card + looping preview player components"
```

---

### Task 8: Rebuild `HomeViewController` + coordinator routes

**Files:**
- Modify: `Caroullage/Features/Home/HomeViewController.swift` (top-level `HomeViewController` only — leave `HomeEmptyStateView` and `ProjectCardCell` in place)
- Create: `Caroullage/Features/Home/HeroShowcaseView.swift`
- Modify: `Caroullage/Coordinators/AppCoordinator.swift`

This is the largest task; it is still one coherent change because the screen's sections all share one data source and one wiring point.

- [ ] **Step 1: `HeroShowcaseView`** — a paged collection of full-card previews driven by `HeroRotationController`:

```swift
//
//  HeroShowcaseView.swift
//  Caroullage
//
//  Step 07 — the Home hero: a paged, auto-cycling card of flagship showcases
//  (photo, video, carousel), each a full-bleed preview with a scrim title and
//  "Tap to create". Rotation logic lives in HeroRotationController; Reduce
//  Motion disables auto-advance and the video page falls back to its poster.
//

import UIKit

@MainActor
final class HeroShowcaseView: UIView {

    struct Page {
        let title: String
        let subtitle: String
        let identifier: String
        let poster: UIImage?
        let loopURL: URL?
        let preview: () -> CGImage?
        let onTap: () -> Void
    }

    private var pages: [Page] = []
    private var rotation: HeroRotationController?
    private let pageControl = UIPageControl()
    private lazy var collectionView: UICollectionView = {
        let item = NSCollectionLayoutItem(layoutSize: .init(
            widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)))
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)),
            subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .groupPaging
        section.visibleItemsInvalidationHandler = { [weak self] _, offset, environment in
            let page = Int(round(offset.x / max(environment.container.contentSize.width, 1)))
            self?.pageChanged(to: page)
        }
        let view = UICollectionView(
            frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout(section: section))
        view.backgroundColor = .clear
        view.isScrollEnabled = true
        view.accessibilityIdentifier = "heroShowcase"
        view.layer.cornerRadius = Theme.Radius.lg
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        view.dataSource = self
        view.delegate = self
        view.register(HeroPageCell.self, forCellWithReuseIdentifier: HeroPageCell.reuseID)
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        pageControl.isUserInteractionEnabled = false
        pageControl.currentPageIndicatorTintColor = .white
        pageControl.pageIndicatorTintColor = UIColor.white.withAlphaComponent(0.4)
        addSubview(collectionView)
        addSubview(pageControl)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
            pageControl.centerXAnchor.constraint(equalTo: centerXAnchor),
            pageControl.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(pages: [Page]) {
        self.pages = pages
        pageControl.numberOfPages = pages.count
        collectionView.reloadData()
        rotation?.stop()
        let rotation = HeroRotationController(
            pageCount: pages.count,
            reduceMotion: { UIAccessibility.isReduceMotionEnabled },
            scheduler: HeroRotationController.timerScheduler())
        rotation.onAdvance = { [weak self] page in
            self?.collectionView.scrollToItem(
                at: IndexPath(item: page, section: 0), at: .centeredHorizontally,
                animated: true)
        }
        self.rotation = rotation
        rotation.start()
    }

    /// The hero stops its timer when Home leaves the screen.
    func setActive(_ active: Bool) {
        if active { rotation?.start() } else { rotation?.stop() }
        visibleLoopCells().forEach { active ? $0.play() : $0.stopLoop() }
    }

    private func pageChanged(to page: Int) {
        guard page != pageControl.currentPage, pages.indices.contains(page) else { return }
        pageControl.currentPage = page
        rotation?.noteUserMoved(to: page)
        visibleLoopCells().forEach { $0.play() }
    }

    private func visibleLoopCells() -> [HeroPageCell] {
        collectionView.visibleCells.compactMap { $0 as? HeroPageCell }
    }
}

extension HeroShowcaseView: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        pages.count
    }

    func collectionView(
        _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: HeroPageCell.reuseID, for: indexPath)
        if let hero = cell as? HeroPageCell, pages.indices.contains(indexPath.item) {
            hero.configure(with: pages[indexPath.item])
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard pages.indices.contains(indexPath.item) else { return }
        Haptics.tap()
        pages[indexPath.item].onTap()
    }

    func collectionView(
        _ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        (cell as? HeroPageCell)?.play()
        rotation?.resume()
    }
}

final class HeroPageCell: UICollectionViewCell {
    static let reuseID = "HeroPageCell"

    private let imageView = UIImageView()
    private let loopView = LoopingPreviewPlayerView()
    private let scrim = GradientScrimView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private var loadTask: Task<Void, Never>?
    private var hasLoop = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = Theme.Color.cellWell
        [imageView, loopView, scrim, titleLabel, subtitleLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        titleLabel.font = Theme.Typography.title2
        titleLabel.textColor = .white
        subtitleLabel.font = Theme.Typography.caption
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            loopView.topAnchor.constraint(equalTo: contentView.topAnchor),
            loopView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            loopView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            loopView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            scrim.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrim.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            scrim.heightAnchor.constraint(equalTo: contentView.heightAnchor, multiplier: 0.34),
            subtitleLabel.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: Theme.Spacing.md),
            subtitleLabel.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor, constant: -Theme.Spacing.md),
            titleLabel.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: Theme.Spacing.md),
            titleLabel.bottomAnchor.constraint(equalTo: subtitleLabel.topAnchor, constant: -2),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        loadTask = nil
        loopView.stop()
        hasLoop = false
        imageView.image = nil
    }

    func configure(with page: HeroShowcaseView.Page) {
        titleLabel.text = page.title
        subtitleLabel.text = page.subtitle
        accessibilityIdentifier = page.identifier
        hasLoop = page.loopURL != nil
        loopView.isHidden = !hasLoop
        loopView.configure(loopURL: page.loopURL, poster: page.poster)
        if hasLoop {
            imageView.image = page.poster
        } else {
            loadTask?.cancel()
            loadTask = Task { @MainActor [weak self] in
                let rendered = page.preview()
                guard !Task.isCancelled else { return }
                self?.imageView.image = rendered.map { UIImage(cgImage: $0) }
            }
        }
    }

    func play() { if hasLoop { loopView.play() } }
    func stopLoop() { loopView.stop() }
}
```

- [ ] **Step 2: Rebuild `HomeViewController`'s section stack.** Keep the class shell, closures, scroll/stack scaffolding, suggestions machinery, and `viewWillAppear` reload. Replace `makeFeaturedSection`/`makeQuickStartSection`/`FeaturedTemplateCell` usage with:

New wiring closures (added alongside the existing ones):

```swift
    // Step 07 showcase wiring (AppCoordinator).
    var carouselTemplatesProvider: (() -> [CarouselTemplate])?
    var onSelectCarouselTemplate: ((CarouselTemplate) -> Void)?
    var videoShowcasesProvider: (() -> [SampleContentManifest.VideoShowcase])?
    var onSelectVideoShowcase: ((SampleContentManifest.VideoShowcase) -> Void)?
    var onBrowseCarousels: (() -> Void)?
```

Section order in `setupLayout()`: hero, photo strip, video strip, carousel strip, suggestions (existing, moved down), quick-start chip row. The three strips are built by one factory (strip height 200, card width 160, same compositional-layout idiom as the old `makeFeaturedStrip`, identifiers `photoShowcaseStrip` / `videoShowcaseStrip` / `carouselShowcaseStrip`), all registering `ShowcaseTemplateCell`; the video strip's cells host a `LoopingPreviewPlayerView` — subclass `ShowcaseTemplateCell` as `VideoShowcaseCell` adding the loop view above the image view, `play()` in `willDisplay`, `stopLoop()` in `didEndDisplaying`, cap concurrent players by only playing cells in `collectionView.visibleCells`.

Cell configuration per pillar (in `cellForItemAt`):

```swift
        // Photo pillar
        card.configure(
            name: template.name,
            identifier: "showcaseTemplate-\(template.id)",
            locked: !TemplateService.shared.canOpen(template)
        ) { TemplateService.shared.showcasePreview(for: template)
            ?? TemplateService.shared.thumbnail(for: template) }

        // Carousel pillar
        card.configure(
            name: template.name,
            identifier: "showcaseCarousel-\(template.id)",
            badge: "\(template.frameCount) frames"
        ) { TemplateService.shared.showcasePreview(for: template) }

        // Video pillar (VideoShowcaseCell)
        card.configure(
            name: showcase.title,
            identifier: "showcaseVideo-\(showcase.id)",
            badge: "▶︎",
            loopURL: SampleContentCatalog.shared.videoURL(named: showcase.loop),
            poster: SampleContentCatalog.shared.image(named: showcase.poster))
```

Hero assembly in `reload()` — map `SampleContentCatalog.shared.heroRefs` to `HeroShowcaseView.Page`s, resolving each ref against the providers and skipping unresolvable refs; hero hidden when empty:

```swift
        let heroPages: [HeroShowcaseView.Page] = SampleContentCatalog.shared.heroRefs.compactMap { ref in
            switch ref.kind {
            case .template:
                guard let t = featured.first(where: { $0.id == ref.id })
                    ?? TemplateService.shared.templates.first(where: { $0.id == ref.id })
                else { return nil }
                return .init(
                    title: t.name, subtitle: String(localized: "Tap to create"),
                    identifier: "heroPage-\(t.id)", poster: nil, loopURL: nil,
                    preview: { TemplateService.shared.showcasePreview(for: t) },
                    onTap: { [weak self] in self?.onSelectTemplate?(t) })
            case .carousel:
                guard let t = carouselTemplatesProvider?().first(where: { $0.id == ref.id })
                else { return nil }
                return .init(
                    title: t.name, subtitle: String(localized: "Tap to create"),
                    identifier: "heroPage-\(t.id)", poster: nil, loopURL: nil,
                    preview: { TemplateService.shared.showcasePreview(for: t) },
                    onTap: { [weak self] in self?.onSelectCarouselTemplate?(t) })
            case .video:
                guard let s = videoShowcasesProvider?().first(where: { $0.id == ref.id })
                else { return nil }
                return .init(
                    title: s.title, subtitle: String(localized: "Tap to create"),
                    identifier: "heroPage-\(s.id)",
                    poster: SampleContentCatalog.shared.image(named: s.poster),
                    loopURL: SampleContentCatalog.shared.videoURL(named: s.loop),
                    preview: { nil },
                    onTap: { [weak self] in self?.onSelectVideoShowcase?(s) })
            }
        }
        heroView.configure(pages: heroPages)
        heroView.isHidden = heroPages.isEmpty
```

Hero constraints: pinned to the content stack width minus `Theme.Spacing.md` margins, `heightAnchor == widthAnchor * 1.15`. Add `heroView.setActive(true)` in `viewWillAppear` / `setActive(false)` in `viewDidDisappear`.

Quick-start chips: one horizontal `UIStackView` of four compact `UIButton.Configuration.tinted()` chips titled Grid / Shapes / Video / Carousel, **keeping the exact existing identifiers** `newProjectButton`, `polygonQuickStartButton`, `videoCollageButton`, `carouselQuickStartButton` and calling the same closures — this keeps `TabBarShellUITests`/`CriticalFlowTests` passing unmodified. Section headers: `String(localized:)` titles "Photo Collages", "Video Collages", "Carousels", "Start Something". Delete `FeaturedTemplateCell` and the `featuredStrip`/`makeFeaturedSection` code once nothing references them; the photo strip's "See All" keeps `seeAllTemplatesButton` and `onBrowseTemplates`; the carousel strip's "See All" gets identifier `seeAllCarouselsButton` → `onBrowseCarousels`.

- [ ] **Step 3: Wire `AppCoordinator`** (near line 50, alongside existing home wiring):

```swift
        home.carouselTemplatesProvider = { [weak self] in
            guard let self else { return [] }
            let showcased = SampleContentCatalog.shared.manifest?.carousels.keys
            return self.templateService.carouselTemplates.filter {
                showcased?.contains($0.id) ?? false
            }
        }
        home.onSelectCarouselTemplate = { [weak self] template in
            self?.openCarouselTemplate(template)
        }
        home.videoShowcasesProvider = { SampleContentCatalog.shared.videoShowcases }
        home.onSelectVideoShowcase = { [weak self] showcase in
            self?.openVideoShowcase(showcase)
        }
        home.onBrowseCarousels = { [weak self] in self?.presentCarouselTypePicker() }
```

(If the coordinator holds no `templateService` property, use `TemplateService.shared` and ensure `loadBundledCarouselTemplates()` is called at launch — check how `featuredTemplatesProvider` resolves today and mirror it.)

New routes (below `startVideoCollage()`):

```swift
    /// Opens a bundled carousel template from the Home showcase: the template's
    /// frames with photo zones EMPTY and text prefilled — the user rebuilds the
    /// preview they tapped with their own photos.
    private func openCarouselTemplate(_ template: CarouselTemplate) {
        let frames = CarouselService().buildCarousel(from: template)
        guard !frames.isEmpty else { return }
        let canvasSize = CanvasSize.size(forAspectRatio: template.canvasAspectRatio)
        presentCarouselEditor(
            frames: frames, images: [:], canvasSize: canvasSize,
            type: template.carouselType, axis: .horizontal)
    }

    /// Opens the video editor preset to the showcase's layout, cells empty.
    private func openVideoShowcase(_ showcase: SampleContentManifest.VideoShowcase) {
        guard let grid = GridTemplate(rawValue: showcase.layout) else { return }
        let canvasSize = CanvasSize.size(forAspectRatio: "4:5")
        let viewModel = VideoEditorViewModel(canvasSize: canvasSize, layout: .grid(grid))
        attachVideoAutosave(to: viewModel)
        store.saveVideo(viewModel)
        pushVideoEditor(viewModel)
    }
```

- [ ] **Step 4: Localization** — new user-facing strings use `String(localized:)`; build once so `Localizable.xcstrings` picks up the keys. Leave new keys English-only and note them in the PR — translations follow the step-06.4 localization process (deliberate, not an omission).

- [ ] **Step 5: Build, then run the full unit suite.** Expected: `BUILD SUCCEEDED`; all unit tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Caroullage/Features/Home/HomeViewController.swift \
        Caroullage/Features/Home/HeroShowcaseView.swift \
        Caroullage/Coordinators/AppCoordinator.swift \
        Caroullage/Resources/Localizable.xcstrings
git commit -m "feat(step07): Home rebuilt as photo-real showcase — hero + three pillars"
```

---

### Task 9: UI tests

**Files:**
- Create: `CaroullageUITests/UI/HomeShowcaseUITests.swift`
- Verify (modify only if red): `CaroullageUITests/UI/TabBarShellUITests.swift`, `CaroullageUITests/UI/CriticalFlowTests.swift`

- [ ] **Step 1: Write the tests.** House rule: assert identity, never visible-cell counts (memory `xcuitest-visible-cell-count-trap`).

```swift
//  CaroullageUITests/UI/HomeShowcaseUITests.swift
import XCTest

final class HomeShowcaseUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testHomeShowsHeroAndThreePillars() {
        XCTAssertTrue(app.otherElements["heroShowcase"].waitForExistence(timeout: 5)
            || app.collectionViews["heroShowcase"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.collectionViews["photoShowcaseStrip"].exists)
        XCTAssertTrue(app.collectionViews["videoShowcaseStrip"].exists)
        XCTAssertTrue(app.collectionViews["carouselShowcaseStrip"].exists)
        XCTAssertTrue(app.buttons["newProjectButton"].exists, "quick-start chips remain")
    }

    func testPhotoShowcaseOpensEditorWithEmptyZones() {
        let strip = app.collectionViews["photoShowcaseStrip"]
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        strip.cells.firstMatch.tap()
        // Grid editor canvas appears; zones are empty (the canvas exists and no
        // photo has been placed — the editor's canvas identifier is the anchor).
        XCTAssertTrue(app.otherElements["canvasView"].waitForExistence(timeout: 5))
    }

    func testCarouselShowcaseOpensCarouselEditor() {
        let strip = app.collectionViews["carouselShowcaseStrip"]
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        strip.swipeUpIntoViewIfNeeded()
        strip.cells.firstMatch.tap()
        XCTAssertTrue(app.otherElements["carouselFrameStrip"].waitForExistence(timeout: 5)
            || app.collectionViews["carouselFrameStrip"].waitForExistence(timeout: 5))
    }

    func testVideoShowcaseOpensVideoEditor() {
        let strip = app.collectionViews["videoShowcaseStrip"]
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        strip.cells.firstMatch.tap()
        XCTAssertTrue(app.otherElements["videoCanvasView"].waitForExistence(timeout: 5))
    }
}

private extension XCUIElement {
    /// Scrolls the Home scroll view until the element is hittable (max 3 swipes).
    func swipeUpIntoViewIfNeeded() {
        var attempts = 0
        while !isHittable && attempts < 3 {
            XCUIApplication().swipeUp()
            attempts += 1
        }
    }
}
```

Before running: confirm the real accessibility identifiers of the grid editor canvas, carousel frame strip, and video canvas (`grep -rn "accessibilityIdentifier" Caroullage/Features/GridEditor/CanvasView.swift Caroullage/Features/CarouselEditor Caroullage/Features/VideoEditor | grep -i canvas`) and substitute the actual values — existing UI tests (`CriticalFlowTests`, `CarouselEditorUITests`) show the working anchors; copy theirs.

- [ ] **Step 2: Run the new UI tests** — `xcodebuild test … -only-testing:CaroullageUITests/HomeShowcaseUITests`. If the runner wedges: `xcrun simctl shutdown all`, retry (full recovery recipe in memory `build-and-test-workflow`). Expected: PASS.

- [ ] **Step 3: Run the existing Home-touching UI suites** — `-only-testing:CaroullageUITests/TabBarShellUITests -only-testing:CaroullageUITests/CriticalFlowTests -only-testing:CaroullageUITests/TemplateGalleryUITests`. Quick-start identifiers were preserved, so these should pass; if one asserts on the removed `featuredTemplateStrip`, update that assertion to `photoShowcaseStrip`.

- [ ] **Step 4: Commit**

```bash
git add CaroullageUITests/UI/HomeShowcaseUITests.swift CaroullageUITests/UI/TabBarShellUITests.swift \
        CaroullageUITests/UI/CriticalFlowTests.swift
git commit -m "test(step07): Home showcase UI coverage — pillars route to their editors"
```

---

### Task 10: Full verification + visual check + docs

- [ ] **Step 1: Full test suite** — `xcodebuild test` with the Dev scheme (header command, no `-only-testing`). Expected: everything green. Fix regressions before proceeding; report the final counts truthfully.

- [ ] **Step 2: Visual check in the simulator** — build, install, launch (`xcrun simctl … install/launch`), screenshot Home in light and dark (`xcrun simctl io booted screenshot home_light.png`, toggle appearance with `xcrun simctl ui booted appearance dark`). Verify: hero renders a photo-filled card, all three strips show photo-real previews (not schematics), scrim text legible in both themes. Send the screenshots to the owner.

- [ ] **Step 3: Update `Steps/STEPS_INDEX.md`** — add a Step 07 row: "Home Showcase Redesign — photo-real hero + three pillar strips; spec 2026-08-29". Match the file's existing row format.

- [ ] **Step 4: Commit docs; leave branch integration to the owner** (per `superpowers:finishing-a-development-branch`). Device QA items to hand back: loop playback smoothness/thermals, hero cross-fade feel, showcase scroll performance on hardware.

```bash
git add Steps/STEPS_INDEX.md
git commit -m "docs(step07): index the Home showcase redesign"
```

---

## Self-review notes (already applied)

- Spec coverage: sample catalog (T2–3), previews via export renderer (T4), hero + pillars + quick-start compression + suggestions move (T8), baked loops + Reduce Motion/Low Power fallback (T6–7), routing contract (T8), degradation paths (T3 catalog / T8 fallback closures), testing (T3–5, 9), licensing (T2), bundle budget (T2/T6 size gates). Out-of-scope items untouched.
- Known adaptation points are called out inline (TemplateCell type discriminator, CellTransform identity, editor canvas identifiers, coordinator's template-service access) — verify against source at each step, do not guess.
- Premium gating: photo pillar shows the lock via `canOpen` and routes through the existing `onSelectTemplate` path (unchanged gating); carousel/video showcases are free-only by manifest rule, enforced by T3's integrity tests.
