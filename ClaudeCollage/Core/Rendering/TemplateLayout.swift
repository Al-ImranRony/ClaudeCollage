//
//  TemplateLayout.swift
//  ClaudeCollage
//
//  Step 03a slice 3 — the geometry a standard template contributes to the
//  editor: just its photo cells' normalized frames and clip shapes. This is the
//  `.template` payload of `CollageLayout`, so the whole existing editor stack
//  (undo, autosave, photo import, filters, export) drives arbitrary template
//  layouts with no duplicated machinery.
//
//  Deliberately NOT the full `CollageTemplate`: text/sticker/art zones are
//  editor overlays (later 03a slices), and keeping the layout payload small
//  keeps `GridEditorState` snapshots (the undo unit) cheap to copy and encode.
//

import CoreGraphics
import Foundation

/// One photo cell of a template, in normalized (0…1) canvas coordinates.
public struct TemplateLayoutCell: Equatable, Sendable, Codable {
    public let frame: CGRect
    public let clip: CellClipShape

    public init(frame: CGRect, clip: CellClipShape = .rectangle) {
        self.frame = frame
        self.clip = clip
    }
}

/// The editable geometry of a standard template.
public struct TemplateLayout: Equatable, Sendable, Codable {
    public let templateID: String
    public let name: String
    /// The authored "w:h" ratio — drives the project's canvas size.
    public let aspectRatio: String
    public let cells: [TemplateLayoutCell]

    public init(templateID: String, name: String, aspectRatio: String, cells: [TemplateLayoutCell]) {
        self.templateID = templateID
        self.name = name
        self.aspectRatio = aspectRatio
        self.cells = cells
    }
}
