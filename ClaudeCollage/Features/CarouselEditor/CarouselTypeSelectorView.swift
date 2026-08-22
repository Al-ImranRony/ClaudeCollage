//
//  CarouselTypeSelectorView.swift
//  ClaudeCollage
//
//  Step 03b slice 5 — the "new carousel" screen (SwiftUI, no canvas, so a simple
//  form fits the plan's guidance). Pick one of the four carousel types, choose the
//  frame count (and split axis for panoramic), and Create. The result is a
//  `CarouselStartConfig` the coordinator turns into frames via the slice-3 builders.
//

import SwiftUI

struct CarouselTypeSelectorView: View {

    let onCreate: (CarouselStartConfig) -> Void
    /// `nil` when the selector is a tab root rather than a sheet — there is
    /// nothing to dismiss, so the header collapses to just the title.
    let onCancel: (() -> Void)?

    @State private var type: CarouselType = .matched
    @State private var frameCount = 3
    @State private var splitAxis: SplitAxis = .horizontal
    @State private var aspect = "4:5"

    private struct TypeInfo: Identifiable {
        let id: CarouselType
        let title: String
        let subtitle: String
        let symbol: String
    }

    private let infos: [TypeInfo] = [
        .init(id: .panoramic, title: "Panoramic",
              subtitle: "One wide photo split across frames", symbol: "photo.on.rectangle.angled"),
        .init(id: .matched, title: "Matched",
              subtitle: "Same design, different photos", symbol: "square.grid.2x2"),
        .init(id: .scrollThrough, title: "Scroll-Through",
              subtitle: "Photo + caption story frames", symbol: "text.below.photo"),
        .init(id: .gridPreview, title: "Grid Preview",
              subtitle: "Reveal a grid, then each cell", symbol: "square.split.2x2"),
    ]

    private var config: CarouselStartConfig {
        CarouselStartConfig(type: type, frameCount: frameCount,
                            splitAxis: splitAxis, aspectRatio: aspect)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(infos) { info in
                        card(info)
                    }
                    options
                }
                .padding(20)
            }
            createButton
        }
        .background(Color(Theme.Color.background).ignoresSafeArea())
    }

    private var header: some View {
        HStack {
            if let onCancel {
                Button("Cancel", action: onCancel)
                    .accessibilityIdentifier("carouselCancelButton")
                Spacer()
                Text("New Carousel").font(.themeHeadline)
                Spacer()
                Button("Cancel", action: onCancel).opacity(0)   // balance the title
                    .accessibilityHidden(true)
            } else {
                Spacer()
                Text("New Carousel").font(.themeHeadline)
                Spacer()
            }
        }
        .padding()
        .foregroundStyle(Color(Theme.Color.accent))
    }

    private func card(_ info: TypeInfo) -> some View {
        let selected = info.id == type
        return Button {
            type = info.id
        } label: {
            HStack(spacing: 16) {
                Image(systemName: info.symbol)
                    .font(.system(size: 28))
                    .frame(width: 44)
                    .foregroundStyle(Color(Theme.Color.accent))
                VStack(alignment: .leading, spacing: 4) {
                    Text(info.title)
                        .font(.themeHeadline)
                        .foregroundStyle(Color(Theme.Color.textPrimary))
                    Text(info.subtitle)
                        .font(.themeSubheadline)
                        .foregroundStyle(Color(Theme.Color.textSecondary))
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(Theme.Color.accent))
                }
            }
            .padding(16)
            .background(Color(Theme.Color.surface))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(Theme.Color.accent), lineWidth: selected ? 2 : 0)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("carouselType-\(info.id.rawValue)")
    }

    @ViewBuilder private var options: some View {
        VStack(spacing: 16) {
            if config.showsFrameCount {
                Stepper(value: $frameCount, in: 2...10) {
                    Text("Frames: \(frameCount)")
                        .foregroundStyle(Color(Theme.Color.textPrimary))
                }
                .accessibilityIdentifier("carouselFrameCountStepper")
            }
            if config.showsSplitAxis {
                Picker("Split", selection: $splitAxis) {
                    Text("Horizontal").tag(SplitAxis.horizontal)
                    Text("Vertical").tag(SplitAxis.vertical)
                }
                .pickerStyle(.segmented)
            }
            Picker("Aspect", selection: $aspect) {
                Text("1:1").tag("1:1")
                Text("4:5").tag("4:5")
                Text("9:16").tag("9:16")
                Text("16:9").tag("16:9")
            }
            .pickerStyle(.segmented)
        }
        .padding(.top, 8)
    }

    private var createButton: some View {
        Button {
            onCreate(config)
        } label: {
            Text(type == .panoramic ? "Choose Photo" : "Create")
                .font(.themeHeadline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(Theme.Color.accent))
                .foregroundStyle(Color(Theme.Color.textOnAccent))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(20)
        .accessibilityIdentifier("carouselCreateButton")
    }
}
