//
//  OnboardingView.swift
//  Caroullage
//
//  Step 06 phase 6.3 — first launch.
//
//  A pager the user can swipe, with the slides drawn rather than shipped: the
//  demos are the app's own shapes animating, so the funnel adds nothing to the
//  bundle and cannot go stale against a redesign.
//
//  Skip sits top-right on the value slides only. Past them the user is being
//  asked for something, and an escape hatch beside a permission prompt reads as
//  a warning rather than a courtesy.
//

import SwiftUI

struct OnboardingView: View {

    @ObservedObject var model: OnboardingViewModel

    /// Runs when the funnel reaches its end — the host presents the paywall.
    var onReachedPaywall: () -> Void
    /// Asks for photo-library access and reports what the user chose.
    var requestPhotoAccess: () async -> RecentPhotoProvider.Access

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.themeBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                slide
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .id(model.step)

                pageDots
                    .padding(.bottom, Theme.Spacing.sm)

                primaryButton
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.bottom, Theme.Spacing.xl)
            }

            if model.step.showsSkip {
                Button("Skip") {
                    Haptics.tap()
                    model.skip()
                }
                .font(.themeSubheadline)
                .foregroundStyle(Color.themeTextSecondary)
                .padding(Theme.Spacing.lg)
                .accessibilityIdentifier("onboardingSkipButton")
            }
        }
        .animation(.easeInOut(duration: Theme.Motion.duration(Theme.Motion.standard)), value: model.step)
        .onChange(of: model.step) { _, step in
            if step == .paywall { onReachedPaywall() }
        }
    }

    // MARK: - Slides

    @ViewBuilder
    private var slide: some View {
        switch model.step {
        case .welcome:
            valueSlide(
                symbol: "square.stack.3d.up.fill",
                title: "Welcome to Caroullage",
                body: "Collages, carousels and video — made on your phone, in a couple of minutes."
            )
        case .grid:
            valueSlide(
                symbol: "square.grid.3x3.fill",
                title: "Layouts that fit",
                body: "Drop photos into a grid or a shape and it arranges itself around them."
            )
        case .carousel:
            valueSlide(
                symbol: "rectangle.stack.fill",
                title: "Carousels that swipe",
                body: "One picture cut across several posts, lined up so it flows as people swipe."
            )
        case .video:
            valueSlide(
                symbol: "wand.and.stars",
                title: "Video, and the fiddly bits",
                body: "Mix clips and photos, cut to the beat, and lift a subject out of its background."
            )
        case .personalization:
            personalizationSlide
        case .photoPriming:
            photoPrimingSlide
        case .preview:
            previewSlide
        case .paywall:
            // The paywall is presented over this by the host; leaving the last
            // slide up avoids a flash of empty background behind it.
            previewSlide
        }
    }

    private func valueSlide(symbol: String, title: String, body: String) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [.themeAccent, .themeAccentStrong],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 168, height: 168)
                Image(systemName: symbol)
                    .font(.system(size: 68, weight: .semibold))
                    .foregroundStyle(Color.themeTextOnAccent)
            }
            Text(LocalizedStringKey(title))
                .font(.themeLargeTitle)
                .foregroundStyle(Color.themeTextPrimary)
                .multilineTextAlignment(.center)
            Text(LocalizedStringKey(body))
                .font(.themeBody)
                .foregroundStyle(Color.themeTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.xxl)
    }

    private var personalizationSlide: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer(minLength: 0)
            Text("What do you make most?")
                .font(.themeTitle)
                .foregroundStyle(Color.themeTextPrimary)
                .multilineTextAlignment(.center)
            Text("So the first thing you see is something you'd actually use.")
                .font(.themeSubheadline)
                .foregroundStyle(Color.themeTextSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: Theme.Spacing.xs) {
                ForEach(CreatorKind.allCases, id: \.rawValue) { kind in
                    Button {
                        Haptics.selectionChanged()
                        model.choose(kind)
                    } label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: kind.symbol)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.themeAccentStrong)
                                .frame(width: 28)
                            Text(kind.title)
                                .font(.themeHeadline)
                                .foregroundStyle(Color.themeTextPrimary)
                            Spacer(minLength: 0)
                        }
                        .padding(Theme.Spacing.md)
                        .background(Color.themeSurface,
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("onboardingChoice.\(kind.rawValue)")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.xl)
    }

    private var photoPrimingSlide: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer(minLength: 0)
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(Color.themeAccentStrong)
            Text("Let's use your photos")
                .font(.themeTitle)
                .foregroundStyle(Color.themeTextPrimary)
            Text("Caroullage reads your recent photos to show you a collage of your own instead of a stock one. Nothing leaves your phone.")
                .font(.themeBody)
                .foregroundStyle(Color.themeTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.xxl)
    }

    private var previewSlide: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer(minLength: 0)
            Text("Here's yours")
                .font(.themeTitle)
                .foregroundStyle(Color.themeTextPrimary)

            if model.previewPhotos.isEmpty {
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .fill(Color.themeSurface)
                    .frame(height: 260)
                    .overlay(ProgressView().tint(Color.themeAccentStrong))
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    ForEach(Array(model.previewPhotos.prefix(4).enumerated()), id: \.offset) { _, image in
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .aspectRatio(1, contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    }
                }
                .frame(maxHeight: 320)
            }

            Text("Three taps from here to a finished carousel.")
                .font(.themeSubheadline)
                .foregroundStyle(Color.themeTextSecondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.xl)
    }

    // MARK: - Chrome

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases.dropLast(), id: \.rawValue) { step in
                Capsule()
                    .fill(step == model.step ? Color.themeAccentStrong : Color.themeSeparator)
                    .frame(width: step == model.step ? 18 : 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var primaryButton: some View {
        if model.step != .personalization {
            Button {
                Haptics.tap()
                switch model.step {
                case .photoPriming:
                    Task { await model.requestPhotos(requestPhotoAccess) }
                case .preview:
                    model.goTo(.paywall)
                default:
                    model.advance()
                }
            } label: {
                Text(buttonTitle)
                    .font(.themeButton)
                    .foregroundStyle(Color.themeTextOnAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        LinearGradient(colors: [.themeAccent, .themeAccentStrong],
                                       startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboardingContinueButton")
        }
    }

    private var buttonTitle: String {
        switch model.step {
        case .photoPriming: return String(localized: "Choose Photos")
        case .preview, .paywall: return String(localized: "See Premium")
        default: return String(localized: "Continue")
        }
    }
}
