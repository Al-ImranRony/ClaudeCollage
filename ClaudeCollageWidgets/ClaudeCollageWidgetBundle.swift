//
//  ClaudeCollageWidgetBundle.swift
//  ClaudeCollageWidgets
//
//  Stub for Step 00. Real widgets ("Recent Projects", "Photo of the Day") land in Step 05.
//

import WidgetKit
import SwiftUI

@available(iOS 17.0, *)
@main
struct ClaudeCollageWidgetBundle: WidgetBundle {
    var body: some Widget {
        // Step 00's PlaceholderWidget is deliberately no longer offered: a real
        // widget exists now, and shipping a stub alongside it would put an empty
        // "ClaudeCollage" tile in the user's widget gallery.
        RecentProjectsWidget()
        // The in-progress export Live Activity (Step 04 slice 6b).
        ExportLiveActivity()
    }
}

@available(iOS 17.0, *)
struct PlaceholderWidget: Widget {
    let kind: String = "PlaceholderWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PlaceholderProvider()) { entry in
            PlaceholderWidgetView(entry: entry)
        }
        .configurationDisplayName("ClaudeCollage")
        .description("Widget arrives in Step 05.")
        .supportedFamilies([.systemSmall])
    }
}

struct PlaceholderEntry: TimelineEntry {
    let date: Date
}

struct PlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlaceholderEntry { PlaceholderEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping @Sendable (PlaceholderEntry) -> Void) {
        completion(PlaceholderEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<PlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [PlaceholderEntry(date: Date())], policy: .never))
    }
}

@available(iOS 17.0, *)
struct PlaceholderWidgetView: View {
    let entry: PlaceholderEntry
    var body: some View {
        Text("ClaudeCollage")
            .font(.headline)
            .containerBackground(.fill.tertiary, for: .widget)
    }
}
