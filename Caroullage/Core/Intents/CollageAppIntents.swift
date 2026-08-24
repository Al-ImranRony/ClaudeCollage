//
//  CollageAppIntents.swift
//  Caroullage
//
//  Step 05 batch C — Siri, Shortcuts, Spotlight and the Action Button.
//
//  Three intents, per the brief. Each one only *requests* work and hands off to
//  the app: an intent that tried to build a collage headlessly would duplicate
//  the coordinator's routing and drift from it. They post through
//  `IntentRouter`, which the coordinator observes, so the app stays the single
//  place that knows how to open an editor.
//
//  `openAppWhenRun` is true on all three because every one of them ends with the
//  user editing something. An intent that silently created a project they could
//  not see would be worse than useless.
//

import AppIntents
import Foundation

// MARK: - Router

/// The seam between an intent and the app's navigation.
///
/// Intents run in the app's process here, but they have no reference to the
/// coordinator, and giving them one would put routing knowledge in two places.
@MainActor
public final class IntentRouter {

    public static let shared = IntentRouter()

    public enum Request: Equatable, Sendable {
        case newGridCollage(photoCount: Int)
        case newStoryCarousel(frameCount: Int)
        case exportLastProject
    }

    /// Set by the coordinator. Requests that arrive before the app is ready are
    /// held and replayed, so an intent fired from a cold launch is not dropped.
    public var onRequest: ((Request) -> Void)? {
        didSet {
            guard onRequest != nil, !pending.isEmpty else { return }
            let queued = pending
            pending.removeAll()
            queued.forEach { onRequest?($0) }
        }
    }

    private var pending: [Request] = []

    private init() {}

    public func send(_ request: Request) {
        guard let onRequest else {
            pending.append(request)
            return
        }
        onRequest(request)
    }
}

// MARK: - Intents

/// "Make a collage from my last 9 photos."
public struct CreateCollageFromRecentPhotos: AppIntent {

    public static let title: LocalizedStringResource = "Create Collage from Recent Photos"
    public static let description = IntentDescription(
        "Starts a new grid collage using your most recent photos.")
    public static let openAppWhenRun: Bool = true

    @Parameter(title: "Number of Photos", default: 9, inclusiveRange: (1, 9))
    public var count: Int

    public init() {}
    public init(count: Int) { self.count = count }

    @MainActor
    public func perform() async throws -> some IntentResult {
        IntentRouter.shared.send(.newGridCollage(photoCount: count))
        return .result()
    }
}

/// "Start a story carousel."
public struct CreateStoryCarousel: AppIntent {

    public static let title: LocalizedStringResource = "Create Story Carousel"
    public static let description = IntentDescription(
        "Opens the carousel editor with a matched multi-frame layout ready to fill.")
    public static let openAppWhenRun: Bool = true

    @Parameter(title: "Number of Frames", default: 3, inclusiveRange: (2, 10))
    public var frameCount: Int

    public init() {}
    public init(frameCount: Int) { self.frameCount = frameCount }

    @MainActor
    public func perform() async throws -> some IntentResult {
        IntentRouter.shared.send(.newStoryCarousel(frameCount: frameCount))
        return .result()
    }
}

/// "Export my last collage again."
public struct ExportLastProject: AppIntent {

    public static let title: LocalizedStringResource = "Export Last Project"
    public static let description = IntentDescription(
        "Opens your most recent project and its export options.")
    public static let openAppWhenRun: Bool = true

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        IntentRouter.shared.send(.exportLastProject)
        return .result()
    }
}

// MARK: - Shortcuts

/// Registers all three so they appear in Spotlight, Shortcuts and Siri
/// Suggestions without the user configuring anything.
public struct CollageShortcuts: AppShortcutsProvider {

    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateCollageFromRecentPhotos(),
            phrases: [
                "Create a collage in \(.applicationName)",
                "Make a photo collage with \(.applicationName)",
            ],
            shortTitle: "New Collage",
            systemImageName: "square.grid.2x2.fill"
        )
        AppShortcut(
            intent: CreateStoryCarousel(),
            phrases: [
                "Create a carousel in \(.applicationName)",
                "Start a story carousel with \(.applicationName)",
            ],
            shortTitle: "New Carousel",
            systemImageName: "rectangle.stack.fill"
        )
        AppShortcut(
            intent: ExportLastProject(),
            phrases: [
                "Export my last collage in \(.applicationName)",
                "Share my latest \(.applicationName) project",
            ],
            shortTitle: "Export Last",
            systemImageName: "square.and.arrow.up"
        )
    }
}
