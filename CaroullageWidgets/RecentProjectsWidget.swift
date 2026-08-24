//
//  RecentProjectsWidget.swift
//  CaroullageWidgets
//
//  Step 05 batch C — recent projects on the Home Screen.
//
//  Reads `WidgetSnapshot`, which the app writes. Note the sandbox rule: without
//  the App Group entitlement (deferred to Step 06) this extension cannot see what
//  the app wrote, and the empty state is what renders. That is the correct
//  behaviour rather than a bug — and the moment the entitlement is added, real
//  entries appear with no change here.
//

import SwiftUI
import WidgetKit

struct RecentProjectsEntry: TimelineEntry {
    let date: Date
    let projects: [WidgetProjectEntry]
}

struct RecentProjectsProvider: TimelineProvider {

    private let store = WidgetSnapshotStore()

    func placeholder(in context: Context) -> RecentProjectsEntry {
        RecentProjectsEntry(date: Date(), projects: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (RecentProjectsEntry) -> Void) {
        completion(RecentProjectsEntry(date: Date(), projects: store.read().projects))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentProjectsEntry>) -> Void) {
        let entry = RecentProjectsEntry(date: Date(), projects: store.read().projects)
        // Half-hourly, per the brief. The app also reloads timelines when it saves,
        // so this is the floor rather than the only refresh.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct RecentProjectsWidgetView: View {

    @Environment(\.widgetFamily) private var family
    let entry: RecentProjectsEntry

    private var visibleCount: Int {
        switch family {
        case .systemSmall: return 1
        case .systemMedium: return 3
        default: return 6
        }
    }

    var body: some View {
        Group {
            if entry.projects.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .containerBackground(for: .widget) { Color(white: 0.98) }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.grid.2x2")
                .font(.title2)
                .foregroundStyle(Color(red: 0.91, green: 0.42, blue: 0.16))
            Text("No collages yet")
                .font(.caption).bold()
                .foregroundStyle(.primary)
            if family != .systemSmall {
                Text("Make one to see it here")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(8)
    }

    private var grid: some View {
        let shown = Array(entry.projects.prefix(visibleCount))
        let columns = family == .systemSmall ? 1 : 3
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns),
            spacing: 6
        ) {
            ForEach(shown) { project in
                // Deep link straight into that project.
                Link(destination: URL(string: "caroullage://project/\(project.id.uuidString)")!) {
                    thumbnail(for: project)
                }
            }
        }
        .padding(10)
    }

    @ViewBuilder
    private func thumbnail(for project: WidgetProjectEntry) -> some View {
        ZStack {
            if let data = project.thumbnailData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // A project saved before its first thumbnail render.
                Color(white: 0.92)
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct RecentProjectsWidget: Widget {

    let kind = "RecentProjectsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecentProjectsProvider()) { entry in
            RecentProjectsWidgetView(entry: entry)
        }
        .configurationDisplayName("Recent Collages")
        .description("Your latest collages, one tap away.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
