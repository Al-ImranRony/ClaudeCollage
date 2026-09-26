//
//  ExportEventsTests.swift
//  CaroullageTests
//
//  Step 06 review fix. The export notification carries the project id, and
//  the store marks that project — and only that project — exported.
//

import XCTest
import SwiftData
@testable import Caroullage

@MainActor
final class ExportEventsTests: XCTestCase {

    func testTheNotificationCarriesTheProjectID() {
        let id = UUID()
        let received = expectation(forNotification: ExportEvents.didExportProject, object: nil) { note in
            ExportEvents.projectID(from: note) == id
        }
        ExportEvents.projectExported(id)
        wait(for: [received], timeout: 1)
    }

    func testAForeignNotificationYieldsNoID() {
        XCTAssertNil(ExportEvents.projectID(from: Notification(name: ExportEvents.didExportProject)))
    }

    func testMarkingExportedThroughTheEventClearsTheUnfinishedList() throws {
        let schema = Schema(versionedSchema: CaroullageSchemaV1.self)
        let container = try ModelContainer(
            for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let store = ProjectStore(container: container)
        let viewModel = GridEditorViewModel()
        store.save(viewModel)
        let since = Date().addingTimeInterval(-3600)
        XCTAssertEqual(store.mostRecentUnexported(since: since)?.id, viewModel.projectID)

        // What the coordinator does on the notification.
        let note = Notification(
            name: ExportEvents.didExportProject, object: nil,
            userInfo: [ExportEvents.projectIDKey: viewModel.projectID])
        if let id = ExportEvents.projectID(from: note) { store.markExported(id: id) }

        XCTAssertNil(store.mostRecentUnexported(since: since), "An exported project is not nagged about")
    }
}
