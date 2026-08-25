//
//  OnboardingViewModel.swift
//  Caroullage
//
//  Step 06 phase 6.3 — the first-launch funnel: show what the app does, ask one
//  question, ask for photos, show the user their own pictures in a template,
//  then make the offer.
//
//  The state lives here rather than in the pager so the rules that matter can be
//  tested: it runs once, Skip goes to the offer rather than out of the app, a
//  declined photo prompt skips the preview instead of stranding the user on a
//  screen with nothing to show, and closing the paywall leaves a working free
//  app rather than a relaunch.
//

import Combine
import CoreGraphics
import Foundation

/// The eight beats of the funnel, in order.
public enum OnboardingStep: String, CaseIterable, Sendable, Equatable {
    case welcome
    case grid
    case carousel
    case video
    case personalization
    case photoPriming
    case preview
    case paywall

    /// Skip belongs on the value slides. Past them the user is answering or
    /// being asked for something, where a stray "Skip" reads as "get me out".
    public var showsSkip: Bool {
        switch self {
        case .welcome, .grid, .carousel, .video: return true
        case .personalization, .photoPriming, .preview, .paywall: return false
        }
    }
}

/// What the user says they make. Used to pick the first template they see.
public enum CreatorKind: String, CaseIterable, Sendable, Equatable {
    case carousels
    case reels
    case pinterest
    case fun

    public var title: String {
        switch self {
        case .carousels: return "Instagram Carousels"
        case .reels: return "TikTok / Reels"
        case .pinterest: return "Pinterest Boards"
        case .fun: return "Just for fun"
        }
    }

    public var symbol: String {
        switch self {
        case .carousels: return "rectangle.stack.fill"
        case .reels: return "play.rectangle.fill"
        case .pinterest: return "square.grid.2x2.fill"
        case .fun: return "sparkles"
        }
    }
}

/// Where the funnel reports to. The brief names TelemetryDeck; no analytics SDK
/// is in the project yet, so this is the seam it will plug into and the console
/// implementation below is what runs until then.
@MainActor
public protocol OnboardingFunnelTracking {
    func reached(_ step: OnboardingStep)
    func skipped(from step: OnboardingStep)
    func finished()
}

@MainActor
public final class OnboardingViewModel: ObservableObject {

    @Published public private(set) var step: OnboardingStep = .welcome
    @Published public private(set) var creatorKind: CreatorKind?
    /// The user's own recent photos, shown in a template on the preview beat.
    @Published public private(set) var previewPhotos: [CGImage] = []

    private let defaults: UserDefaults
    private let tracker: any OnboardingFunnelTracking

    private enum Key {
        static let seen = "hasSeenOnboarding"
        static let creatorKind = "onboarding.creatorKind"
    }

    public init(
        defaults: UserDefaults = .standard,
        tracker: any OnboardingFunnelTracking = ConsoleFunnelTracker()
    ) {
        self.defaults = defaults
        self.tracker = tracker
        self.creatorKind = Self.storedCreatorKind(defaults: defaults)
    }

    // MARK: - Whether to run at all

    public static func shouldPresent(defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: Key.seen)
    }

    /// What the user said they make, for the first-template suggestion.
    public static func storedCreatorKind(defaults: UserDefaults = .standard) -> CreatorKind? {
        defaults.string(forKey: Key.creatorKind).flatMap(CreatorKind.init(rawValue:))
    }

    // MARK: - Moving through it

    public func advance() {
        guard let index = OnboardingStep.allCases.firstIndex(of: step),
              index + 1 < OnboardingStep.allCases.count
        else { return }
        goTo(OnboardingStep.allCases[index + 1])
    }

    public func goTo(_ next: OnboardingStep) {
        guard next != step else { return }
        step = next
        tracker.reached(next)
    }

    /// Leaves the slides for the offer. Not an exit: the funnel still ends where
    /// it was always going to end.
    public func skip() {
        tracker.skipped(from: step)
        goTo(.paywall)
    }

    public func choose(_ kind: CreatorKind) {
        creatorKind = kind
        defaults.set(kind.rawValue, forKey: Key.creatorKind)
        advance()
    }

    /// Asks for photo access at the moment the user has been told why.
    /// `request` is the provider's own prompt, injected so the decision logic is
    /// testable without PhotoKit.
    public func requestPhotos(_ request: () async -> RecentPhotoProvider.Access) async {
        let access = await request()
        // Denied is final — iOS will not show the dialog twice — so there is
        // nothing to preview and no reason to hold the user on the way to it.
        goTo(access == .authorized ? .preview : .paywall)
    }

    public func setPreviewPhotos(_ photos: [CGImage]) {
        previewPhotos = photos
    }

    /// Marks the funnel done. Called however it ends — bought, closed, or
    /// skipped — because a user who has seen it must never see it again.
    public func finish() {
        defaults.set(true, forKey: Key.seen)
        tracker.finished()
    }
}

/// Until an analytics SDK is chosen, funnel events go to the console. The point
/// of the type is that the call sites already exist when it is.
@MainActor
public struct ConsoleFunnelTracker: OnboardingFunnelTracking {
    public init() {}
    public func reached(_ step: OnboardingStep) { log("reached \(step.rawValue)") }
    public func skipped(from step: OnboardingStep) { log("skipped from \(step.rawValue)") }
    public func finished() { log("finished") }

    private func log(_ message: String) {
        #if DEBUG
        print("[onboarding] \(message)")
        #endif
    }
}
