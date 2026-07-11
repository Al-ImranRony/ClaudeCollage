//
//  UndoStack.swift
//  ClaudeCollage
//
//  Step 01 — a bounded snapshot-based undo/redo stack.
//
//  Generic over any snapshot value type. The grid editor drives it with a
//  `GridEditorState` value snapshot; the tests drive it with `Int`. Holds at
//  most `maxDepth` snapshots (default 20 per the plan); the oldest is dropped
//  when the limit is exceeded.
//

import Foundation

/// A linear undo/redo history of value snapshots.
///
/// `push` truncates any redo history (standard editor behaviour: making a new
/// edit after undoing discards the redo branch). `undo`/`redo` move a cursor
/// over the retained snapshots and return the snapshot moved to (or `nil` at
/// the ends).
public final class UndoStack<Element> {

    public let maxDepth: Int
    private var history: [Element] = []
    private var cursor: Int = -1

    public init(maxDepth: Int = 20) {
        self.maxDepth = max(1, maxDepth)
    }

    /// The snapshot currently pointed at, or `nil` if the stack is empty.
    public var current: Element? {
        history.indices.contains(cursor) ? history[cursor] : nil
    }

    public var canUndo: Bool { cursor > 0 }
    public var canRedo: Bool { cursor < history.count - 1 }
    public var count: Int { history.count }

    /// Records a new snapshot as the current state. Drops the oldest snapshot
    /// if the depth limit is exceeded.
    public func push(_ state: Element) {
        // Discard any redo branch ahead of the cursor before appending.
        if cursor < history.count - 1 {
            history.removeSubrange((cursor + 1)...)
        }
        history.append(state)
        if history.count > maxDepth {
            history.removeFirst(history.count - maxDepth)
        }
        cursor = history.count - 1
    }

    /// Moves back one snapshot and returns it, or `nil` if already at the start.
    @discardableResult
    public func undo() -> Element? {
        guard canUndo else { return nil }
        cursor -= 1
        return history[cursor]
    }

    /// Moves forward one snapshot and returns it, or `nil` if already at the end.
    @discardableResult
    public func redo() -> Element? {
        guard canRedo else { return nil }
        cursor += 1
        return history[cursor]
    }

    /// Clears all history.
    public func reset() {
        history.removeAll()
        cursor = -1
    }
}
