//
//  AIServiceTests.swift
//  CaroullageTests
//
//  Step 05 batch A — subject lifting and orchestration.
//
//  Vision's ML requests cannot run in the simulator ("Could not create inference
//  context"), so `AIService` takes its segmenter by injection and these tests
//  supply a deterministic stub. What is covered here is everything the app itself
//  is responsible for: compositing a mask into real alpha, trimming to the
//  subject, converting Vision's coordinate space, and behaving sanely when
//  segmentation finds nothing or fails outright.
//
//  The Vision adapter itself is device-QA'd; there is no way to fake that here
//  that would prove anything.
//

import XCTest
import CoreGraphics
@testable import Caroullage

// MARK: - Stub

/// Returns whatever the test asks it to, including failure.
private struct StubSegmenter: SubjectSegmenting {
    var mask: CGImage?
    var faces: [CGRect] = []
    var salient: [CGRect] = []
    var error: SegmentationError?

    func foregroundMask(for image: CGImage) async throws -> CGImage? {
        if let error { throw error }
        return mask
    }
    func faceRects(in image: CGImage) async throws -> [CGRect] {
        if let error { throw error }
        return faces
    }
    func salientRects(in image: CGImage) async throws -> [CGRect] {
        if let error { throw error }
        return salient
    }
}

@MainActor
final class AIServiceTests: XCTestCase {

    // MARK: - Fixtures

