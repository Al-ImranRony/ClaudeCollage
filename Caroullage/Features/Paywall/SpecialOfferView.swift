//
//  SpecialOfferView.swift
//  Caroullage
//
//  Step 06 phase 6.2b — the discounted second chance, shown once to someone who
//  closed the paywall without buying.
//
//  The shape is the one the owner asked for: a full-bleed hero, the saving in
//  the headline, and a dark card that puts the standard price and the offer
//  price one above the other. Two additions the reference shot does not have,
//  both required rather than decorative — the renewal terms under the button
//  (App Store §3.1.1) and a close button that is legible from the first frame.
//

import SwiftUI

struct SpecialOfferView: View {

    @ObservedObject var model: SpecialOfferViewModel

    var onUnlocked: () -> Void
    var onClose: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            hero
            VStack(spacing: 0) {
                HStack {
                    closeButton
                    Spacer()
                }
                Spacer()
                headline
                offerCard
            }
        }
        .task { await model.load() }
    }

    // MARK: - Hero

    /// A lit-up carousel: the app's own motif, drawn rather than shipped as a
    /// photo so the screen adds nothing to the bundle.
    private var hero: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.36, green: 0.05, blue: 0.24),
                             Color(red: 0.15, green: 0.02, blue: 0.12),
                             .black],
                    startPoint: .top, endPoint: .bottom
                )
                CarouselMotif()
                    .frame(width: geometry.size.width * 1.1)
                    .offset(y: -geometry.size.height * 0.12)
                LinearGradient(
                    colors: [.clear, .black.opacity(0.55), .black],
                    startPoint: .center, endPoint: .bottom
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var closeButton: some View {
        Button(action: {
            Haptics.tap()
            onClose()
        }) {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.18), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(.leading, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.xs)
        .accessibilityIdentifier("specialOfferCloseButton")
        .accessibilityLabel("Close")
    }

    // MARK: - Headline

    private var headline: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(model.headline)
                .foregroundStyle(.white)
            Text(model.savingText)
                .foregroundStyle(Color.themeAccent)
            Spacer(minLength: 0)
        }
        .font(.system(size: 44, weight: .heavy, design: .rounded))
        .minimumScaleFactor(0.6)
        .lineLimit(1)
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.lg)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("specialOfferHeadline")
    }

    // MARK: - Card

    private var offerCard: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text(model.periodText)
                .font(.themeHeadline)
                .foregroundStyle(.white)

            Text(model.regularPriceText)
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.themeCritical)
                .strikethrough(true, color: Color.themeCritical)
                .accessibilityLabel("Standard price \(model.regularPriceText) per year")

            Image(systemName: "chevron.down")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))

            Text("only \(model.offerPriceText)")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.themeAccent)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .accessibilityIdentifier("specialOfferPrice")

            continueButton

            // Required on the screen where the user commits.
            Text(model.termsText)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("specialOfferTerms")

            if let error = model.errorMessage {
                Text(error)
                    .font(.themeCaption)
                    .foregroundStyle(Color.themeCritical)
                    .multilineTextAlignment(.center)
            }

            footer
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.top, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.09))
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: Theme.Radius.xl, topTrailingRadius: Theme.Radius.xl, style: .continuous))
    }

    private var continueButton: some View {
        Button(action: {
            Task {
                if await model.accept() {
                    Haptics.success()
                    onUnlocked()
                }
            }
        }) {
            ZStack {
                Capsule().fill(Color.themeAccent)
                if model.isPurchasing {
                    ProgressView().tint(.black)
                } else {
                    Text("Continue")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                }
            }
            .frame(height: 62)
        }
        .buttonStyle(.plain)
        .disabled(model.isPurchasing || !model.isAvailable)
        .padding(.top, Theme.Spacing.xs)
        .accessibilityIdentifier("specialOfferContinueButton")
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Link("Terms of Use", destination: PaywallView.termsURL)
            Text("|")
            Link("Privacy Policy", destination: PaywallView.privacyURL)
            Text("|")
            Button("Restore Purchases") {
                Task {
                    if await model.restore() {
                        Haptics.success()
                        onUnlocked()
                    }
                }
            }
            .accessibilityIdentifier("specialOfferRestoreButton")
        }
        .font(.system(size: 13))
        .foregroundStyle(.white.opacity(0.65))
        .buttonStyle(.plain)
        .padding(.top, 2)
    }
}

/// The lights-and-canopy shape behind the offer. Pure geometry: no asset, no
/// download, and it scales to any width.
private struct CarouselMotif: View {

    var body: some View {
        Canvas { context, size in
            let centre = CGPoint(x: size.width / 2, y: size.height * 0.62)
            let canopyRadius = size.width * 0.46

            // Canopy.
            var canopy = Path()
            canopy.move(to: CGPoint(x: centre.x - canopyRadius, y: centre.y))
            canopy.addQuadCurve(
                to: CGPoint(x: centre.x + canopyRadius, y: centre.y),
                control: CGPoint(x: centre.x, y: centre.y - canopyRadius * 1.15))
            context.fill(canopy, with: .linearGradient(
                Gradient(colors: [Color(red: 0.62, green: 0.16, blue: 0.42),
                                  Color(red: 0.30, green: 0.06, blue: 0.22)]),
                startPoint: CGPoint(x: centre.x, y: centre.y - canopyRadius),
                endPoint: CGPoint(x: centre.x, y: centre.y)))

            // Bulbs along the rim, brightest at the centre.
            for index in 0..<28 {
                let t = Double(index) / 27
                let angle = .pi * (1 - t)
                let x = centre.x + cos(angle) * canopyRadius * 0.98
                let y = centre.y - sin(angle) * canopyRadius * 0.86
                let glow = 0.55 + 0.45 * sin(t * .pi)
                let bulb = Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8))
                context.fill(bulb, with: .color(Color(red: 1, green: 0.85, blue: 0.6).opacity(glow)))
            }

            // Poles.
            for index in 0..<7 {
                let t = Double(index) / 6
                let x = centre.x + (t - 0.5) * canopyRadius * 1.7
                var pole = Path()
                pole.move(to: CGPoint(x: x, y: centre.y))
                pole.addLine(to: CGPoint(x: x, y: centre.y + size.height * 0.3))
                context.stroke(pole, with: .color(.white.opacity(0.22)), lineWidth: 3)
            }
        }
        .aspectRatio(1.2, contentMode: .fit)
    }
}
