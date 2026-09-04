//
//  CarouselTypeSelectorView.swift
//  Caroullage
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
            // Only when presented as a sheet. As a tab root the navigation bar
            // already says "New Carousel", and drawing it again below produced
            // the title twice, the second time in orange.
            if onCancel != nil { header }
            ScrollView {
                // Tight enough that the four type cards and both option controls
                // fit without scrolling on a standard phone. At the previous
                // spacing the aspect picker landed exactly on the scroll
                // boundary and rendered as a control sliced in half, which reads
                // as a bug rather than as more content below.
                VStack(spacing: 14) {
                    ForEach(infos) { info in
                        card(info)
                    }
                    options
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            createButton
        }
        .background(Color(Theme.Color.background).ignoresSafeArea())
    }

    @ViewBuilder private var header: some View {
        if let onCancel {
            HStack {
                Button("Cancel", action: onCancel)
                    .accessibilityIdentifier("carouselCancelButton")
                Spacer()
                Text("New Carousel")
                    .font(.themeHeadline)
                    .foregroundStyle(Color.themeTextPrimary)
                Spacer()
                Button("Cancel", action: onCancel).opacity(0)   // balance the title
                    .accessibilityHidden(true)
            }
            .padding()
            .foregroundStyle(Color.themeAccentStrong)
        }
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
            .padding(14)
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
                // "Direction", not "Split": for panoramic it still decides how the
                // source photo is cut, but for every other type it decides which
                // way the frames are laid out and swiped.
                Picker("Direction", selection: $splitAxis) {
                    ForEach(SplitAxis.allCases, id: \.self) { axis in
                        Text(axis.displayName).tag(axis)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("carouselDirectionPicker")
            }
            Picker("Aspect", selection: $aspect) {
                Text("1:1").tag("1:1")
                Text("4:5").tag("4:5")
                Text("9:16").tag("9:16")
                Text("16:9").tag("16:9")
            }
            .pickerStyle(.segmented)
        }
        .padding(.top, 4)
    }

    private var createButton: some View {
        Button {
            onCreate(config)
        } label: {
            Text(type == .panoramic ? "Choose Photo" : "Create")
                .font(.themeHeadline)
                .frame(maxWidth: .infinity)
                .padding()
                // `accentStrong`, not `accent`: a filled call to action is
                // chrome, and `textOnAccent` on `accentStrong` is the pair
                // `ThemeContrastTests` pins.
                .background(Color.themeAccentStrong)
                .foregroundStyle(Color.themeTextOnAccent)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .accessibilityIdentifier("carouselCreateButton")
    }
}
