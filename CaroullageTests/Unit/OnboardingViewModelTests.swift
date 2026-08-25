//
//  OnboardingViewModelTests.swift
//  CaroullageTests
//
//  Step 06 phase 6.3 — the first-launch funnel.
//
//  The funnel's job is to reach the paywall with the user still interested, and
//  its rules are the kind that break silently: shown once and only once, Skip
//  jumps to the end rather than abandoning the run, a declined photo prompt does
//  not strand anyone, and closing the paywall leaves a working free app.
//

import XCTest
@testable import Caroullage

@MainActor
final class OnboardingViewModelTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "OnboardingViewModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    private func makeModel(tracker: SpyFunnelTracker = SpyFunnelTracker()) -> OnboardingViewModel {
        OnboardingViewModel(defaults: defaults, tracker: tracker)
    }

    // MARK: - When it runs

    func testOnboardingRunsOnAFirstLaunch() {
        XCTAssertTrue(OnboardingViewModel.shouldPresent(defaults: defaults))
    }

    func testOnboardingDoesNotRunAgainOnceFinished() {
        let model = makeModel()
        model.finish()

        XCTAssertFalse(OnboardingViewModel.shouldPresent(defaults: defaults))
    }

    func testSkippingStillCountsAsSeen() {
        let model = makeModel()
        model.skip()
        model.finish()

        XCTAssertFalse(OnboardingViewModel.shouldPresent(defaults: defaults),
                       "a user who skipped has seen it; showing it again would be a bug they cannot escape")
    }

    // MARK: - The sequence

    func testTheFunnelOpensOnWelcome() {
        XCTAssertEqual(makeModel().step, .welcome)
    }

    func testTheStepsRunInTheOrderTheBriefSpecifies() {
        XCTAssertEqual(
            OnboardingStep.allCases,
            [.welcome, .grid, .carousel, .video, .personalization, .photoPriming, .preview, .paywall]
        )
    }

    func testAdvancingWalksTheWholeFunnel() {
        let model = makeModel()

        for expected in OnboardingStep.allCases.dropFirst() {
            model.advance()
            XCTAssertEqual(model.step, expected)
        }
    }

    func testAdvancingPastTheEndStaysAtTheEnd() {
        let model = makeModel()
        for _ in 0..<20 { model.advance() }

        XCTAssertEqual(model.step, .paywall)
    }

    func testSkipJumpsStraightToThePaywall() {
        let model = makeModel()

        model.skip()

        XCTAssertEqual(model.step, .paywall, "Skip is for the slides, not for the offer")
    }

    func testSkipIsOfferedOnTheValueSlidesOnly() {
        XCTAssertTrue(OnboardingStep.welcome.showsSkip)
        XCTAssertTrue(OnboardingStep.grid.showsSkip)
        XCTAssertTrue(OnboardingStep.carousel.showsSkip)
        XCTAssertTrue(OnboardingStep.video.showsSkip)
        XCTAssertFalse(OnboardingStep.personalization.showsSkip)
        XCTAssertFalse(OnboardingStep.paywall.showsSkip)
    }

    // MARK: - Personalization

    func testTheAnswerIsRememberedForTheFirstTemplateSuggestion() {
        let model = makeModel()

        model.choose(.reels)

        XCTAssertEqual(model.creatorKind, .reels)
        XCTAssertEqual(OnboardingViewModel.storedCreatorKind(defaults: defaults), .reels)
    }

    func testAnsweringMovesTheFunnelOn() {
        let model = makeModel()
        model.advance(); model.advance(); model.advance(); model.advance()
        XCTAssertEqual(model.step, .personalization)

        model.choose(.carousels)

        XCTAssertEqual(model.step, .photoPriming)
    }

    func testTheQuestionCanBePassedWithoutAnAnswer() {
        let model = makeModel()
        model.advance(); model.advance(); model.advance(); model.advance()

        model.advance()

        XCTAssertEqual(model.step, .photoPriming)
        XCTAssertNil(model.creatorKind, "an unanswered question is not an answer")
    }

    // MARK: - Photos

    func testGrantingPhotoAccessMovesOnToThePreview() async {
        let model = makeModel()
        model.goTo(.photoPriming)

        await model.requestPhotos { .authorized }

        XCTAssertEqual(model.step, .preview)
    }

    func testDecliningPhotoAccessSkipsThePreviewRatherThanStranding() async {
        let model = makeModel()
        model.goTo(.photoPriming)

        await model.requestPhotos { .denied }

        XCTAssertEqual(model.step, .paywall, "there is nothing to preview, so go straight to the offer")
    }

    // MARK: - Analytics

    func testEveryStepReachedIsLogged() {
        let tracker = SpyFunnelTracker()
        let model = makeModel(tracker: tracker)

        model.advance()
        model.advance()

        XCTAssertEqual(tracker.steps, [.grid, .carousel])
    }

    func testSkippingIsLoggedWithTheStepItWasSkippedFrom() {
        let tracker = SpyFunnelTracker()
        let model = makeModel(tracker: tracker)
        model.advance()

        model.skip()

        XCTAssertEqual(tracker.skippedFrom, .grid, "where people bail is the number worth having")
    }

    func testCompletionIsLogged() {
        let tracker = SpyFunnelTracker()
        let model = makeModel(tracker: tracker)

        model.finish()

        XCTAssertTrue(tracker.didFinish)
    }
}

/// Records what the funnel reported, standing in for the analytics backend that
/// is not wired up yet.
private final class SpyFunnelTracker: OnboardingFunnelTracking {
    var steps: [OnboardingStep] = []
    var skippedFrom: OnboardingStep?
    var didFinish = false

    func reached(_ step: OnboardingStep) { steps.append(step) }
    func skipped(from step: OnboardingStep) { skippedFrom = step }
    func finished() { didFinish = true }
}
