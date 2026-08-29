//
//  SampleContentCatalogTests.swift
//  CaroullageTests
//
//  Step 07 — integrity of the bundled sample-content manifest. The Home showcase
//  dresses template previews in real licensed photography, so a manifest entry
//  whose photo array is the wrong length renders a half-empty preview that looks
//  broken rather than aspirational. These tests hold the manifest to the real
//  catalog: every id resolves, every array length matches the template's actual
//  photo-zone count, every asset it names is bundled, and nothing showcased is
//  premium (the showcase must be openable by a free user).
//

import AVFoundation
import XCTest
@testable import Caroullage

@MainActor
final class SampleContentCatalogTests: XCTestCase {

    /// The app bundle — the unit test bundle carries none of the app's resources.
    private var appBundle: Bundle { Bundle(for: CollageRenderer.self) }

    private func makeCatalog() -> SampleContentCatalog {
        SampleContentCatalog(bundle: appBundle)
    }

    private func makeTemplateService() -> TemplateService {
        let service = TemplateService(bundle: appBundle)
        service.loadBundledTemplates()
        service.loadBundledCarouselTemplates()
        return service
    }

    // MARK: - Manifest

    func testManifestLoads() throws {
        let catalog = makeCatalog()
        let manifest = try XCTUnwrap(
            catalog.manifest,
            "sample_content_manifest.json must be bundled and decodable"
        )
        XCTAssertGreaterThanOrEqual(manifest.version, 1)
        XCTAssertEqual(catalog.version, manifest.version)
    }

    func testAllReferencedPhotoAssetsExist() throws {
        let catalog = makeCatalog()
        let names = catalog.allReferencedPhotoNames()
        XCTAssertFalse(names.isEmpty, "the manifest must reference at least one sample photo")
        for name in names {
            XCTAssertNotNil(
                catalog.image(named: name),
                "\(name): referenced by the manifest but not bundled as \(name).jpg"
            )
        }
    }

    // MARK: - Templates

    func testTemplateEntriesMatchCatalog() throws {
        let catalog = makeCatalog()
        let service = makeTemplateService()
        let entries = try XCTUnwrap(catalog.manifest?.templates)

        XCTAssertGreaterThanOrEqual(entries.count, 8, "the showcase needs at least 8 dressed templates")

        for (id, entry) in entries {
            let template = try XCTUnwrap(
                service.templates.first { $0.id == id },
                "\(id): manifest names a template that is not in the bundled catalog"
            )
            let photoZones = template.cells.filter { $0.zoneType == .photo }.count
            XCTAssertEqual(
                entry.photos.count, photoZones,
                "\(id): manifest lists \(entry.photos.count) photos for \(photoZones) photo zones"
            )
            XCTAssertFalse(
                template.isPremium,
                "\(id): a showcased template must be free — the showcase is the free user's first impression"
            )
            XCTAssertNotNil(
                catalog.samplePhotos(forTemplateID: id),
                "\(id): every named photo must resolve, or the preview draws half-dressed"
            )
        }
    }

    // MARK: - Carousels

    func testCarouselEntriesMatchCatalog() throws {
        let catalog = makeCatalog()
        let service = makeTemplateService()
        let entries = try XCTUnwrap(catalog.manifest?.carousels)

        XCTAssertGreaterThanOrEqual(entries.count, 6, "the showcase needs at least 6 dressed carousels")

        for (id, entry) in entries {
            let template = try XCTUnwrap(
                service.carouselTemplates.first { $0.id == id },
                "\(id): manifest names a carousel that is not in the bundled catalog"
            )
            XCTAssertEqual(
                entry.framePhotos.count, template.frames.count,
                "\(id): manifest dresses \(entry.framePhotos.count) frames of \(template.frames.count)"
            )
            // The manifest's arrays are authored in frame order, so compare against
            // frames sorted by `index` rather than by their JSON order.
            let frames = template.frames.sorted { $0.index < $1.index }
            for (offset, names) in entry.framePhotos.enumerated() where offset < frames.count {
                let photoZones = frames[offset].cells.filter { $0.zoneType == .photo }.count
                XCTAssertEqual(
                    names.count, photoZones,
                    "\(id) frame \(frames[offset].index): \(names.count) photos for \(photoZones) photo zones"
                )
            }
            XCTAssertFalse(
                template.isPremium,
                "\(id): a showcased carousel must be free"
            )
            XCTAssertNotNil(
                catalog.sampleFramePhotos(forCarouselID: id),
                "\(id): every named photo must resolve"
            )
        }
    }

