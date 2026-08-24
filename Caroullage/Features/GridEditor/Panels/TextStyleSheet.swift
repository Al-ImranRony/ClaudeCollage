//
//  TextStyleSheet.swift
//  Caroullage
//
//  Step 03a slice 5 — the text-zone styling panel. A SwiftUI form hosted in a
//  `UISheetPresentationController` bottom sheet (see GridEditorViewController). It
//  edits a copy of the tapped `TextOverlay` and streams every change back through
//  `onChange` so the canvas updates live; `onDone` commits one undo snapshot.
//
//  Uses the app design tokens (Theme accent tint, rounded typography) rather than
//  raw system defaults, per the project's design-foundation rule.
//

import SwiftUI

struct TextStyleSheet: View {

    /// A curated set of faces (display name → the font's PostScript/family name).
    /// "System" intentionally maps to an unresolvable name so `TextRendering`
    /// falls back to the rounded system font.
    private static let fonts: [(label: String, name: String)] = [
        ("System", "SFProRounded-Semibold"),
        ("Helvetica", "HelveticaNeue"),
        ("Avenir", "AvenirNext-Regular"),
        ("Georgia", "Georgia"),
        ("Futura", "Futura-Medium"),
        ("Baskerville", "Baskerville"),
        ("Copperplate", "Copperplate"),
        ("Marker", "MarkerFelt-Wide"),
        ("Script", "SnellRoundhand"),
        ("Chalkboard", "ChalkboardSE-Regular"),
    ]

    /// Preset colour swatches — neutrals, brand orange, and a few social-friendly hues.
    private static let swatches: [String] = [
        "#000000", "#FFFFFF", "#E86A2A", "#F29B3C", "#F5C542",
        "#2E7D5B", "#2F6FB0", "#7A4FB0", "#C0405B", "#8A8A8E",
    ]

    @State private var overlay: TextOverlay
    private let onChange: (TextOverlay) -> Void
    private let onDone: () -> Void

    init(
        overlay: TextOverlay,
        onChange: @escaping (TextOverlay) -> Void,
        onDone: @escaping () -> Void
    ) {
        _overlay = State(initialValue: overlay)
        self.onChange = onChange
        self.onDone = onDone
    }

    private var accent: Color { Color(uiColor: Theme.Color.accent) }
    /// The fill under a selected chip's label. `accent` would be 3.1:1 against
    /// white at this text size; `accentStrong` is the token that carries ink.
    private var accentFill: Color { .themeAccentStrong }

    var body: some View {
        NavigationStack {
            Form {
                textSection
                fontSection
                styleSection
                colorSection
                spacingSection
            }
            .navigationTitle("Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone() }
                        .fontWeight(.semibold)
                }
            }
            .tint(accent)
        }
    }

    // MARK: - Sections

    private var textSection: some View {
        Section("Text") {
            TextField("Enter text", text: binding(\.text), axis: .vertical)
                .lineLimit(1...4)
                .font(.themeBody)
        }
    }

    private var fontSection: some View {
        Section("Font") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.fonts, id: \.name) { entry in
                        let isSelected = overlay.fontName == entry.name
                        Button {
                            update { $0.fontName = entry.name }
                        } label: {
                            Text(entry.label)
                                .font(fontPreview(entry.name))
                                .lineLimit(1)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(isSelected ? accentFill : Color.themeControlFill)
                                .foregroundStyle(isSelected ? Color.themeTextOnAccent : Color.themeTextPrimary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        }
    }

    private var styleSection: some View {
        Section("Style") {
            Picker("Alignment", selection: alignmentBinding) {
                Image(systemName: "text.alignleft").tag(TextOverlay.Alignment.leading)
                Image(systemName: "text.aligncenter").tag(TextOverlay.Alignment.center)
                Image(systemName: "text.alignright").tag(TextOverlay.Alignment.trailing)
                Image(systemName: "text.justify").tag(TextOverlay.Alignment.justified)
            }
            .pickerStyle(.segmented)

            Toggle("Bold", isOn: binding(\.isBold))
            Toggle("Italic", isOn: binding(\.isItalic))
            Toggle("Underline", isOn: binding(\.isUnderlined))
        }
    }

    private var colorSection: some View {
        Section("Color") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                ForEach(Self.swatches, id: \.self) { hex in
                    let isSelected = overlay.colorHex.caseInsensitiveCompare(hex) == .orderedSame
                    Circle()
                        .fill(Color(uiColor: UIColor(hex: hex)))
                        .frame(height: 30)
                        .overlay(Circle().stroke(Color.themeSeparator, lineWidth: 0.5))
                        .overlay(
                            Circle().stroke(accent, lineWidth: isSelected ? 3 : 0).padding(-3)
                        )
                        .onTapGesture { update { $0.colorHex = hex } }
                }
            }
            .padding(.vertical, 4)

            ColorPicker("Custom color", selection: customColorBinding, supportsOpacity: false)
        }
    }

    private var spacingSection: some View {
        Section("Adjust") {
            slider("Size", value: binding(\.fontSize), range: 24...260, unit: "pt")
            slider("Letter spacing", value: binding(\.letterSpacing), range: -8...40, unit: "")
            slider("Line height", value: binding(\.lineHeight), range: 0.8...2.0, unit: "×")
            slider("Opacity", value: binding(\.opacity), range: 0...1, unit: "%", displayScale: 100)
        }
    }

    // MARK: - Building blocks

    private func slider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        unit: String,
        displayScale: Double = 1
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.themeSubheadline)
                    .foregroundStyle(Color.themeTextSecondary)
                Spacer()
                Text("\(Int((value.wrappedValue * displayScale).rounded()))\(unit)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color.themeTextSecondary)
            }
            Slider(value: value, in: range)
        }
    }

    private func fontPreview(_ name: String) -> Font {
        UIFont(name: name, size: 16) != nil ? Font.custom(name, size: 16) : Font.system(size: 16, design: .rounded)
    }

    // MARK: - Bindings

    /// A write-through binding that streams each edit out via `onChange`.
    private func binding<Value>(_ keyPath: WritableKeyPath<TextOverlay, Value>) -> Binding<Value> {
        Binding(
            get: { overlay[keyPath: keyPath] },
            set: { newValue in update { $0[keyPath: keyPath] = newValue } }
        )
    }

    private var alignmentBinding: Binding<TextOverlay.Alignment> {
        Binding(
            get: { overlay.alignment },
            set: { newValue in update { $0.alignment = newValue } }
        )
    }

    private var customColorBinding: Binding<Color> {
        Binding(
            get: { Color(uiColor: UIColor(hex: overlay.colorHex)) },
            set: { newValue in update { $0.colorHex = UIColor(newValue).hexStringRGB } }
        )
    }

    private func update(_ mutate: (inout TextOverlay) -> Void) {
        mutate(&overlay)
        onChange(overlay)
    }
}
