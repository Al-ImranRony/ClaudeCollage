//
//  HeroStageTests.swift
//  CaroullageTests
//
//  The Home hero's stages: which page goes on which stage, and that the
//  manifest dresses every stage with what it needs. The views themselves are
//  checked by eye (they are motion); what can drift silently is the data.
//

import XCTest
@testable import Caroullage

@MainActor
final class HeroStageTests: XCTestCase {

    private var appBundle: Bundle { Bundle(for: CollageRenderer.self) }

    private func makeCatalog() -> SampleContentCatalog { SampleContentCatalog(bundle: appBundle) }

    private func makeTemplateService() -> TemplateService {
        let service = TemplateService(bundle: appBundle)
        service.loadBundledTemplates()
        service.loadBundledCarouselTemplates()
        return service
    }

    // MARK: - Lineup

    /// Video leads: running content is the strongest first impression, so the
    /// hero opens on a loop and no other kind outnumbers video.
    func testHeroLeadsWithVideo() throws {
        let hero = makeCatalog().heroRefs
        XCTAssertEqual(hero.first?.kind, .video, "the hero opens on a video")
        let counts = Dictionary(grouping: hero, by: \.kind).mapValues(\.count)
        let videos = counts[.video] ?? 0
        for (kind, count) in counts where kind != .video {
            XCTAssertLessThanOrEqual(count, videos, "\(kind) outnumbers video in the hero")
        }
    }

    /// Two loops back to back waste the motion: the eye stops noticing it. Videos
    /// are spread through the rotation instead.
    func testHeroNeverRunsTwoVideosInARow() {
        let kinds = makeCatalog().heroRefs.map(\.kind)
        for (a, b) in zip(kinds, kinds.dropFirst()) {
            XCTAssertFalse(a == .video && b == .video, "two hero videos in a row")
        }
    }

    func testEveryNamedStageIsOneThisBuildKnows() {
        for ref in makeCatalog().heroRefs {
            if let raw = ref.stage {
                XCTAssertNotNil(SampleContentManifest.HeroStage(rawValue: raw),
                                "hero '\(ref.id)' names unknown stage '\(raw)'")
            }
        }
    }

    func testCompareStagesHaveAPhotoToWipe() throws {
        let catalog = makeCatalog()
        let compares = catalog.heroRefs.filter { $0.heroStage == .compare }
        XCTAssertFalse(compares.isEmpty, "the before/after carousel is shown as a wipe")
        for ref in compares {
            let name = try XCTUnwrap(ref.photo, "compare page '\(ref.id)' names no photo")
            let photo = try XCTUnwrap(catalog.image(named: name), "'\(name)' is not bundled")
            XCTAssertNotNil(HeroCompareGrade.before(from: photo))
        }
    }

    // MARK: - Carousel dressing

    /// No placeholder copy ("Name 1", "Phase 2") in a sample the hero deals
    /// out as a deck — and the copy lines up with the frames it dresses.
    func testDeckCarouselsAreDressedWithRealCopy() throws {
        let catalog = makeCatalog()
        let service = makeTemplateService()
        let manifest = try XCTUnwrap(catalog.manifest)
        let decks = catalog.heroRefs.filter { $0.kind == .carousel && $0.heroStage != .compare }
        XCTAssertFalse(decks.isEmpty)

        for ref in decks {
            let template = try XCTUnwrap(service.carouselTemplates.first { $0.id == ref.id })
            let entry = try XCTUnwrap(manifest.carousels[ref.id])
            let texts = try XCTUnwrap(entry.frameTexts, "deck '\(ref.id)' keeps its placeholder copy")
            XCTAssertEqual(texts.count, entry.framePhotos.count, "'\(ref.id)' copy and photos disagree on frames")
            let frames = template.frames.sorted { $0.index < $1.index }
            for (frame, copy) in zip(frames, texts) {
                let zones = frame.cells.compactMap(\.textStyle).count
                XCTAssertLessThanOrEqual(copy.count, zones, "'\(ref.id)' frame \(frame.index) has more copy than text zones")
            }
        }
    }

    func testShowcaseFramesDealEveryFrameWithTheDressedCopy() throws {
        let catalog = makeCatalog()
        let service = makeTemplateService()
        let team = try XCTUnwrap(service.carouselTemplates.first { $0.id == "carousel-matched-team" })
        let frames = service.showcaseFrames(for: team, sampleContent: catalog, maxDimension: 200)
        XCTAssertEqual(frames.count, team.frames.count, "every frame becomes a card")
        // A 1:1 template comes back square: the deck sizes its cards from this.
        let first = try XCTUnwrap(frames.first)
        XCTAssertEqual(first.width, first.height)
    }

    /// The hero draws its deck off the main actor; that path must deal exactly
    /// the frames the synchronous one does, cold cache or warm.
    func testBackgroundFramesMatchTheSynchronousOnes() async throws {
        let catalog = makeCatalog()
        let team = try XCTUnwrap(makeTemplateService().carouselTemplates.first { $0.id == "carousel-matched-team" })
        let background = await makeTemplateService().showcaseFramesInBackground(
            for: team, sampleContent: catalog, maxDimension: 120)
        let synchronous = makeTemplateService().showcaseFrames(for: team, sampleContent: catalog, maxDimension: 120)
        XCTAssertEqual(background.count, team.frames.count)
        XCTAssertEqual(background.map { [$0.width, $0.height] }, synchronous.map { [$0.width, $0.height] })
    }

    func testBackgroundGradeMatchesTheSynchronousOne() async throws {
        let photo = try XCTUnwrap(makeCatalog().image(named: "sample_seasonal_01"))
        let background = await HeroCompareGrade.beforeInBackground(from: photo)
        XCTAssertEqual(background?.size, photo.size)
        XCTAssertTrue(background === HeroCompareGrade.before(from: photo), "both paths share one cache")
    }

    // MARK: - Stage resolution

    func testTallWorkStandsAsAStoryAndTheRestFills() {
        typealias Stage = HeroShowcaseView.Page.Stage
        XCTAssertEqual(Stage.resolve(aspect: 9.0 / 16.0), .story(aspect: 9.0 / 16.0))
        XCTAssertEqual(Stage.resolve(aspect: 2.0 / 3.0), .story(aspect: 2.0 / 3.0))
        XCTAssertEqual(Stage.resolve(aspect: 4.0 / 5.0), .fill)
        XCTAssertEqual(Stage.resolve(aspect: 1), .fill)
        XCTAssertEqual(Stage.resolve(aspect: 16.0 / 9.0), .fill)
        XCTAssertEqual(Stage.resolve(aspect: 0), .fill, "an unknown shape fills rather than vanishing")
    }

    // MARK: - Before grade

    func testBeforeGradeIsTheSamePhotoWithTheColourTakenOut() throws {
        let photo = try XCTUnwrap(makeCatalog().image(named: "sample_seasonal_01"))
        let before = try XCTUnwrap(HeroCompareGrade.before(from: photo))
        XCTAssertEqual(before.size, photo.size, "the wipe lines the two halves up pixel for pixel")
        XCTAssertLessThan(try saturation(of: before), try saturation(of: photo) * 0.6)
    }

    private func saturation(of image: UIImage) throws -> CGFloat {
        let cg = try XCTUnwrap(image.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        let drew: Bool = pixel.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        XCTAssertTrue(drew)
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
        UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                blue: CGFloat(pixel[2]) / 255, alpha: 1)
            .getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
        return sat
    }
}
