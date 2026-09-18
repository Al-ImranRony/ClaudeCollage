//
//  EngagementReminderPolicy.swift
//  Caroullage
//
//  Home retention, phase 3 — when the app may tap the user on the shoulder.
//
//  Two reminders, both about something real: a collage they started and
//  never exported, and a seasonal collection whose window is about to open.
//  Nothing else, ever. The rules are a pure value over injected defaults, like
//  `RatingPromptPolicy`, so every one of them is pinned by a test with a fixed
//  clock rather than trusted:
//
//    - off unless the user turned reminders on in Settings;
//    - nothing in the first day after install;
//    - at most one reminder a week and two a month, counting what was
//      scheduled;
//    - the unfinished-project nudge fires a day after the last edit, never
//      within two hours of the user last opening the app, and only for work
//      touched in the last week;
//    - a seasonal drop fires at ten in the morning on the day its window
//      opens, once per collection, never for a window already open.
//
//  Scheduling is `EngagementReminderScheduler`'s job; this only decides.
//

import Foundation

public struct EngagementReminderPolicy {

    public enum Kind: String, Sendable {
        case unfinishedProject = "unfinished"
        case seasonalDrop = "seasonal"
    }

    /// One reminder the scheduler should have pending.
    public struct Decision: Equatable, Sendable {
        public let kind: Kind
        public let identifier: String
        public let title: String
        public let body: String
        public let fireDate: Date
        public let deepLink: URL
    }

    /// The most recently edited, never-exported project, as the store reports it.
    public struct UnfinishedProject: Equatable, Sendable {
        public let id: UUID
        public let name: String
        public let updatedAt: Date

        public init(id: UUID, name: String, updatedAt: Date) {
            self.id = id
            self.name = name
            self.updatedAt = updatedAt
        }
    }

    /// The next seasonal collection to open, as the planner reports it.
    public struct SeasonalDrop: Equatable, Sendable {
        public let collectionID: String
        public let title: String
        public let windowStart: Date

        public init(collectionID: String, title: String, windowStart: Date) {
            self.collectionID = collectionID
            self.title = title
            self.windowStart = windowStart
        }
    }

    public static let unfinishedIdentifier = "caroullage.reminder.unfinished"
    /// Per collection AND per year: the same season comes round again, and a
    /// record keyed on the id alone would have announced it exactly once for
    /// the life of the install.
    public static func seasonalIdentifier(_ collectionID: String, year: Int) -> String {
        "caroullage.reminder.seasonal.\(collectionID).\(year)"
    }
    /// Bookings older than this are forgotten. Long enough to enforce the
    /// monthly cap, short enough that last year's season does not block this
    /// year's.
    static let bookingMemory: TimeInterval = 60 * 24 * 3600

    static let quietAfterInstall: TimeInterval = 24 * 3600
    static let unfinishedDelay: TimeInterval = 24 * 3600
    static let unfinishedWindow: TimeInterval = 7 * 24 * 3600
    static let minimumGapAfterOpen: TimeInterval = 2 * 3600
    static let week: TimeInterval = 7 * 24 * 3600
    static let month: TimeInterval = 30 * 24 * 3600
    static let maxPerWeek = 1
    static let maxPerMonth = 2
    /// A seasonal drop is only worth booking this far ahead.
    static let seasonalHorizon: TimeInterval = 45 * 24 * 3600
    static let seasonalHour = 10

    private enum Key {
        static let enabled = "reminders.enabled"
        static let scheduled = "reminders.scheduled"     // [identifier: fireDate]
        static let lastOpenedAt = "reminders.lastOpenedAt"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - State

    /// The Settings toggle. Off until the user turns it on; never inferred
    /// from system authorization alone.
    public var isEnabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        nonmutating set { defaults.set(newValue, forKey: Key.enabled) }
    }

    public var lastOpenedAt: Date? {
        defaults.object(forKey: Key.lastOpenedAt) as? Date
    }

    /// Every reminder booked so far, by identifier, with the date it was set
    /// to fire. Re-booking an identifier replaces its entry, so a nudge that
    /// moved never counts twice.
    public var scheduled: [String: Date] {
        (defaults.dictionary(forKey: Key.scheduled) as? [String: Date]) ?? [:]
    }

