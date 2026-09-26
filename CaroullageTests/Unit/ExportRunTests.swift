//
//  ExportRunTests.swift
//  CaroullageTests
//
//  Pre-account hardening. Every editor's export now runs through one sequence:
//  make the artifact, hand it over, settle the credit on what actually
//  happened. The three editors used to each carry their own copy, and they had
//  drifted — the carousel's image-set share never took the credit at all, so a
//  single purchased credit unlocked watermark-free image sets without limit.
//

import Foundation
import XCTest
@testable import Caroullage

@MainActor
final class ExportRunTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var credits: CreditStore!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "ExportRunTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        credits = CreditStore(defaults: defaults)
        credits.grant(.single)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        credits = nil
        try await super.tearDown()
    }

    private func paidSession() -> ExportCreditSession {
        let session = ExportCreditSession(credits: credits)
        XCTAssertTrue(session.begin())
        return session
    }

    private let artifact = ExportArtifact.images([Data([1])], fileExtension: "jpg", baseName: "Collage")

    // MARK: - Delivered

    func testAPhotosSaveKeepsTheCredit() async {
        let outcome = await ExportRun.perform(credit: paidSession(), destination: .photos,
                                              produce: { self.artifact },
                                              handOver: { _ in [] })

        guard case .delivered = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(credits.balance, 0)
    }

    // MARK: - A share holds the credit until the sheet closes

    private func heldShare() async -> ExportCreditSession {
        let session = paidSession()
        let shared = [URL(fileURLWithPath: "/tmp/Collage.jpg")]
        let outcome = await ExportRun.perform(credit: session, destination: .share,
                                              produce: { self.artifact },
                                              handOver: { _ in shared })
        guard case .delivered(let urls, _) = outcome else { XCTFail("\(outcome)"); return session }
        XCTAssertEqual(urls, shared)
        return session
    }

    func testAShareHoldsTheCreditWhileTheSheetIsOpen() async {
        // Writing the files is not delivery: the user has nothing until they
        // share. The credit stays taken but unsettled.
        let session = await heldShare()

        XCTAssertTrue(session.isActive)
        XCTAssertEqual(credits.balance, 0)
    }

    func testDismissingTheShareSheetGivesTheCreditBack() async {
        let session = await heldShare()

        session.settle(after: .stillOpen)          // an activity was cancelled; the sheet is still up
        XCTAssertTrue(session.isActive)
        session.settle(after: .dismissed)

        XCTAssertFalse(session.isActive)
        XCTAssertEqual(credits.balance, 1)
    }

    func testSharingKeepsTheCredit() async {
        let session = await heldShare()

        session.settle(after: .shared)

        XCTAssertFalse(session.isActive)
        XCTAssertEqual(credits.balance, 0)
    }

    func testTheSheetsCompletionValuesMapToHowItEnded() {
        XCTAssertEqual(ShareSheetEnding(activityChosen: true, completed: true), .shared)
        XCTAssertEqual(ShareSheetEnding(activityChosen: false, completed: false), .dismissed)
        // iOS reports a cancelled activity while leaving the sheet on screen;
        // the files must survive that, for the user's next choice.
        XCTAssertEqual(ShareSheetEnding(activityChosen: true, completed: false), .stillOpen)
    }

    func testAnEntitledExportNeverTouchesTheBalance() async {
        let outcome = await ExportRun.perform(credit: ExportCreditSession(credits: credits), destination: .photos,
                                              produce: { self.artifact },
                                              handOver: { _ in [] })

        guard case .delivered = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(credits.balance, 1)
    }

    // MARK: - Not delivered: the credit goes back

    func testAFailedRenderGivesTheCreditBack() async {
        struct RenderFailed: Error {}
        let outcome = await ExportRun.perform(credit: paidSession(), destination: .photos,
                                              produce: { throw RenderFailed() },
                                              handOver: { _ in [] })

        guard case .failed(.making, _) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(credits.balance, 1)
    }

    func testAFailedHandOverGivesTheCreditBack() async {
        let outcome = await ExportRun.perform(credit: paidSession(), destination: .photos,
                                              produce: { self.artifact },
                                              handOver: { _ in throw PhotoLibrarySaver.SaveError.notAuthorized })

        guard case .failed(.delivering, let error) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(error as? PhotoLibrarySaver.SaveError, .notAuthorized)
        XCTAssertEqual(credits.balance, 1)
    }

    func testACancelledRenderGivesTheCreditBackAndIsNotAFailure() async {
        let outcome = await ExportRun.perform(credit: paidSession(), destination: .photos,
                                              produce: { throw VideoComposer.ComposerError.cancelled },
                                              handOver: { _ in [] })

        guard case .cancelled = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(credits.balance, 1)
    }

    func testARefusalGivesTheCreditBackAndCarriesItsMessage() async {
        let refusal = ExportRefusal(title: "Nothing to Export", message: "Add a video to a slot first.")
        let outcome = await ExportRun.perform(credit: paidSession(), destination: .photos,
                                              produce: { throw refusal },
                                              handOver: { _ in [] })

        guard case .refused(let carried) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(carried, refusal)
        XCTAssertEqual(credits.balance, 1)
    }

    // MARK: - Files for the share sheet

    func testASingleImageIsSharedUnderItsPlainName() throws {
        let folder = try ExportFiles.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let urls = try ExportFiles.write([Data([1])], fileExtension: "png", baseName: "Collage", into: folder)

        XCTAssertEqual(urls.map(\.lastPathComponent), ["Collage.png"])
    }

    func testSeveralImagesAreNumberedInCarouselOrder() throws {
        // Order is the contract: the share sheet passes these straight to the
        // apps a carousel is posted from.
        let folder = try ExportFiles.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let urls = try ExportFiles.write((1 ... 3).map { Data([UInt8($0)]) },
                                         fileExtension: "jpg", baseName: "Carousel", into: folder)

        XCTAssertEqual(urls.map(\.lastPathComponent), ["Carousel_01.jpg", "Carousel_02.jpg", "Carousel_03.jpg"])
        XCTAssertEqual(try urls.map { try Data(contentsOf: $0) }, [Data([1]), Data([2]), Data([3])])
    }

    func testEveryExportGetsItsOwnFolder() throws {
        // A shorter carousel must not share the previous run's extra frames.
        let first = try ExportFiles.makeFolder()
        let second = try ExportFiles.makeFolder()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: second.path), [])
    }

    func testNoImagesIsAnError() throws {
        let folder = try ExportFiles.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertThrowsError(try ExportFiles.write([], fileExtension: "jpg", baseName: "Carousel", into: folder))
    }

    // MARK: - One place takes credits

    func testOnlyTheExportFlowSpendsCredits() throws {
        // The carousel's image-set share bypassed the credit because each editor
        // hand-rolled its own session. Now only the shared flow opens one.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Caroullage")
        var openers: [String] = []
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: url, encoding: .utf8)
            if source.contains("ExportCreditSession(") { openers.append(url.lastPathComponent) }
        }
        XCTAssertEqual(openers, ["EditorExportFlow.swift"])
    }

    func testNoEditorHandsAFileOverOutsideTheFlow() throws {
        // The carousel's share used to build its own UIActivityViewController,
        // which is how it skipped the credit. Photos saves and share sheets
        // belong to EditorExportFlow alone.
        let features = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Caroullage/Features")
        for editor in ["GridEditor/GridEditorViewController.swift",
                       "CarouselEditor/CarouselEditorViewController.swift",
                       "VideoEditor/VideoEditorViewController.swift"] {
            let source = try String(contentsOf: features.appendingPathComponent(editor), encoding: .utf8)
            for bypass in ["UIActivityViewController(", "PhotoLibrarySaver(", "ExportCreditSession("] {
                XCTAssertFalse(source.contains(bypass), "\(editor) hands a file over itself via \(bypass)")
            }
        }
    }
}
