//
//  PersistenceSmokeTests.swift
//  ClaudeCollageTests
//
//  Step 01 — verifies the SwiftData schema realizes and a project round-trips.
//  Also used to diagnose the fetch trap.
//

import XCTest
import SwiftData
@testable import ClaudeCollage

@MainActor
final class PersistenceSmokeTests: XCTestCase {

    func testContainerRealizesAndFetches() throws {
        let schema = Schema([CollageProject.self, CollageCell.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        try roundTrip(context: context)
    }

    func testOnDiskContainerRealizesAndFetches() throws {
        let schema = Schema([CollageProject.self, CollageCell.self])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-test-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        try roundTrip(context: context)
    }

    private func roundTrip(context: ModelContext) throws {

        let project = CollageProject(mode: .grid, canvasSize: CGSize(width: 1080, height: 1080))
        context.insert(project)
        try context.save()

        let descriptor = FetchDescriptor<CollageProject>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.mode, .grid)
    }
}
