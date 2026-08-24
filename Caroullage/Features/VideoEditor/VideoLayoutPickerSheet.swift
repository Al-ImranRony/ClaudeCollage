//
//  VideoLayoutPickerSheet.swift
//  Caroullage
//
//  The video editor's layout picker, presented as a `UISheetPresentationController`
//  sheet (see `VideoEditorViewController.layoutTapped`). Replaces a plain text
//  action sheet ("2 · Side", "4 · Grid" …) with a grid of schematic thumbnails —
//  the same visual language `LayoutSchematicCell` already draws for the photo
//  grid editor's picker — so choosing a layout is recognition, not label-reading.
//

import SwiftUI

struct VideoLayoutPickerSheet: View {

    let templates: [GridTemplate]
    let selected: GridTemplate
    let onSelect: (GridTemplate) -> Void
    let onClose: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 80), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(templates, id: \.self) { template in
                        Button {
                            onSelect(template)
                            onClose()
                        } label: {
                            VStack(spacing: 8) {
                                LayoutSchematicShape(template: template, isSelected: template == selected)
                                    .frame(width: 64, height: 64)
                                Text(template.displayName)
                                    .font(.themeCaption)
                                    .foregroundStyle(
                                        template == selected
                                            ? Color(Theme.Color.accent)
                                            : Color(Theme.Color.textSecondary))
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("videoLayoutOption-\(template.rawValue)")
                    }
                }
                .padding(20)
            }
            .background(Color(Theme.Color.background).ignoresSafeArea())
            .navigationTitle("Layout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onClose() }
                }
            }
        }
    }
}

/// Draws the same cell-pattern schematic as `LayoutSchematicCell`, in SwiftUI.
/// Uses `Canvas` rather than a `ZStack`/`ForEach` of shapes — the latter blows up
/// the type-checker on this many overlapping modifiers.
private struct LayoutSchematicShape: View {
    let template: GridTemplate
    let isSelected: Bool

    var body: some View {
        Canvas { context, size in
            let backgroundPath = Path(
                roundedRect: CGRect(origin: .zero, size: size),
                cornerRadius: Theme.Radius.sm, style: .continuous)
            context.fill(backgroundPath, with: .color(fillColor))
            context.stroke(backgroundPath, with: .color(borderColor), lineWidth: 2)

            let cellColor = Color(Theme.Color.accent).opacity(0.7)
            for cell in template.normalizedCells {
                let rect = CGRect(
                    x: cell.minX * size.width + 4,
                    y: cell.minY * size.height + 4,
                    width: max(cell.width * size.width - 8, 1),
                    height: max(cell.height * size.height - 8, 1))
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(cellColor))
            }
        }
    }

    private var fillColor: Color {
        Color(isSelected ? Theme.Color.accentSoft : Theme.Color.controlFill)
    }

    private var borderColor: Color {
        Color(isSelected ? Theme.Color.accent : Theme.Color.separator)
    }
}
