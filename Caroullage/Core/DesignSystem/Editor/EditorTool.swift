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

    /// How a tool's icon moves while that tool is the selected one.
    ///
    /// The rail plays a REPEATING SF Symbol effect on the active tool and on
    /// nothing else, so the strip always has exactly one thing moving in it and
    /// that thing is the answer to "where am I". Which effect is per tool
    /// because the symbols are not interchangeable: a symbol whose meaning lives
    /// in its secondary layers (the dots behind `person.and.background.dotted`,
    /// the rays of `wand.and.rays`) says something when those layers cycle,
    /// where a solid glyph like `trash` has no layers to cycle and has to move
    /// as a whole instead.
    ///
    /// Named for the intent rather than for the UIKit effect so this file stays
    /// what its header claims — a value type with no UIKit in it. `ToolButton`
    /// is where these become `SymbolEffect`s, and where the two that need iOS 18
    /// fall back for iOS 17.
    public enum Emphasis: Sendable {
        /// The whole glyph breathes in opacity. The default: it needs no
        /// particular structure from the symbol, so it is never wrong, and it is
        /// quiet enough to sit under a label without competing with it.
        case pulse
        /// A discrete hop, repeated. For symbols that read as an object being
        /// acted on rather than as a process.
        case bounce
        /// The glyph slides back and forth. For tools that ARE a motion —
        /// swapping, trimming, erasing — where the icon miming the gesture is
        /// the whole point. iOS 18+; falls back to `bounce`.
        case wiggle
        /// The symbol's layers fill in sequence. Only for symbols built in
        /// layers that mean something in order: waves, rays, bars.
        case variableColor
        /// The glyph spins about its own centre. For symbols with a natural
        /// axis. iOS 18+; falls back to `bounce`.
        case rotate
    }

    public let id: ID
    public let title: String
    /// SF Symbol name.
    public let systemImage: String
    /// Preserved across the redesign so existing XCUITests keep matching.
    public let accessibilityIdentifier: String
    /// How this tool's icon animates while it is the active tool.
    public let emphasis: Emphasis

    /// `emphasis` defaults to `.pulse` rather than being required at every call
    /// site: it is the one effect that suits any symbol, so a tool added later
    /// animates correctly without its author having to think about it, and only
    /// the tools whose symbol earns something better have to say so.
    public init(
        id: ID,
        title: String,
        systemImage: String,
        accessibilityIdentifier: String,
        emphasis: Emphasis = .pulse
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.accessibilityIdentifier = accessibilityIdentifier
        self.emphasis = emphasis
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
