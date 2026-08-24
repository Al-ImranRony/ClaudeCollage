//
//  BeatSyncPlanner.swift
//  Caroullage
//
//  Step 04 slice 6c — maps detected beats onto the collage's cells: cell i reveals
//  on the i-th beat, giving a "cells cascade in on the music" effect. Pure value
//  logic, so the mapping is unit-tested without any audio.
//

import Foundation

public enum BeatSyncPlanner {

    /// A transition start time (seconds) for each of `cellCount` cells.
    ///
    /// Beats are sorted and clamped to those inside `duration`; cell i takes the
    /// i-th such beat. With fewer beats than cells the remaining cells reuse the
    /// last beat (they reveal together on the final downbeat); with no usable beats
    /// every cell starts at 0 (reveal immediately).
    public static func startTimes(cellCount: Int, beats: [Double], within duration: Double) -> [Double] {
        guard cellCount > 0 else { return [] }
        let usable = beats.filter { $0 >= 0 && $0 < duration }.sorted()
        guard !usable.isEmpty else { return Array(repeating: 0, count: cellCount) }
        return (0 ..< cellCount).map { usable[min($0, usable.count - 1)] }
    }
}
