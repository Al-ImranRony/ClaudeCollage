//
//  GalleryFilter.swift
//  Caroullage
//
//  Step 06 — the saved-project gallery's narrowing: mode, then search, then
//  sort.
//
//  It used to run twice, because the Carousel tab was this gallery filtered to
//  carousels. Step 07 gave that tab to the carousel template catalog, so today
//  only the Projects tab calls it, with `mode: nil`. The mode parameter stays:
//  it is what "By type" grouping is built on, and it is the pin these unit tests
//  hold in place.
//

import Foundation

/// How the gallery is ordered. Search narrows within the chosen order.
enum GallerySortOrder: Int, CaseIterable {
    case recent, oldest, byMode

    var title: String {
        switch self {
        case .recent: return "Recent"
        case .oldest: return "Oldest"
        case .byMode: return "By type"
        }
    }

    /// The glyph shown beside this order in the sort menu.
    var symbolName: String {
        switch self {
        case .recent: return "clock"
        case .oldest: return "clock.arrow.circlepath"
        case .byMode: return "square.grid.2x2"
        }
    }
}

/// Turns the saved-project list into what a gallery actually shows.
enum GalleryFilter {

    /// The projects a tab is allowed to show at all, before search and sort.
    /// `nil` means "every kind" — what the Projects tab passes.
    static func modeFiltered(
        _ summaries: [ProjectSummary], mode: CollageMode?
    ) -> [ProjectSummary] {
        guard let mode else { return summaries }
        return summaries.filter { $0.mode == mode }
    }

    /// The final ordered list for the grid.
    static func visible(
        _ summaries: [ProjectSummary],
        mode: CollageMode?,
        search: String,
        sort: GallerySortOrder
    ) -> [ProjectSummary] {
        var filtered = modeFiltered(summaries, mode: mode)

        let query = search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            filtered = filtered.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
        }

        switch sort {
        case .recent:
            filtered.sort { $0.updatedAt > $1.updatedAt }
        case .oldest:
            filtered.sort { $0.updatedAt < $1.updatedAt }
        case .byMode:
            // Grouped by type, newest first inside each group.
            filtered.sort {
                $0.mode.rawValue == $1.mode.rawValue
                    ? $0.updatedAt > $1.updatedAt
                    : $0.mode.rawValue < $1.mode.rawValue
            }
        }
        return filtered
    }

    /// Whether the "nothing here yet" panel should be shown.
    ///
    /// Two rules, and the second is the one that is easy to get wrong. The panel
    /// invites you to create something, so it belongs when you genuinely have
    /// none of this kind — but a search that matched nothing is a different
    /// situation entirely, and offering to create a project there answers a
    /// question the user did not ask.
    static func showsEmptyState(
        _ summaries: [ProjectSummary], mode: CollageMode?, search: String
    ) -> Bool {
        guard search.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return modeFiltered(summaries, mode: mode).isEmpty
    }

    /// What the gallery's header row says it is showing.
    ///
    /// The row used to hold a full-width Recent/Oldest segmented control — a lot of
    /// screen for a binary choice most people never change. It now carries this on
    /// the left and a compact sort menu on the right, which is both lighter and
    /// more informative than what it replaced.
    ///
    /// Zero is named rather than counted: "0 Carousels" reads as something that
    /// failed, "No carousels" reads as a state you are in.
    static func countLabel(count: Int, singular: String, plural: String) -> String {
        switch count {
        case ..<1: return "No \(plural.lowercased())"
        case 1: return "1 \(singular)"
        default: return "\(count) \(plural)"
        }
    }
}
