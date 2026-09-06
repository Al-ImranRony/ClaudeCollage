//
//  EditorTool.swift
//  Caroullage
//
//  The value types behind `EditorToolRail`. Kept free of UIKit behaviour so the
//  editors can describe their tool sets declaratively and the rail stays a dumb
//  renderer of whatever it is handed.
//

import Foundation

/// One tool in an editor's bottom rail.
public struct EditorTool: Equatable, Identifiable, Sendable {
    public typealias ID = String

    public let id: ID
    public let title: String
    /// SF Symbol name.
    public let systemImage: String
    /// Preserved across the redesign so existing XCUITests keep matching.
    public let accessibilityIdentifier: String

    public init(id: ID, title: String, systemImage: String, accessibilityIdentifier: String) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.accessibilityIdentifier = accessibilityIdentifier
    }
}

/// A contextual tool group inserted ahead of the base tools when something on the
/// canvas is selected. The base tools are never removed — they scroll.
public struct EditorRailContext: Equatable, Sendable {
    public let chipTitle: String
    /// SF Symbol name shown in the dismissible chip.
    public let chipSystemImage: String
    public let tools: [EditorTool]

    public init(chipTitle: String, chipSystemImage: String, tools: [EditorTool]) {
        self.chipTitle = chipTitle
        self.chipSystemImage = chipSystemImage
        self.tools = tools
    }
}
