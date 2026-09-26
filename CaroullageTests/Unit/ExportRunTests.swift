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

    func testADeliveredExportKeepsTheCreditAndReturnsTheSharedFiles() async {
        let shared = [URL(fileURLWithPath: "/tmp/Collage.jpg")]
        let outcome = await ExportRun.perform(credit: paidSession(),
                                              produce: { self.artifact },
                                              handOver: { _ in shared })

        guard case .delivered(let urls) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(urls, shared)
        XCTAssertEqual(credits.balance, 0)
    }

    func testAnEntitledExportNeverTouchesTheBalance() async {
        let outcome = await ExportRun.perform(credit: ExportCreditSession(credits: credits),
                                              produce: { self.artifact },
                                              handOver: { _ in [] })

        guard case .delivered = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(credits.balance, 1)
    }

    // MARK: - Not delivered: the credit goes back

    func testAFailedRenderGivesTheCreditBack() async {
        struct RenderFailed: Error {}
        let outcome = await ExportRun.perform(credit: paidSession(),
                                              produce: { throw RenderFailed() },
                                              handOver: { _ in [] })

        guard case .failed(.making, _) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(credits.balance, 1)
    }

    func testAFailedHandOverGivesTheCreditBack() async {
        let outcome = await ExportRun.perform(credit: paidSession(),
                                              produce: { self.artifact },
                                              handOver: { _ in throw PhotoLibrarySaver.SaveError.notAuthorized })

        guard case .failed(.delivering, let error) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(error as? PhotoLibrarySaver.SaveError, .notAuthorized)
        XCTAssertEqual(credits.balance, 1)
    }

    func testACancelledRenderGivesTheCreditBackAndIsNotAFailure() async {
        let outcome = await ExportRun.perform(credit: paidSession(),
                                              produce: { throw VideoComposer.ComposerError.cancelled },
                                              handOver: { _ in [] })

        guard case .cancelled = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(credits.balance, 1)
    }

    func testARefusalGivesTheCreditBackAndCarriesItsMessage() async {
        let refusal = ExportRefusal(title: "Nothing to Export", message: "Add a video to a slot first.")
        let outcome = await ExportRun.perform(credit: paidSession(),
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
}
