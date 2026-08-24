//
//  FilterStripView.swift
//  Caroullage
//
//  Step 01 — the per-cell filter strip. This is a small form, so it's the one
//  place in the grid editor where SwiftUI is genuinely simpler than UIKit; it's
//  embedded into the UIKit editor via UIHostingController (the interop pattern
//  from the project plan).
//

import SwiftUI

struct FilterStripView: View {

    /// Live filter values. Changes stream back out via `onChange`.
    @State private var filters: CellFilters
    private let onChange: (CellFilters) -> Void
    private let onDone: () -> Void

    init(
        filters: CellFilters,
        onChange: @escaping (CellFilters) -> Void,
        onDone: @escaping () -> Void
    ) {
        _filters = State(initialValue: filters)
        self.onChange = onChange
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Adjust") {
                    slider("Brightness", value: $filters.brightness, range: -0.5 ... 0.5)
                    slider("Contrast", value: $filters.contrast, range: 0.5 ... 1.5)
                    slider("Saturation", value: $filters.saturation, range: 0.0 ... 2.0)
                    slider("Warmth", value: $filters.warmth, range: -1.0 ... 1.0)
                    slider("Sharpness", value: $filters.sharpness, range: 0.0 ... 1.0)
                }
                Section {
                    Button("Reset", role: .destructive) {
                        filters = CellFilters()
                        onChange(filters)
                    }
                }
            }
            .navigationTitle("Edit Cell")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone() }
                }
            }
        }
    }

    private func slider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.themeSubheadline)
                .foregroundStyle(Color.themeTextSecondary)
            Slider(value: value, in: range) { editing in
                if !editing { onChange(filters) }
            }
            .onChange(of: value.wrappedValue) { _, _ in
                onChange(filters)
            }
        }
    }
}
