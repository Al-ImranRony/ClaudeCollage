//
//  PaywallView.swift
//  Caroullage
//
//  Step 06 phase 6.2 — the highest-stakes screen in the app.
//
//  SwiftUI, per the brief: it is a static form with no canvas or gesture work,
//  and layout iteration is faster here. Presented from UIKit through
//  `PaywallHostingController`.
//
//  Two things are load-bearing for App Review and are therefore not negotiable
//  in layout work: the close button is visible from the first frame, and the
//  exact price with its renewal terms sits directly under the button that
//  commits the user.
//

import SwiftUI

struct PaywallView: View {

    @ObservedObject var model: PaywallViewModel

    /// Called after a purchase or restore that left the user premium.
    var onUnlocked: () -> Void
    var onClose: () -> Void

    @State private var heroIndex = 0

    private static let features = [
        ("square.grid.3x3.fill", "200+ templates, every carousel type"),
        ("hexagon.fill", "All polygon shapes and custom bezier"),
        ("4k.tv.fill", "4K video export, no watermark"),
        ("wand.and.stars", "Generative AI backgrounds"),
        ("icloud.fill", "Unlimited saves and iCloud sync"),
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.themeBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    hero
                    headline
                    featureList
                    planPicker
                    commitSection
                    footer
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.top, Theme.Spacing.xxl)
                .padding(.bottom, Theme.Spacing.xxl)
            }

            closeButton
        }
        .task { await model.load() }
    }

    // MARK: - Close

    private var closeButton: some View {
        Button(action: {
            Haptics.tap()
            onClose()
        }) {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.themeTextSecondary)
                .frame(width: 32, height: 32)
                .background(Color.themeControlFill, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(Theme.Spacing.md)
        .accessibilityIdentifier("paywallCloseButton")
        .accessibilityLabel("Close")
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.themeAccent, .themeAccentStrong],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )

            Image(systemName: PaywallView.heroSymbols[heroIndex])
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(Color.themeTextOnAccent)
                .transition(.opacity)
                .id(heroIndex)
        }
        .frame(height: 168)
        .accessibilityHidden(true)
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            withAnimation(.easeInOut(duration: Theme.Motion.duration(Theme.Motion.standard))) {
                heroIndex = (heroIndex + 1) % PaywallView.heroSymbols.count
            }
        }
    }

    private static let heroSymbols = ["rectangle.stack.fill", "square.grid.3x3.fill", "wand.and.stars"]

    // MARK: - Copy

    private var headline: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text("Unlock Caroullage Premium")
                .font(.themeTitle)
                .foregroundStyle(Color.themeTextPrimary)
                .multilineTextAlignment(.center)
            Text("Everything, unlocked. Cancel whenever you like.")
                .font(.themeSubheadline)
                .foregroundStyle(Color.themeTextSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(Self.features, id: \.1) { symbol, text in
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.themeAccentStrong)
                        .frame(width: 26)
                    Text(text)
                        .font(.themeBody)
                        .foregroundStyle(Color.themeTextPrimary)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Plans

    @ViewBuilder
    private var planPicker: some View {
        if model.isStoreUnavailable {
            VStack(spacing: Theme.Spacing.xs) {
                Text("Plans are unavailable right now")
                    .font(.themeHeadline)
                    .foregroundStyle(Color.themeTextPrimary)
                Text("Check your connection and try again in a moment.")
                    .font(.themeSubheadline)
                    .foregroundStyle(Color.themeTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity)
            .background(Color.themeSurface, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .accessibilityIdentifier("paywallUnavailable")
        } else {
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(model.plans) { plan in
                    planRow(plan)
                }
            }
        }
    }

    private func planRow(_ plan: PaywallViewModel.Plan) -> some View {
        let isSelected = plan.product == model.selectedProduct
        return Button(action: {
            Haptics.selectionChanged()
            withAnimation(.easeOut(duration: Theme.Motion.duration(Theme.Motion.quick))) {
                model.select(plan.product)
            }
        }) {
            HStack(spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(plan.title)
                            .font(.themeHeadline)
                            .foregroundStyle(Color.themeTextPrimary)
                        if let badge = plan.badge {
                            Text(badge.uppercased())
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(Color.themeTextOnAccent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.themeAccentStrong, in: Capsule())
                        }
                    }
                    Text(plan.priceLine)
                        .font(.themeSubheadline)
                        .foregroundStyle(Color.themeTextSecondary)
                }

                Spacer(minLength: 0)

                if let secondary = plan.secondaryLine {
                    Text(secondary)
                        .font(.themeCaption)
                        .foregroundStyle(Color.themeTextSecondary)
                        .multilineTextAlignment(.trailing)
                }

                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.themeAccentStrong : Color.themeSeparator)
            }
            .padding(Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .fill(Color.themeSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .stroke(isSelected ? Color.themeAccentStrong : Color.themeSeparator,
                            lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("paywallPlan.\(plan.product.rawValue)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Commit

    @ViewBuilder
    private var commitSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if let title = model.callToAction {
                Button(action: {
                    Task {
                        if await model.purchaseSelected() {
                            Haptics.success()
                            onUnlocked()
                        }
                    }
                }) {
                    ZStack {
                        LinearGradient(
                            colors: [.themeAccent, .themeAccentStrong],
                            startPoint: .leading, endPoint: .trailing
                        )
                        if model.isPurchasing {
                            ProgressView().tint(Color.themeTextOnAccent)
                        } else {
                            Text(title)
                                .font(.themeButton)
                                .foregroundStyle(Color.themeTextOnAccent)
                        }
                    }
                    .frame(height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(model.isPurchasing)
                .accessibilityIdentifier("paywallSubscribeButton")
            }

            Text(model.termsText)
                .font(.system(size: 11))
                .foregroundStyle(Color.themeTextSecondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("paywallTerms")

            if let error = model.errorMessage {
                Text(error)
                    .font(.themeCaption)
                    .foregroundStyle(Color.themeCritical)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("paywallError")
            }

            if let restore = model.restoreMessage {
                Text(restore)
                    .font(.themeCaption)
                    .foregroundStyle(Color.themeTextSecondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("paywallRestoreMessage")
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button("Restore Purchase") {
                Task {
                    if await model.restore() {
                        Haptics.success()
                        onUnlocked()
                    }
                }
            }
            .accessibilityIdentifier("paywallRestoreButton")

            Link("Terms", destination: PaywallView.termsURL)
            Link("Privacy", destination: PaywallView.privacyURL)
        }
        .font(.themeCaption)
        .foregroundStyle(Color.themeTextSecondary)
        .buttonStyle(.plain)
    }

    // Both must resolve before submission — App Review checks them.
    static let termsURL = URL(string: "https://devron.com/legal/caroullage/terms.html")!
    static let privacyURL = URL(string: "https://devron.com/legal/caroullage/privacy.html")!
}