    public func recordScheduled(_ decision: Decision) {
        var all = scheduled
        all[decision.identifier] = decision.fireDate
        defaults.set(all, forKey: Key.scheduled)
    }

    /// Drops bookings whose fire date is more than `bookingMemory` in the past.
    public func forgetOldBookings(now: Date) {
        let kept = scheduled.filter { now.timeIntervalSince($0.value) <= Self.bookingMemory }
        guard kept.count != scheduled.count else { return }
        defaults.set(kept, forKey: Key.scheduled)
    }

    public func recordCancelled(identifier: String) {
        var all = scheduled
        all[identifier] = nil
        defaults.set(all, forKey: Key.scheduled)
    }

    public func recordOpened(now: Date = Date()) {
        defaults.set(now, forKey: Key.lastOpenedAt)
    }

    // MARK: - Decisions

    public func decisions(
        now: Date,
        installedAt: Date,
        unfinished: UnfinishedProject?,
        seasonal: SeasonalDrop?,
        calendar: Calendar = .current
    ) -> [Decision] {
        guard isEnabled else { return [] }
        guard now >= installedAt.addingTimeInterval(Self.quietAfterInstall) else { return [] }

        forgetOldBookings(now: now)
        var booked = scheduled
        var out: [Decision] = []

        if let unfinished, let decision = unfinishedDecision(unfinished, now: now),
           fits(decision, among: booked) {
            out.append(decision)
            booked[decision.identifier] = decision.fireDate
        }

        if let seasonal, let decision = seasonalDecision(seasonal, now: now, calendar: calendar),
           booked[decision.identifier] == nil, fits(decision, among: booked) {
            out.append(decision)
            booked[decision.identifier] = decision.fireDate
        }

        return out
    }

    private func unfinishedDecision(_ project: UnfinishedProject, now: Date) -> Decision? {
        guard now.timeIntervalSince(project.updatedAt) <= Self.unfinishedWindow else { return nil }
        var fireDate = max(project.updatedAt.addingTimeInterval(Self.unfinishedDelay),
                           now.addingTimeInterval(3600))
        if let opened = lastOpenedAt {
            fireDate = max(fireDate, opened.addingTimeInterval(Self.minimumGapAfterOpen))
        }
        return Decision(
            kind: .unfinishedProject,
            identifier: Self.unfinishedIdentifier,
            title: String(localized: "Your collage is waiting"),
            body: String(localized: "Pick up “\(project.name)” where you left off."),
            fireDate: fireDate,
            deepLink: DeepLink.project(project.id).url)
    }

    private func seasonalDecision(
        _ drop: SeasonalDrop, now: Date, calendar: Calendar
    ) -> Decision? {
        guard drop.windowStart > now,
              drop.windowStart.timeIntervalSince(now) <= Self.seasonalHorizon else { return nil }
        var components = calendar.dateComponents([.year, .month, .day], from: drop.windowStart)
        components.hour = Self.seasonalHour
        guard let fireDate = calendar.date(from: components), fireDate > now else { return nil }
        return Decision(
            kind: .seasonalDrop,
            identifier: Self.seasonalIdentifier(
                drop.collectionID, year: calendar.component(.year, from: drop.windowStart)),
            title: String(localized: "New for \(drop.title)"),
            body: String(localized: "Fresh templates just landed on Home."),
            fireDate: fireDate,
            deepLink: DeepLink.collection(drop.collectionID).url)
    }

    /// The caps, against everything booked other than this identifier.
    private func fits(_ decision: Decision, among booked: [String: Date]) -> Bool {
        let others = booked.filter { $0.key != decision.identifier }.map(\.value)
        let withinWeek = others.filter { abs($0.timeIntervalSince(decision.fireDate)) < Self.week }
        guard withinWeek.count < Self.maxPerWeek else { return false }
        let withinMonth = others.filter { abs($0.timeIntervalSince(decision.fireDate)) < Self.month }
        return withinMonth.count < Self.maxPerMonth
    }
}
