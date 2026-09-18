//
//  ProjectLibraryTests.swift
//  CaroullageTests
//
//  Step 05 batch D — naming, renaming and duplicating projects.
//
//  The gallery's own filtering is UI state, but everything it depends on lives
//  here and is testable: what a project is called when the user hasn't named it,
//  what renaming does with whitespace, and that a duplicate is genuinely
//  independent of its original.
//

import XCTest
import SwiftData
@testable import Caroullage

@MainActor
final class ProjectLibraryTests: XCTestCase {

    private func makeStore() throws -> ProjectStore {
        let schema = Schema([CollageProject.self, CollageCell.self, PersonalSticker.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return ProjectStore(container: container)
    }

    private func makeProject(in store: ProjectStore) -> UUID {
        let viewModel = GridEditorViewModel()
        store.save(viewModel)
        return viewModel.projectID
    }

    // MARK: - Display name

    func testAnUnnamedProjectFallsBackToItsType() throws {
        let store = try makeStore()
        _ = makeProject(in: store)

        let summary = try XCTUnwrap(store.listSummaries().first)
        XCTAssertNil(summary.name)
        XCTAssertFalse(summary.displayName.isEmpty,
                       "A card must never render a blank title")
    }

    func testRenamingShowsThroughToTheSummary() throws {
        let store = try makeStore()
        let id = makeProject(in: store)

        store.rename(id: id, to: "Beach trip")
        let summary = try XCTUnwrap(store.listSummaries().first { $0.id == id })
        XCTAssertEqual(summary.name, "Beach trip")
        XCTAssertEqual(summary.displayName, "Beach trip")
    }

    func testWhitespaceOnlyNameClearsRatherThanStoringBlanks() throws {
        // Otherwise a card shows an empty title and search can never match it.
        let store = try makeStore()
        let id = makeProject(in: store)

        store.rename(id: id, to: "Named")
        store.rename(id: id, to: "   ")

        let summary = try XCTUnwrap(store.listSummaries().first { $0.id == id })
        XCTAssertNil(summary.name)
        XCTAssertFalse(summary.displayName.isEmpty)
    }

    func testRenamingTrimsSurroundingWhitespace() throws {
        let store = try makeStore()
        let id = makeProject(in: store)
        store.rename(id: id, to: "  Sunset  ")
        XCTAssertEqual(store.listSummaries().first { $0.id == id }?.name, "Sunset")
    }

    // MARK: - Duplicate

    func testDuplicateCreatesAnIndependentProject() throws {
        let store = try makeStore()
        let original = makeProject(in: store)
        store.rename(id: original, to: "Original")

        let copy = try XCTUnwrap(store.duplicate(id: original))
        XCTAssertNotEqual(copy, original)
        XCTAssertEqual(store.listSummaries().count, 2)

        // Deleting one must leave the other whole — the entire point of copying
        // the files rather than referencing them.
        store.delete(id: original)
        XCTAssertEqual(store.listSummaries().count, 1)
        XCTAssertEqual(store.listSummaries().first?.id, copy)
    }

    func testDuplicateIsNamedDistinctly() throws {
        let store = try makeStore()
        let id = makeProject(in: store)
        store.rename(id: id, to: "Sunset")

        let copy = try XCTUnwrap(store.duplicate(id: id))
        let name = try XCTUnwrap(store.listSummaries().first { $0.id == copy }?.name)
        XCTAssertNotEqual(name, "Sunset", "A duplicate must be tellable from its original")
        XCTAssertTrue(name.contains("Sunset"))
    }

    func testDuplicatingTwiceDoesNotProduceTwoIdenticalNames() {
        // "Sunset" → "Sunset copy" → "Sunset copy 2"
        let first = ProjectStore.duplicateName(of: "Sunset")
        let second = ProjectStore.duplicateName(of: first)
        let third = ProjectStore.duplicateName(of: second)

        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(second, third)
        XCTAssertEqual(Set([first, second, third]).count, 3)
    }

    func testDuplicatingAnUnknownProjectIsHarmless() throws {
        let store = try makeStore()
        XCTAssertNil(store.duplicate(id: UUID()))
        XCTAssertTrue(store.listSummaries().isEmpty)
    }

    func testRenamingAnUnknownProjectIsHarmless() throws {
        let store = try makeStore()
        store.rename(id: UUID(), to: "Nothing")   // must not trap
        XCTAssertTrue(store.listSummaries().isEmpty)
    }

    // MARK: - Mode labels

    func testEveryModeHasACardLabel() {
        for mode in CollageMode.allCases {
            XCTAssertFalse(mode.displayName.isEmpty, "\(mode) has no card label")
        }
    }

    // MARK: - Recents and export bookkeeping (Home retention, phase 1)

    func testRecentSummariesAreNewestFirstAndBounded() throws {
        let store = try makeStore()
        let first = makeProject(in: store)
        Thread.sleep(forTimeInterval: 0.02)
        let second = makeProject(in: store)
        Thread.sleep(forTimeInterval: 0.02)
        let third = makeProject(in: store)

        let recent = store.recentSummaries(limit: 2)
        XCTAssertEqual(recent.map(\.id), [third, second],
                       "The strip shows the newest work first and never more than it asked for")
        XCTAssertEqual(store.recentSummaries(limit: 10).map(\.id), [third, second, first])
        XCTAssertTrue(store.recentSummaries(limit: 0).isEmpty)
    }

    func testProjectCountNeedsNoThumbnails() throws {
        let store = try makeStore()
        XCTAssertEqual(store.projectCount(), 0)
        _ = makeProject(in: store)
        _ = makeProject(in: store)
        XCTAssertEqual(store.projectCount(), 2)
    }

    func testASummaryStillCarriesItsThumbnailAndName() throws {
        // The bounded listing fetches only the columns a summary needs; that
        // must include the two a card actually draws.
        let store = try makeStore()
        let id = makeProject(in: store)
        store.rename(id: id, to: "Lake day")
        let summary = try XCTUnwrap(store.recentSummaries(limit: 1).first)
        XCTAssertEqual(summary.name, "Lake day")
        XCTAssertEqual(summary.mode, .grid)
        XCTAssertNotNil(summary.thumbnail, "A saved grid project renders a thumbnail on save")
    }

    func testMarkingExportedRemovesAProjectFromTheUnfinishedList() throws {
        let store = try makeStore()
        let id = makeProject(in: store)
        let since = Date().addingTimeInterval(-3600)

        XCTAssertEqual(store.mostRecentUnexported(since: since)?.id, id,
                       "A fresh project has never been exported")

        let exportedAt = Date()
        store.markExported(id: id, at: exportedAt)
        XCTAssertNil(store.mostRecentUnexported(since: since))

        let summary = try XCTUnwrap(store.recentSummaries(limit: 1).first)
        XCTAssertGreaterThanOrEqual(exportedAt, summary.updatedAt,
                                    "Exporting is not editing: it must not bump updatedAt")
    }

    func testUnfinishedIgnoresProjectsOlderThanTheWindow() throws {
        let store = try makeStore()
        _ = makeProject(in: store)
        XCTAssertNil(store.mostRecentUnexported(since: Date().addingTimeInterval(60)),
                     "A project edited before the window started is not nagged about")
    }
}
