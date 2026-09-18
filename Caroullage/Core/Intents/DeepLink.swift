//
//  DeepLink.swift
//  Caroullage
//
//  Home retention, phase 1 — the doors into the app from outside it.
//
//  The Recent Collages widget had been emitting `caroullage://project/<id>`
//  and the export Live Activity `caroullage://export` since Step 05, and
//  Spotlight had indexed every project — and none of it went anywhere: the
//  scheme was not registered, and the scene delegate answered no URL and no
//  user activity. A tap on any of them cold-launched to Home.
//
//  This is the one parser all of those share. It produces an `IntentRouter`
//  request rather than touching navigation, so a deep link, a Siri intent and
//  a notification tap all arrive at the coordinator through the same queue —
//  which already holds requests that land before the app is ready.
//

import CoreSpotlight
import Foundation

public enum DeepLink: Equatable, Sendable {
    case project(UUID)
    case exportLast
    case collection(String)
    case template(String)
    case carouselTemplate(String)
    case settings

    public static let scheme = "caroullage"

    // MARK: - Parsing

    /// `caroullage://project/<uuid>`, `caroullage://export`,
    /// `caroullage://collection/<id>`, `caroullage://template/<id>`,
    /// `caroullage://carousel/<id>`, `caroullage://settings`.
    ///
    /// The host is the verb and the first path segment is the argument. A
    /// scheme-only form with the verb as the first path segment
    /// (`caroullage:///project/…`) is accepted too, because that is what some
    /// URL builders produce.
    public static func parse(_ url: URL) -> DeepLink? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        var parts: [String] = []
        if let host = url.host, !host.isEmpty { parts.append(host) }
        parts += url.pathComponents.filter { $0 != "/" }
        guard let verb = parts.first?.lowercased() else { return nil }
        let argument = parts.dropFirst().first

        switch verb {
        case "project":
            guard let argument, let id = UUID(uuidString: argument) else { return nil }
            return .project(id)
        case "export":
            return .exportLast
        case "collection":
            guard let argument, !argument.isEmpty else { return nil }
            return .collection(argument)
        case "template":
            guard let argument, !argument.isEmpty else { return nil }
            return .template(argument)
        case "carousel":
            guard let argument, !argument.isEmpty else { return nil }
            return .carouselTemplate(argument)
        case "settings":
            return .settings
        default:
            return nil
        }
    }

    /// A Spotlight result, or a web/URL activity carrying one of our URLs.
    public static func parse(_ activity: NSUserActivity) -> DeepLink? {
        if activity.activityType == CSSearchableItemActionType,
           let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
           let id = SpotlightIndexer.projectID(fromIdentifier: identifier) {
            return .project(id)
        }
        if let url = activity.webpageURL ?? (activity.userInfo?["url"] as? URL) {
            return parse(url)
        }
        return nil
    }

    // MARK: - Round trip

    /// The canonical URL, so a widget, a notification and a test all build the
    /// same string.
    public var url: URL {
        let path: String
        switch self {
        case let .project(id): path = "project/\(id.uuidString)"
        case .exportLast: path = "export"
        case let .collection(id): path = "collection/\(id)"
        case let .template(id): path = "template/\(id)"
        case let .carouselTemplate(id): path = "carousel/\(id)"
        case .settings: path = "settings"
        }
        // Force-unwrapped only after the path has been percent-encoded, so an
        // authored id with a space cannot produce nil.
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return URL(string: "\(Self.scheme)://\(encoded)")!
    }

    /// What the coordinator runs.
    @MainActor
    public var request: IntentRouter.Request {
        switch self {
        case let .project(id): return .openProject(id)
        case .exportLast: return .exportLastProject
        case let .collection(id): return .openCollection(id)
        case let .template(id): return .openTemplate(id)
        case let .carouselTemplate(id): return .openCarouselTemplate(id)
        case .settings: return .openSettings
        }
    }

    /// The analytics dimension: which kind of door was used.
    public var analyticsKind: String {
        switch self {
        case .project: return "project"
        case .exportLast: return "export"
        case .collection: return "collection"
        case .template: return "template"
        case .carouselTemplate: return "carousel"
        case .settings: return "settings"
        }
    }
}
