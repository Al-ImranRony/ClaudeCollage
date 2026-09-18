//
//  EngagementReminderScheduler.swift
//  Caroullage
//
//  Home retention, phase 3 — books what `EngagementReminderPolicy` decided.
//
//  The same seam the trial reminder uses (`LocalNotificationScheduling`), so
//  the notification centre is still touched from exactly one place and the
//  timing here is tested against a spy. Called by the coordinator when the app
//  goes to the background (book) and comes back (note the open, drop the
//  unfinished nudge — they are here, so it is moot).
//

import Foundation

@MainActor
public final class EngagementReminderScheduler {

    private let notifications: any LocalNotificationScheduling
    private let policy: EngagementReminderPolicy

    public init(
        notifications: any LocalNotificationScheduling = SystemTrialNotificationScheduler(),
        policy: EngagementReminderPolicy = EngagementReminderPolicy()
    ) {
        self.notifications = notifications
        self.policy = policy
    }

    public var isEnabled: Bool { policy.isEnabled }

    /// The Settings toggle. Turning reminders on asks the system if it has
    /// not been asked; a refusal leaves the toggle off and reports it, so the
    /// screen can point at the Settings app rather than pretend.
    @discardableResult
    public func setEnabled(_ enabled: Bool) async -> Bool {
        if enabled {
            // Full, not provisional: the user asked for these in Settings and
            // expects to see them.
            let granted = await notifications.requestFullAuthorization()
            policy.isEnabled = granted
            return granted
        }
        policy.isEnabled = false
        await cancelAll()
        return false
    }

    /// Whether the system would deliver anything, whatever the toggle says.
    public func authorization() async -> LocalNotificationAuthorization {
        await notifications.authorization()
    }

    /// Books the policy's decisions and clears anything it no longer wants.
    public func refresh(
        now: Date = Date(),
        installedAt: Date,
        unfinished: EngagementReminderPolicy.UnfinishedProject?,
        seasonal: EngagementReminderPolicy.SeasonalDrop?
    ) async {
        let decisions = policy.decisions(
            now: now, installedAt: installedAt, unfinished: unfinished, seasonal: seasonal)

        // The unfinished nudge is about the CURRENT state of the library: if
        // the policy no longer wants one (exported, too old, cap hit), an
        // earlier booking must not fire.
        if !decisions.contains(where: { $0.kind == .unfinishedProject }) {
            await notifications.cancel(identifier: EngagementReminderPolicy.unfinishedIdentifier)
            policy.recordCancelled(identifier: EngagementReminderPolicy.unfinishedIdentifier)
        }

        for decision in decisions {
            await notifications.schedule(TrialReminderRequest(
                identifier: decision.identifier,
                title: decision.title,
                body: decision.body,
                fireDate: decision.fireDate,
                deepLink: decision.deepLink))
            policy.recordScheduled(decision)
            Analytics.track(.reminderScheduled(kind: decision.kind.rawValue))
        }
    }

    /// The user is here. The unfinished nudge would only annoy them now.
    public func noteOpened(now: Date = Date()) async {
        policy.recordOpened(now: now)
        await notifications.cancel(identifier: EngagementReminderPolicy.unfinishedIdentifier)
        policy.recordCancelled(identifier: EngagementReminderPolicy.unfinishedIdentifier)
    }

    public func cancelAll() async {
        for identifier in policy.scheduled.keys {
            await notifications.cancel(identifier: identifier)
            policy.recordCancelled(identifier: identifier)
        }
        await notifications.cancel(identifier: EngagementReminderPolicy.unfinishedIdentifier)
    }
}
