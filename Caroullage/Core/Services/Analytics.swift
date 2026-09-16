//
//  Analytics.swift
//  Caroullage
//
//  Home retention, phase 1 — the event seam.
//
//  Nothing on Home could be measured: the only tracker in the app was the
//  onboarding funnel's, and it prints. This is the same shape widened to the
//  whole app — a protocol, a console implementation, and one static entry
//  point — so every touchpoint the retention work adds already reports
//  somewhere when an SDK (the brief names TelemetryDeck) is chosen. Until then
//  it costs a `print` in DEBUG and nothing in release.
//
//  Deliberately no SDK: `PrivacyInfo.xcprivacy` declares no tracking, and
//  `PrivacyManifestTests` pins that. Wiring a vendor here is a manifest change
//  first and a code change second.
//

import Foundation

/// One thing the user did, named the way a dashboard would name it.
public enum AnalyticsEvent: Equatable, Sendable {
    case homeSectionShown(id: String)
    case collectionSeeAll(id: String)
    case templateOpened(id: String, source: String)
    case heroTapped(id: String)
    case recentResumed
    case suggestionOpened(template: String)
    case favouriteToggled(id: String, saved: Bool)
    case settingsOpened
    case restore(result: String)
    case reminderScheduled(kind: String)
    case reminderOpened(kind: String)
    case deepLinkOpened(kind: String)

    /// The wire name: snake_case, stable, never derived from the case name so a
    /// Swift rename can never silently fork a dashboard series.
    public var name: String {
        switch self {
        case .homeSectionShown: return "home_section_shown"
        case .collectionSeeAll: return "collection_see_all"
        case .templateOpened: return "template_opened"
        case .heroTapped: return "hero_tapped"
        case .recentResumed: return "recent_resumed"
        case .suggestionOpened: return "suggestion_opened"
        case .favouriteToggled: return "favourite_toggled"
        case .settingsOpened: return "settings_opened"
        case .restore: return "restore"
        case .reminderScheduled: return "reminder_scheduled"
        case .reminderOpened: return "reminder_opened"
        case .deepLinkOpened: return "deep_link_opened"
        }
    }

    /// Everything a vendor would want beside the name. Strings only, so no
    /// implementation has to negotiate types.
    public var parameters: [String: String] {
        switch self {
        case let .homeSectionShown(id), let .collectionSeeAll(id), let .heroTapped(id):
            return ["id": id]
        case let .templateOpened(id, source):
            return ["id": id, "source": source]
        case .recentResumed, .settingsOpened:
            return [:]
        case let .suggestionOpened(template):
            return ["template": template]
        case let .favouriteToggled(id, saved):
            return ["id": id, "saved": saved ? "true" : "false"]
        case let .restore(result):
            return ["result": result]
        case let .reminderScheduled(kind), let .reminderOpened(kind), let .deepLinkOpened(kind):
            return ["kind": kind]
        }
    }
}

/// Where events go. Implemented by the console today and by a vendor later;
/// tests install a spy.
@MainActor
public protocol AnalyticsTracking {
    func track(_ event: AnalyticsEvent)
}

/// The DEBUG console, same as `ConsoleFunnelTracker`.
@MainActor
public struct ConsoleAnalytics: AnalyticsTracking {
    public init() {}

    public func track(_ event: AnalyticsEvent) {
        #if DEBUG
        let params = event.parameters.isEmpty
            ? ""
            : " " + event.parameters.sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        print("[analytics] \(event.name)\(params)")
        #endif
    }
}

/// The app's single entry point. Swappable so tests can observe what a screen
/// reports without a vendor in the loop.
@MainActor
public enum Analytics {
    public static var tracker: any AnalyticsTracking = ConsoleAnalytics()

    public static func track(_ event: AnalyticsEvent) {
        tracker.track(event)
    }
}
