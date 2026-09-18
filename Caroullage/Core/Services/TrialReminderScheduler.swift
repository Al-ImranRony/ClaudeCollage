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
    /// Where a tap on the notification lands (Home retention, phase 3). Stored
    /// in the request's `userInfo` and routed by `AppDelegate` through
    /// `DeepLink`, so the notification centre never learns navigation.
    public let deepLink: URL?

    public init(identifier: String, title: String, body: String, fireDate: Date, deepLink: URL? = nil) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.fireDate = fireDate
        self.deepLink = deepLink
    }
}

/// What the system will do with a notification, as the Settings toggle
/// needs to know it.
public enum LocalNotificationAuthorization: Equatable, Sendable {
    case notDetermined, authorized, denied
}

/// The seam in front of `UNUserNotificationCenter`. It began as the trial
/// reminder's; the engagement reminders (phase 3) book through the same
/// one, so the centre is still touched from exactly one type.
@MainActor
public protocol LocalNotificationScheduling {
    /// Returns whether the app may post notifications.
    func requestAuthorization() async -> Bool
    func authorization() async -> LocalNotificationAuthorization
    func schedule(_ request: TrialReminderRequest) async
    func cancel(identifier: String) async
    func pendingIdentifiers() async -> [String]
}

public extension LocalNotificationScheduling {
    // Defaults so the trial reminder's existing spy keeps compiling; the
    // engagement tests use a spy of their own that records everything.
    func authorization() async -> LocalNotificationAuthorization { .authorized }
    func pendingIdentifiers() async -> [String] { [] }
}

/// The name the trial reminder used before the seam was shared.
public typealias TrialNotificationScheduling = LocalNotificationScheduling

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

        // Whole sentences per case rather than an assembled "per \(period)":
        // assembling breaks the grammar in Japanese, Korean and Arabic.
        let title = trialDays >= 2
            ? String(localized: "Your free trial ends tomorrow")
            : String(localized: "Your free trial ends soon")
        let body: String
        switch period {
        case "month": body = String(localized: "You'll be charged \(price) per month unless you cancel in Settings before then.")
        case "week": body = String(localized: "You'll be charged \(price) per week unless you cancel in Settings before then.")
        case "once": body = String(localized: "You'll be charged \(price) unless you cancel in Settings before then.")
        default: body = String(localized: "You'll be charged \(price) per year unless you cancel in Settings before then.")
        }
        await notifications.schedule(TrialReminderRequest(
            identifier: Self.identifier,
            title: title,
            body: body,
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
public struct SystemTrialNotificationScheduler: LocalNotificationScheduling {

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

    public func authorization() async -> LocalNotificationAuthorization {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .authorized
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    public func pendingIdentifiers() async -> [String] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
    }

    public func schedule(_ request: TrialReminderRequest) async {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        if let deepLink = request.deepLink {
            content.userInfo = [AppDelegate.deepLinkUserInfoKey: deepLink.absoluteString]
        }

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
