//
//  ExportLiveActivity.swift
//  CaroullageWidgets
//
//  Step 04 slice 6b — the Lock Screen + Dynamic Island rendering of an in-progress
//  export. Driven by `ExportLiveActivityController` in the app via the shared
//  `ExportActivityAttributes` (added to this target's sources in project.yml).
//
//  Self-contained styling (no dependency on the app's Theme, which isn't in this
//  target): the brand orange as a literal, system materials for backgrounds.
//

import ActivityKit
import SwiftUI
import WidgetKit

private let brandOrange = Color(red: 1.0, green: 0.45, blue: 0.16)

struct ExportLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ExportActivityAttributes.self) { context in
            lockScreen(context.attributes, context.state)
                .activityBackgroundTint(Color.black.opacity(0.6))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: symbol(context.state))
                        .foregroundStyle(brandOrange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.percentText)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    progressBar(context.state)
                }
            } compactLeading: {
                Image(systemName: symbol(context.state)).foregroundStyle(brandOrange)
            } compactTrailing: {
                Text(context.state.percentText).font(.caption.monospacedDigit())
            } minimal: {
                Image(systemName: symbol(context.state)).foregroundStyle(brandOrange)
            }
            .widgetURL(URL(string: "caroullage://export"))
            .keylineTint(brandOrange)
        }
    }

    // MARK: - Lock Screen

    private func lockScreen(
        _ attributes: ExportActivityAttributes,
        _ state: ExportActivityAttributes.ContentState
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol(state))
                .font(.title2)
                .foregroundStyle(brandOrange)
            VStack(alignment: .leading, spacing: 6) {
                Text(state.isComplete ? "Export complete" : attributes.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                progressBar(state)
            }
            Text(state.percentText)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding()
    }

    private func progressBar(_ state: ExportActivityAttributes.ContentState) -> some View {
        ProgressView(value: state.fraction)
            .progressViewStyle(.linear)
            .tint(brandOrange)
    }

    private func symbol(_ state: ExportActivityAttributes.ContentState) -> String {
        state.isComplete ? "checkmark.circle.fill" : "square.and.arrow.up"
    }
}