    // MARK: - Video showcases

    func testVideoShowcasesResolve() throws {
        let catalog = makeCatalog()

        XCTAssertGreaterThanOrEqual(catalog.videoShowcases.count, 3)
        for showcase in catalog.videoShowcases {
            XCTAssertNotNil(
                GridTemplate(rawValue: showcase.layout),
                "\(showcase.id): '\(showcase.layout)' is not a GridTemplate case"
            )
            XCTAssertNotNil(
                catalog.image(named: showcase.poster),
                "\(showcase.id): poster \(showcase.poster).jpg is not bundled"
            )
            XCTAssertNotNil(
                catalog.videoURL(named: showcase.loop),
                "\(showcase.id): loop \(showcase.loop).mp4 is not bundled"
            )
        }
    }

    /// The app never configures an `AVAudioSession`, so it runs on the default
    /// non-mixing `soloAmbient` category. A Home loop that carries even a silent
    /// audio track can activate that session on autoplay and duck whatever the user
    /// is listening to — for a muted decorative preview. The loops are baked with
    /// `-an`, and this test is what keeps them that way.
    func testVideoLoopsCarryNoAudioTrack() async throws {
        let catalog = makeCatalog()
        let showcases = catalog.videoShowcases
        XCTAssertFalse(showcases.isEmpty, "there must be video showcases to check")

        for showcase in showcases {
            let url = try XCTUnwrap(
                catalog.videoURL(named: showcase.loop),
                "\(showcase.id): loop \(showcase.loop).mp4 is not bundled"
            )
            let asset = AVURLAsset(url: url)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            XCTAssertTrue(
                audioTracks.isEmpty,
                "\(showcase.id): \(showcase.loop).mp4 carries \(audioTracks.count) audio track(s) — a bundled loop must have none, or autoplay ducks the user's music"
            )
        }
    }

    // MARK: - Hero

    func testHeroEntriesResolve() throws {
        let catalog = makeCatalog()
        let manifest = try XCTUnwrap(catalog.manifest)
        let hero = catalog.heroRefs

        XCTAssertGreaterThanOrEqual(hero.count, 4, "the hero rail needs at least 4 entries to feel alive")
        XCTAssertEqual(
            Set(hero.map(\.kind)), Set(SampleContentManifest.HeroKind.allCases),
            "the hero rail must showcase all three content kinds"
        )

        for ref in hero {
            switch ref.kind {
            case .template:
                XCTAssertNotNil(manifest.templates[ref.id], "hero template '\(ref.id)' has no manifest entry")
            case .carousel:
                XCTAssertNotNil(manifest.carousels[ref.id], "hero carousel '\(ref.id)' has no manifest entry")
            case .video:
                XCTAssertTrue(
                    manifest.videoShowcases.contains { $0.id == ref.id },
                    "hero video '\(ref.id)' has no videoShowcases entry"
                )
            }
        }
    }

    // MARK: - Degradation

    func testUnknownTemplateReturnsNil() {
        let catalog = makeCatalog()
        XCTAssertNil(
            catalog.samplePhotos(forTemplateID: "no-such-template"),
            "an unknown id must degrade to nil (caller falls back to a schematic), never crash"
        )
        XCTAssertNil(catalog.sampleFramePhotos(forCarouselID: "no-such-carousel"))
    }
}
