//
//  PersistenceDurabilityTests.swift
//  CaroullageTests
//
//  Pre-submission. Two ways the library used to lose work without a word:
//
//  - A store that failed to open was swapped for an in-memory one, so the user
//    saw an empty library AND everything made afterwards vanished on relaunch.
//    Now the unreadable files are set aside (kept, not deleted) and a fresh
//    store opens on disk, so new work persists and the old data can be recovered.
//  - A state `JSONEncoder` refuses (a non-finite Double from a gesture) was
//    written as `nil` over the last good save. Now the last good save stays.
//

import Foundation
import SwiftData
import XCTest
@testable import Caroullage

@MainActor
final class PersistenceDurabilityTests: XCTestCase {

    private var directory: URL!

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersistenceDurabilityTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        try await super.tearDown()
    }

    private var storeURL: URL { directory.appendingPathComponent("default.store") }

    // MARK: - Opening the store

    func testAHealthyStoreOpensWithItsProjects() throws {
        do {
            let store = ProjectStore(container: ModelContainerFactory.makeContainer(storeURL: storeURL))
            store.save(GridEditorViewModel())
        }
        let reopened = ProjectStore(container: ModelContainerFactory.makeContainer(storeURL: storeURL))

        XCTAssertEqual(reopened.projectCount(), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recoveredFolder.path), "nothing to set aside")
    }

    func testAnUnreadableStoreIsSetAsideAndAFreshOneOpensOnDisk() throws {
        let garbage = Data("not a database".utf8)
        try garbage.write(to: storeURL)

        let container = ModelContainerFactory.makeContainer(storeURL: storeURL)

        let configuration = try XCTUnwrap(container.configurations.first)
        XCTAssertFalse(configuration.isStoredInMemoryOnly, "new work must survive a relaunch")
        XCTAssertEqual(configuration.url.standardizedFileURL, storeURL.standardizedFileURL)

        // The unreadable file is kept for recovery, not destroyed.
        let setAside = try FileManager.default.subpathsOfDirectory(atPath: recoveredFolder.path)
            .filter { $0.hasSuffix("default.store") }
        XCTAssertEqual(setAside.count, 1)
        let kept = try Data(contentsOf: recoveredFolder.appendingPathComponent(try XCTUnwrap(setAside.first)))
        XCTAssertEqual(kept, garbage)

        // And the fresh store persists.
        do {
            let store = ProjectStore(container: container)
            store.save(GridEditorViewModel())
        }
        let reopened = ProjectStore(container: ModelContainerFactory.makeContainer(storeURL: storeURL))
        XCTAssertEqual(reopened.projectCount(), 1)
    }

    private var recoveredFolder: URL { directory.appendingPathComponent("Recovered", isDirectory: true) }

    func testTheStoresExternalDataIsSetAsideWithIt() throws {
        // SwiftData keeps `.externalStorage` blobs (personal stickers) in a
        // `.<store>_SUPPORT` folder beside the file; leaving it behind would
        // orphan the old blobs next to the fresh store.
        try Data("not a database".utf8).write(to: storeURL)
        let support = directory.appendingPathComponent(".default_SUPPORT/_EXTERNAL_DATA", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: support.appendingPathComponent("blob"))

        _ = ModelContainerFactory.makeContainer(storeURL: storeURL)

        let setAside = try FileManager.default.subpathsOfDirectory(atPath: recoveredFolder.path)
        XCTAssertTrue(setAside.contains { $0.hasSuffix(".default_SUPPORT/_EXTERNAL_DATA/blob") }, "\(setAside)")
    }

    // MARK: - The versioned schema

    func testTheSchemaIsVersionedAndStoresNoEditorTypes() {
        XCTAssertEqual(CaroullageMigrationPlan.schemas.map { $0.versionIdentifier }, [Schema.Version(1, 0, 0)])
        // CollageCell (dead since Step 00) stored CellTransform, CellFilters and
        // [TextOverlay] as columns, tying the frozen schema to live editor types.
        let entities = Set(Schema(versionedSchema: CaroullageSchemaV1.self).entities.map(\.name))
        XCTAssertEqual(entities, ["CollageProject", "PersonalSticker"])
    }

    func testAStoreFromBeforeVersioningMigratesWithItsProjects() throws {
        // Written by the pre-versioning schema (CollageCell table with a row,
        // CollageProject.exportSettings) — every development install up to v1.
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Integration
            .deletingLastPathComponent()   // CaroullageTests
            .appendingPathComponent("Fixtures/UnversionedStore/default.store")
        try FileManager.default.copyItem(at: fixture, to: storeURL)

        let container = ModelContainerFactory.makeContainer(storeURL: storeURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: recoveredFolder.path), "migrated, not set aside")
        XCTAssertFalse(try XCTUnwrap(container.configurations.first).isStoredInMemoryOnly)
        XCTAssertFalse(container.schema.entities.map(\.name).contains("CollageCell"))
        let store = ProjectStore(container: container)
        XCTAssertEqual(Set(store.listSummaries().compactMap(\.name)), ["Legacy grid", "Legacy carousel"])
        XCTAssertNotNil(store.loadViewModel(id: try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<PersonalSticker>()), 1)

        // The next launch opens it straight through the migration plan.
        let relaunched = ProjectStore(container: ModelContainerFactory.makeContainer(storeURL: storeURL))
        XCTAssertEqual(relaunched.projectCount(), 2)
    }

    // MARK: - Saving

    func testAStateThatCannotBeEncodedDoesNotEraseTheLastGoodSave() throws {
        let store = ProjectStore(container: ModelContainerFactory.makeContainer(storeURL: storeURL))
        let viewModel = GridEditorViewModel()
        store.save(viewModel)
        XCTAssertNotNil(store.loadViewModel(id: viewModel.projectID))

        var broken = viewModel.state
        broken.borderWidth = .nan          // JSONEncoder throws on a non-finite Double
        viewModel.restore(state: broken, images: [:])
        store.save(viewModel)

        let resumed = try XCTUnwrap(store.loadViewModel(id: viewModel.projectID),
                                    "the last good save must still open")
        XCTAssertTrue(resumed.state.borderWidth.isFinite)
    }
}
