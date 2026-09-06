//
//  VideoTimelineModelBuilder.swift
//  Caroullage
//
//  Task 7 — turns the document into the timeline's view model.
//
//  Pure, and deliberately separate from both the view and the view model: this is
//  where the arithmetic lives (which cell is a lane, how long it is once its trim
//  is resolved against the source, where a caption's pill sits when its window is
//  open-ended), and that arithmetic is worth testing without a screen attached.
//  Same split as `VideoTimelineGeometry` and `EditorStageGeometry`.
//
//  Two conventions that are easy to get wrong:
//
//  • A lane's length is its TRIMMED length, never the source's. The lane's edges
//    are the trim handles, so if the two disagreed, grabbing an edge would make
//    the block jump before it moved.
//  • A clip's lane starts at its `startOffset`. Cells otherwise play
//    SIMULTANEOUSLY in separate regions of one canvas — this is a collage, not a
//    sequential edit — so without an offset every lane begins at zero.
//  • Lane times are COMPOSITION time; a `VideoTrim` is SOURCE time. They are not
//    interchangeable, and the owner converts between them — see
//    `VideoEditorViewController.trimFromTimeline`.
//

import Foundation

public enum VideoTimelineModelBuilder {

    /// - Parameters:
    ///   - sourceDurations: resolved source lengths in seconds, keyed by cell
    ///     index. Loading an `AVAsset`'s duration is async, so a cell is simply
    ///     absent from this until its load lands — and an absent cell reports a
    ///     zero-length lane rather than inventing a length it cannot know.
    public static func make(
        cells: [VideoCellState],
        sourceDurations: [Int: Double],
        textOverlays: [TextOverlay],
        hasMusic: Bool = false,
        selectedClipIndex: Int? = nil,
        selectedTextID: UUID? = nil,
        isPlaying: Bool = false
    ) -> VideoTimelineModel {

        let clips = cells.enumerated().map { index, cell in
            let isFilled = cell.videoID != nil
            return VideoTimelineModel.Clip(
                index: index,
                start: isFilled ? max(0, cell.startOffset) : 0,
                duration: laneDuration(of: cell, source: sourceDurations[index]),
                isFilled: isFilled)
        }

        // The same rule the engine uses, so the timeline's ruler and the real
        // composition cannot disagree: it runs until the LAST cell finishes,
        // which with offsets is not the longest one.
        let duration = VideoCompositionMath.compositionDuration(
            cellSpans: clips.filter(\.isFilled).map { ($0.start, $0.duration) })

        let pills = textOverlays.map { overlay in
            // `nil` timing means "always visible" (`TextOverlay.isVisible`), which
            // on a timeline has to read as a pill covering everything rather than
            // a zero-width one stuck at the origin.
            VideoTimelineModel.TextPill(
                id: overlay.id,
                label: overlay.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Text" : overlay.text,
                start: overlay.startTime ?? 0,
                end: overlay.endTime ?? duration)
        }

        return VideoTimelineModel(
            duration: duration,
            clips: clips,
            textPills: pills,
            musicTitle: hasMusic ? "Music" : nil,
            selectedClipIndex: selectedClipIndex,
            selectedTextID: selectedTextID,
            isPlaying: isPlaying)
    }

    /// An empty slot contributes no length. A filled one contributes its trim
    /// resolved against the source — which is what turns the default "unset"
    /// trim (`end == 0`, meaning "to the end") into a real length.
    private static func laneDuration(of cell: VideoCellState, source: Double?) -> Double {
        guard cell.videoID != nil else { return 0 }
        guard let source, source > 0 else { return cell.trim.duration }
        return cell.trim.clamped(toAssetDuration: source).duration
    }
}
