//
//  SettingsView.swift
//  Caroullage
//
//  Home retention, phase 3 — the Settings sheet.
//
//  SwiftUI, like the paywall and onboarding: a form with a toggle, a few
//  rows and a version line is the one shape SwiftUI beats a hand-built table
//  on. Not a `Form`, though — that brings the system's grouped-list look,
//  and every surface in this app is drawn from `Theme`. The rows are cards
//  on the app's background, the way the editor panels are.
//
//  Identifiers sit on the controls, not on the hosting root: a root
//  identifier overrides default-styled children's, so each row is
//  `.buttonStyle(.plain)` with its own name.
//

import SwiftUI

struct SettingsView: View {

    @ObservedObject var model: SettingsViewModel
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header
                notifications
                purchases
                about
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .background(Color.themeBackground.ignoresSafeArea())
        .task { await model.load() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.themeTitle)
                .foregroundStyle(Color.themeTextPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(action: onDone) {
                Text("Done").font(.themeButton).hitTargetPadded()
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.themeAccentStrong)
            .accessibilityIdentifier("settingsDoneButton")
        }
    }

    // MARK: - Notifications

    private var notifications: some View {
        section(String(localized: "Notifications")) {
            Toggle(isOn: Binding(
                get: { model.remindersEnabled },
                set: { enabled in Task { await model.setReminders(enabled) } }
            )) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text("Reminders")
                        .font(.themeHeadline)
                        .foregroundStyle(Color.themeTextPrimary)
                    Text("A nudge about an unfinished collage, and a heads-up when a seasonal collection lands. Never more than one a week.")
                        .font(.themeCaption)
                        .foregroundStyle(Color.themeTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Color.themeAccent)
            .padding(Theme.Spacing.md)
            .accessibilityIdentifier("settingsRemindersToggle")

            if model.remindersBlockedBySystem {
                divider
                row(identifier: "settingsOpenSystemSettings", action: model.openSystemSettings) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text("Notifications are off for Caroullage in the Settings app.")
                            .font(.themeCaption)
                            .foregroundStyle(Color.themeWarning)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Open Settings")
                            .font(.themeHeadline)
                            .foregroundStyle(Color.themeAccentStrong)
                    }
                } trailing: {
                    Image(systemName: "arrow.up.forward")
                }
            }
        }
    }

    // MARK: - Purchases

    private var purchases: some View {
        section(String(localized: "Purchases")) {
            if model.isPremium {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.themeSuccess)
                    Text("Premium is unlocked on this Apple Account.")
                        .font(.themeSubheadline)
                        .foregroundStyle(Color.themeTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.Spacing.md)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("settingsPremiumStatus")
                divider
            }

            row(identifier: "settingsRestoreButton", action: { Task { await model.restore() } }) {
                Text(model.isRestoring ? "Restoring…" : "Restore Purchases")
                    .font(.themeHeadline)
                    .foregroundStyle(Color.themeTextPrimary)
            } trailing: {
                if model.isRestoring { ProgressView() } else { Image(systemName: "arrow.clockwise") }
            }
            .disabled(model.isRestoring)

            if let message = model.restoreMessage ?? model.restoreFailure {
                Text(message)
                    .font(.themeCaption)
                    .foregroundStyle(model.restoreFailure == nil ? Color.themeTextSecondary : Color.themeCritical)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.sm)
                    .accessibilityIdentifier("settingsRestoreMessage")
            }

            divider
            row(identifier: "settingsManageSubscriptionLink",
                action: { model.open(LegalLinks.manageSubscriptions) }) {
                Text("Manage Subscription")
                    .font(.themeHeadline)
                    .foregroundStyle(Color.themeTextPrimary)
            } trailing: {
                Image(systemName: "arrow.up.forward")
            }
        }
    }

    // MARK: - About

    private var about: some View {
        section(String(localized: "About")) {
            row(identifier: "settingsTermsLink", action: { model.open(LegalLinks.terms) }) {
                Text("Terms of Use").font(.themeHeadline).foregroundStyle(Color.themeTextPrimary)
            } trailing: {
                Image(systemName: "arrow.up.forward")
            }
            divider
            row(identifier: "settingsPrivacyLink", action: { model.open(LegalLinks.privacy) }) {
                Text("Privacy Policy").font(.themeHeadline).foregroundStyle(Color.themeTextPrimary)
            } trailing: {
                Image(systemName: "arrow.up.forward")
            }
            divider
            HStack {
                Text("Version").font(.themeHeadline).foregroundStyle(Color.themeTextPrimary)
                Spacer()
                Text(model.version)
                    .font(.themeSubheadline)
                    .foregroundStyle(Color.themeTextSecondary)
                    .accessibilityIdentifier("settingsVersionLabel")
            }
            .padding(Theme.Spacing.md)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Pieces

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(.themeCaption)
                .foregroundStyle(Color.themeTextSecondary)
                .textCase(.uppercase)
                .padding(.horizontal, Theme.Spacing.xs)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { content() }
                .background(Color.themeSurface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.themeSeparator)
            .frame(height: 1 / UIScreen.main.scale)
            .padding(.leading, Theme.Spacing.md)
    }

    private func row<Label: View, Trailing: View>(
        identifier: String,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                label()
                Spacer(minLength: Theme.Spacing.sm)
                trailing()
                    .font(.themeSubheadline)
                    .foregroundStyle(Color.themeTextSecondary)
            }
            .padding(Theme.Spacing.md)
            .frame(minHeight: Theme.Layout.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
