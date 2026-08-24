//
//  PersonalSticker.swift
//  Caroullage
//
//  Step 05 batch B — a sticker the user made by lifting a subject out of one of
//  their own photos.
//
//  Stored as its own SwiftData record rather than inside a project, because the
//  point of the workflow is reuse: a subject lifted while editing one collage
//  should appear in the sticker picker for every later one. Projects reference it
//  by `id` through `StickerOverlay.imageID`.
//
//  The PNG bytes live on the record (subjects are small — a trimmed cut-out, not
//  a photo) so a personal sticker survives the source photo being deleted from
//  the library, which is the same durability rule Step 04 applied to video clips.
//

import Foundation
import SwiftData

@Model
public final class PersonalSticker {

    /// Matches `StickerOverlay.imageID`.
    @Attribute(.unique) public var id: UUID

    /// PNG, so the lifted subject's alpha survives. External storage keeps the
    /// bytes out of the SwiftData row and off the query path.
    @Attribute(.externalStorage) public var imageData: Data

    public var createdAt: Date

    public init(id: UUID = UUID(), imageData: Data, createdAt: Date = Date()) {
        self.id = id
        self.imageData = imageData
        self.createdAt = createdAt
    }
}
