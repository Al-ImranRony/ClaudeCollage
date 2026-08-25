//
//  TrialReminderScheduler.swift
//  Caroullage
//
//  Step 06 phase 6.3 — telling the user before the money moves.
//
//  A day before a free trial converts, the app says what is about to be charged
//  and that cancelling avoids it. That is the opposite of the pattern App Review
//  penalises, and it is also the reason people trust a trial enough to start one.
//
//  `UNUserNotificationCenter` cannot be driven from a headless test, so it sits
//  behind `TrialNotificationScheduling` — the same seam used for StoreKit and
//  Vision — and the timing and wording are tested against a stub.
//

import Foundation
import UserNotifications

/// One scheduled reminder.
public struct TrialReminderRequest: Equatable, Sendable {
    public let identifier: String
    public let title: String
    public let body: String
    public let fireDate: Date
}

@MainActor
public protocol TrialNotificationScheduling {
    /// Returns whether the app may post notifications.
    func requestAuthorization() async -> Bool
    func schedule(_ request: TrialReminderRequest) async
    func cancel(identifier: String) async
}

@MainActor
public final class TrialReminderScheduler {

    /// One identifier, so re-scheduling replaces rather than stacks.
    public static let identifier = "caroullage.trial.ending"

    private let notifications: any TrialNotificationScheduling

    public init(notifications: any TrialNotificationScheduling = SystemTrialNotificationScheduler()) {
        self.notifications = notifications
    }

    /// Schedules the warning for a trial that has just started.
    public func scheduleReminder(
        trialDays: Int?, price: String, period: String, from start: Date = Date()
    ) async {
        guard let trialDays, trialDays > 0 else { return }
        guard await notifications.requestAuthorization() else { return }

        let trialLength = TimeInterval(trialDays) * 24 * 3600
        // A day's warning where there is a day to give; otherwise three quarters
        // of the way through, which still lands before the charge.
        let lead = trialDays >= 2 ? 24 * 3600 : trialLength * 0.25
        let fireDate = start.addingTimeInterval(trialLength - lead)

        let whenText = trialDays >= 2 ? "tomorrow" : "soon"
        await notifications.schedule(TrialReminderRequest(
            identifier: Self.identifier,
            title: "Your free trial ends \(whenText)",
            body: "You'll be charged \(price) per \(period) unless you cancel in Settings before then.",
            fireDate: fireDate
        ))
    }

    /// Removes the reminder once it is no longer true — the user cancelled, the
    /// subscription lapsed, or they bought outright.
    public func cancelReminder() async {
        await notifications.cancel(identifier: Self.identifier)
    }
}

/// The real thing. Asks provisionally: a trial reminder is exactly the quiet,
/// expected notification that provisional authorization exists for, and it means
/// no permission prompt lands on the user seconds after they paid.
@MainActor
public struct SystemTrialNotificationScheduler: TrialNotificationScheduling {

    public init() {}

    public func requestAuthorization() async -> Bool {
        let centre = UNUserNotificationCenter.current()
        let settings = await centre.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await centre.requestAuthorization(options: [.alert, .sound, .provisional])) ?? false
        @unknown default:
            return false
        }
    }

    public func schedule(_ request: TrialReminderRequest) async {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default

        let interval = max(1, request.fireDate.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let notification = UNNotificationRequest(
            identifier: request.identifier, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(notification)
    }

    public func cancel(identifier: String) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
