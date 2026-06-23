//
//  ClaudeCollageWidgetBundle.swift
//  ClaudeCollageWidgets
//
//  Stub for Step 00. Real widgets ("Recent Projects", "Photo of the Day") land in Step 05.
//

import WidgetKit
import SwiftUI

@main
struct ClaudeCollageWidgetBundle: WidgetBundle {
    var body: some Widget {
        PlaceholderWidget()
    }
}

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

struct PlaceholderWidgetView: View {
    let entry: PlaceholderEntry
    var body: some View {
        Text("ClaudeCollage")
            .font(.headline)
            .containerBackground(.fill.tertiary, for: .widget)
    }
}
