//
//  HomeCollectionPlanner.swift
//  Caroullage
//
//  Home retention, phase 2 — which collections Home shows today, in what order.
//
//  Pure, like `CarouselGalleryFilter`: a list in, a list out, the date and the
//  onboarding answer passed rather than read, so every rule here is pinned by
//  a test with a fixed clock. The order it produces:
//
//    1. pinned — in-window seasonal collections and anything marked new,
//       highest priority first;
//    2. affinity — collections for what the user said they make;
//    3. the rest, rotated by the ISO week so the same file reads differently
//       next Monday;
//    …capped at `maxStrips`, then
//    4. the pillars, always, in file order, never capped.
//
//  Out-of-window collections are dropped before any of that, and a weekly
//  pick is sliced from its list by the same week number, so "this week's
//  picks" really are this week's.
//

import Foundation

enum HomeCollectionPlanner {

    /// The calendar the week number and the windows are read on: ISO 8601, so
    /// a week is the same week in every locale the app ships in.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar
    }()

    static func plan(
        _ collections: [HomeCollection],
        now: Date,
        creatorKind: CreatorKind?,
        calendar: Calendar = calendar,
        maxStrips: Int = 5
    ) -> [HomeCollection] {
        let week = weekIndex(now: now, calendar: calendar)
        let live = collections
            .filter { $0.window.map { isInWindow($0, now: now, calendar: calendar) } ?? true }
            .map { apply(weeklyPick: $0, week: week) }

        let pillars = live.filter(\.isPillar)
        let candidates = live.filter { !$0.isPillar }

        let pinned = candidates
            .filter { $0.window != nil || $0.isNew }
            .sorted { lhs, rhs in
                lhs.priority == rhs.priority ? lhs.id < rhs.id : lhs.priority > rhs.priority
            }
        let affinity = candidates.filter { collection in
            guard !pinned.contains(collection), let creatorKind else { return false }
            return collection.creatorKinds.contains(creatorKind.rawValue)
        }
        let rest = candidates.filter { !pinned.contains($0) && !affinity.contains($0) }

        let chosen = Array((pinned + affinity + rotate(rest, by: week)).prefix(max(0, maxStrips)))
        return chosen + pillars
    }

    // MARK: - Distinct items

    /// The plan with every card shown ONCE on the whole screen.
    ///
    /// The file's collections overlap on purpose — a template can be both
    /// "Clean & Minimal" and one of "This Week's Picks" — but Home showing the
    /// same card in the hero, a curated strip and a pillar reads as a catalog
    /// padded out, not curated. So the screen is walked top to bottom and each
    /// card is claimed by the first place it appears:
    ///
    ///   1. `alreadyShown` — the hero's pages — claim theirs first;
    ///   2. each chosen collection keeps only cards not yet claimed, and is
    ///      dropped (claiming nothing) when fewer than `minimumItems` remain;
    ///      the next candidate takes its place, up to `maxStrips`;
    ///   3. each pillar keeps its unclaimed cards and is topped back up to its
    ///      authored length from `pools` (the catalog, best first), so the
    ///      closing strips show what the screen has not.
    ///
    /// Pass `plan(…, maxStrips: .max)` in, so a dropped collection has a
    /// replacement to promote.
    static func distinct(
        _ planned: [HomeCollection],
        excluding alreadyShown: [HomeCollection.Kind: [String]] = [:],
        pools: [HomeCollection.Kind: [String]] = [:],
        minimumItems: Int = 4,
        maxStrips: Int = 3
    ) -> [HomeCollection] {
        var claimed: [HomeCollection.Kind: Set<String>] = alreadyShown.mapValues(Set.init)
        func unclaimed(_ ids: [String], _ kind: HomeCollection.Kind) -> [String] {
            var seen = claimed[kind] ?? []
            return ids.filter { seen.insert($0).inserted }
        }

        var chosen: [HomeCollection] = []
        for collection in planned where !collection.isPillar && chosen.count < maxStrips {
            let items = unclaimed(collection.itemIDs, collection.kind)
            guard items.count >= max(1, minimumItems) else { continue }
            claimed[collection.kind, default: []].formUnion(items)
            chosen.append(collection.with(itemIDs: items))
        }

        var pillars: [HomeCollection] = []
        for pillar in planned where pillar.isPillar {
            var items = unclaimed(pillar.itemIDs, pillar.kind)
            if items.count < pillar.itemIDs.count {
                let topUp = unclaimed(pools[pillar.kind] ?? [], pillar.kind)
                    .filter { !items.contains($0) }
                items += topUp.prefix(pillar.itemIDs.count - items.count)
            }
            guard !items.isEmpty else { continue }
            claimed[pillar.kind, default: []].formUnion(items)
            pillars.append(pillar.with(itemIDs: items))
        }
        return chosen + pillars
    }

    // MARK: - Windows

    /// Whether `now` falls inside the window, inclusive at both ends. A window
    /// whose start is after its end wraps the new year.
    static func isInWindow(
        _ window: HomeCollection.Window, now: Date, calendar: Calendar = calendar
    ) -> Bool {
        guard let start = dayOfYear(window.start), let end = dayOfYear(window.end) else { return false }
        let today = calendar.component(.month, from: now) * 100 + calendar.component(.day, from: now)
        if start <= end { return today >= start && today <= end }
        return today >= start || today <= end
    }

    /// "MM-dd" as a comparable month-day number, e.g. "11-16" → 1116.
    private static func dayOfYear(_ text: String) -> Int? {
        let parts = text.split(separator: "-")
        guard parts.count == 2, let month = Int(parts[0]), let day = Int(parts[1]),
              (1 ... 12).contains(month), (1 ... 31).contains(day) else { return nil }
        return month * 100 + day
    }

    // MARK: - Weeks

    /// A number that changes once a week and never repeats within a year.
    static func weekIndex(now: Date, calendar: Calendar = calendar) -> Int {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        return (components.yearForWeekOfYear ?? 0) * 53 + (components.weekOfYear ?? 0)
    }

    private static func rotate<T>(_ items: [T], by amount: Int) -> [T] {
        guard items.count > 1 else { return items }
        let shift = ((amount % items.count) + items.count) % items.count
        return Array(items[shift...] + items[..<shift])
    }

    /// Slices a weekly-pick collection's items for this week.
    private static func apply(weeklyPick collection: HomeCollection, week: Int) -> HomeCollection {
        guard let pick = collection.weeklyPick, pick > 0, collection.itemIDs.count > pick
        else { return collection }
        let rotated = rotate(collection.itemIDs, by: week * pick)
        return collection.with(itemIDs: Array(rotated.prefix(pick)))
    }

    /// The next seasonal window to open after `now`, and when: what the
    /// seasonal-drop reminder is about. A window already open is not "next".
    static func nextSeasonalDrop(
        _ collections: [HomeCollection], after now: Date, calendar: Calendar = calendar
    ) -> (collection: HomeCollection, windowStart: Date)? {
        let year = calendar.component(.year, from: now)
        var best: (HomeCollection, Date)?
        for collection in collections {
            guard let window = collection.window, let start = dayOfYear(window.start) else { continue }
            for candidateYear in [year, year + 1] {
                var components = DateComponents()
                components.year = candidateYear
                components.month = start / 100
                components.day = start % 100
                guard let date = calendar.date(from: components), date > now else { continue }
                if best == nil || date < best!.1 { best = (collection, date) }
                break
            }
        }
        return best.map { (collection: $0.0, windowStart: $0.1) }
    }

    // MARK: - Debugging

    /// `-debug.homeDate YYYY-MM-DD` on the launch line, so a seasonal window
    /// can be walked on a simulator without waiting for the season.
    static func overrideDate(from defaults: UserDefaults = .standard) -> Date? {
        guard let raw = DevelopmentHooks.homeDate(in: defaults) else { return nil }
        let parts = raw.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        return calendar.date(from: components)
    }
}
