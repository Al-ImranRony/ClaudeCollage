//
//  SpotlightIndexer.swift
//  ClaudeCollage
//
//  Step 05 batch C — saved projects become results in iOS Spotlight.
//
//  Needs no entitlement, so unlike the widgets this works fully today.
//
//  The attribute building is a pure function so it can be tested headlessly;
//  `CSSearchableIndex` itself is I/O and is exercised on device.
//

import CoreSpotlight
import Foundation
import UIKit
import UniformTypeIdentifiers

struct SpotlightIndexer: Sendable {

    /// Prefix for `NSUserActivity` / Spotlight identifiers, so a deep link can be
    /// recognised as ours and turned back into a project id.
    static let domain = "com.devron.claudecollage.project"

    init() {}

    // MARK: - Pure

    /// Searchable metadata for one project.
    ///
    /// Title and description are what the user actually reads in Spotlight, so
    /// they are written as a person would say them rather than as field dumps.
    func attributes(for summary: ProjectSummary) -> CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .image)
        attributes.title = Self.title(for: summary.mode)
        attributes.contentDescription = Self.description(for: summary)
        attributes.contentModificationDate = summary.updatedAt
        attributes.keywords = Self.keywords(for: summary.mode)
        attributes.thumbnailData = summary.thumbnail?.jpegData(compressionQuality: 0.7)
        return attributes
    }

    /// Stable identifier ↔ project id, both directions.
    static func identifier(for id: UUID) -> String { "\(domain).\(id.uuidString)" }

    /// The project id inside one of our Spotlight identifiers, or nil if the
    /// identifier is not ours.
    static func projectID(fromIdentifier identifier: String) -> UUID? {
        guard identifier.hasPrefix("\(domain).") else { return nil }
        return UUID(uuidString: String(identifier.dropFirst(domain.count + 1)))
    }

    static func title(for mode: CollageMode) -> String {
        switch mode {
        case .grid: return "Grid collage"
        case .polygon: return "Shape collage"
        case .template: return "Template collage"
        case .carousel: return "Carousel"
        case .video: return "Video collage"
        }
    }

    static func description(for summary: ProjectSummary) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "Edited \(formatter.string(from: summary.updatedAt))"
    }

    static func keywords(for mode: CollageMode) -> [String] {
        // "collage" and "photo" on everything so a general search finds the app's
        // work at all; the mode word narrows it.
        ["collage", "photo", title(for: mode).lowercased()]
    }

    // MARK: - Indexing

    func index(_ summaries: [ProjectSummary]) {
        let items = summaries.map { summary in
            CSSearchableItem(
                uniqueIdentifier: Self.identifier(for: summary.id),
                domainIdentifier: Self.domain,
                attributeSet: attributes(for: summary))
        }
        guard !items.isEmpty else { return }
        CSSearchableIndex.default().indexSearchableItems(items)
    }

    func remove(id: UUID) {
        CSSearchableIndex.default()
            .deleteSearchableItems(withIdentifiers: [Self.identifier(for: id)])
    }
}