    /// Opaque colour field.
    private func makePhoto(width: Int = 200, height: Int = 200) -> CGImage {
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.9, green: 0.5, blue: 0.2, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    /// Grayscale mask: white inside `subject`, black elsewhere.
    private func makeMask(width: Int = 200, height: Int = 200, subject: CGRect) -> CGImage {
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(subject)
        return ctx.makeImage()!
    }

    private func alpha(of image: CGImage, atX x: Int, y: Int) -> UInt8 {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let ctx = CGContext(
            data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels[(y * image.width + x) * 4 + 3]
    }

    // MARK: - Subject lifting

    func testLiftedSubjectHasTransparencyOutsideTheMask() async throws {
        let photo = makePhoto()
        let subject = CGRect(x: 50, y: 50, width: 100, height: 100)
        let service = AIService(segmenter: StubSegmenter(mask: makeMask(subject: subject)))

        let lifted = try await service.liftSubject(from: photo)

        // Cropped to the subject, so the result is the masked region's size.
        XCTAssertEqual(lifted.width, 100, accuracy: 2)
        XCTAssertEqual(lifted.height, 100, accuracy: 2)
        XCTAssertGreaterThan(alpha(of: lifted, atX: lifted.width / 2, y: lifted.height / 2), 200,
                             "The subject itself must stay opaque")
    }

    func testLiftedSubjectIsTrimmedToItsOwnBounds() async throws {
        // A small subject in a large photo must not come back photo-sized with
        // transparent margins — it gets dragged around as a sticker.
        let photo = makePhoto(width: 400, height: 400)
        let service = AIService(segmenter: StubSegmenter(
            mask: makeMask(width: 400, height: 400,
                           subject: CGRect(x: 160, y: 160, width: 80, height: 80))))

        let lifted = try await service.liftSubject(from: photo)

        XCTAssertLessThan(lifted.width, 120, "Trimmed, not photo-sized")
        XCTAssertLessThan(lifted.height, 120)
    }

    func testNoSubjectIsReportedDistinctlyFromFailure() async {
        // A flat landscape is a normal outcome, not an error the UI should shout
        // about — so it must be its own case.
        let service = AIService(segmenter: StubSegmenter(mask: nil))
        do {
            _ = try await service.liftSubject(from: makePhoto())
            XCTFail("Expected noSubjectFound")
        } catch let error as AIService.AIError {
            XCTAssertEqual(error, .noSubjectFound)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testAnEmptyMaskAlsoReportsNoSubject() async {
        // Segmentation returned a mask, but it is entirely black: nothing lifts.
        let service = AIService(segmenter: StubSegmenter(mask: makeMask(subject: .zero)))
        do {
            _ = try await service.liftSubject(from: makePhoto())
            XCTFail("Expected noSubjectFound")
        } catch let error as AIService.AIError {
            XCTAssertEqual(error, .noSubjectFound)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testVisionFailurePropagates() async {
        // The simulator's real behaviour: Vision cannot start at all.
        let service = AIService(segmenter: StubSegmenter(
            error: .visionUnavailable("Could not create inference context")))
        do {
            _ = try await service.liftSubject(from: makePhoto())
            XCTFail("Expected the segmentation error to propagate")
        } catch let error as SegmentationError {
            XCTAssertEqual(error, .visionUnavailable("Could not create inference context"))
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testExtractStickerMatchesSubjectLift() async throws {
        // Same operation, workflow-specific name; must not drift apart.
        let photo = makePhoto()
        let mask = makeMask(subject: CGRect(x: 40, y: 40, width: 120, height: 120))
        let service = AIService(segmenter: StubSegmenter(mask: mask))

        let lifted = try await service.liftSubject(from: photo)
        let sticker = try await service.extractSticker(from: photo)
        XCTAssertEqual(lifted.width, sticker.width)
        XCTAssertEqual(lifted.height, sticker.height)
    }

    // MARK: - Coordinate space

    func testVisionRectsAreFlippedToTopLeft() {
        // Vision's origin is bottom-left; the rest of the app is top-left.
        let bottomLeft = CGRect(x: 0.1, y: 0.0, width: 0.2, height: 0.25)
        let topLeft = AIService.flippedToTopLeft(bottomLeft)

        XCTAssertEqual(topLeft.minX, 0.1, accuracy: 0.0001, "x is untouched")
        XCTAssertEqual(topLeft.minY, 0.75, accuracy: 0.0001, "A rect at the bottom becomes a rect at the top")
        XCTAssertEqual(topLeft.height, 0.25, accuracy: 0.0001)
    }

    func testFlippingIsItsOwnInverse() {
        let rect = CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.2)
        let roundTrip = AIService.flippedToTopLeft(AIService.flippedToTopLeft(rect))
        XCTAssertEqual(roundTrip.minY, rect.minY, accuracy: 0.0001)
    }

    func testFeaturesCarryFlippedDetectionsAndTrueAspect() async {
        let service = AIService(segmenter: StubSegmenter(
            mask: nil,
            faces: [CGRect(x: 0.1, y: 0.0, width: 0.2, height: 0.2)]))

        let features = await service.features(for: makePhoto(width: 400, height: 200))

        XCTAssertEqual(features.aspectRatio, 2, accuracy: 0.001)
        XCTAssertEqual(features.faces.first?.minY ?? -1, 0.8, accuracy: 0.0001,
                       "A face at Vision's bottom is a face at the top in app space")
    }

    // MARK: - Auto-layout orchestration

    func testSuggestLayoutsReturnsAtLeastOne() async {
        let service = AIService(segmenter: StubSegmenter(mask: nil))
        let suggestions = await service.suggestLayouts(for: [makePhoto(), makePhoto(), makePhoto()])
        XCTAssertFalse(suggestions.isEmpty)
        XCTAssertLessThanOrEqual(suggestions.count, 5)
    }

    func testSuggestLayoutsSurvivesVisionBeingUnavailable() async {
        // The real simulator case, and a real device case under memory pressure:
        // analysis fails for every photo. Suggestions must degrade to
        // shape-based, not vanish.
        let service = AIService(segmenter: StubSegmenter(error: .visionUnavailable("no context")))
        let suggestions = await service.suggestLayouts(for: [makePhoto(), makePhoto()])
        XCTAssertFalse(suggestions.isEmpty,
                       "A failed analysis must still yield layout suggestions")
    }

    func testSuggestLayoutsWithNoPhotosReturnsNothing() async {
        let service = AIService(segmenter: StubSegmenter(mask: nil))
        let suggestions = await service.suggestLayouts(for: [])
        XCTAssertTrue(suggestions.isEmpty)
    }

    // MARK: - Availability

    func testGenerativeBackgroundsUnavailableInSimulator() {
        // Guards the "never advertise a feature this device cannot run" rule.
        let service = AIService(segmenter: StubSegmenter(mask: nil))
        XCTAssertFalse(service.generativeBackgroundsAvailable)
    }
}

/// `XCTAssertEqual` for Int with a tolerance — Core Image can be a pixel off
/// after resampling a mask, and that is not a defect worth failing on.
private func XCTAssertEqual(
    _ lhs: Int, _ rhs: Int, accuracy: Int, file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertLessThanOrEqual(abs(lhs - rhs), accuracy,
                             "\(lhs) is not within \(accuracy) of \(rhs)", file: file, line: line)
}
