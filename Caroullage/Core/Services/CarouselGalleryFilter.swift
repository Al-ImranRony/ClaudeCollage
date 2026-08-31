//
//  CarouselGalleryFilter.swift
//  Caroullage
//
//  Step 07 — what the Carousel tab shows, as arithmetic.
//
//  Sibling of `GalleryFilter`, and for the same reason: the narrowing is the
//  part that can be wrong, so it lives outside the view controller where a unit
//  test can pin it without a simulator. The screen's job is then only to draw
//  what this returns.
//
//  Three narrowings compose: canvas ratio (`nil` = any), free text on the
//  template name, and carousel type. Type is last because it also decides the
//  SHAPE of the result — "All" fans out into one section per type, a chosen type
//  collapses to a single unheaded section.
//

import Foundation

enum CarouselGalleryFilter {

    /// One block of the gallery. `type` is `nil` for the collapsed, single-type
    /// view, where a header would only repeat the chip the user just tapped.
    struct Section: Equatable {
        let type: CarouselType?
        let templates: [CarouselTemplate]
    }

    /// The gallery's content, in draw order.
    ///
    /// - Parameters:
    ///   - ratio: `nil` means "Any Ratio", which is the default. Unlike the
    ///     Templates tab — whose catalog is large enough that defaulting to
    ///     Square is reasonable — this catalog has 6 square and exactly 1
    ///     landscape template, so a preset default would hide most of it. It
    ///     would also make every visible card the same shape, which flattens the
    ///     masonry into a plain grid.
    ///   - search: trimmed; empty matches everything.
    static func sections(
        _ templates: [CarouselTemplate],
        type: CarouselType?,
        ratio: CanvasPreset?,
        search: String
    ) -> [Section] {
        var narrowed = templates

        if let ratio {
            narrowed = narrowed.filter {
                CanvasSize.normalize($0.canvasAspectRatio)
                    == CanvasSize.normalize(ratio.aspectRatio)
            }
        }

        let query = search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            narrowed = narrowed.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }

        if let type {
            let matching = ordered(narrowed.filter { $0.carouselType == type })
            return matching.isEmpty ? [] : [Section(type: nil, templates: matching)]
        }

        // `allCases` order — panoramic, matched, scroll-through, grid preview —
        // is the same order the "New Carousel" picker lists them in, so the two
        // screens agree on what comes first.
        return CarouselType.allCases.compactMap { type in
            let matching = ordered(narrowed.filter { $0.carouselType == type })
            return matching.isEmpty ? nil : Section(type: type, templates: matching)
        }
    }

    /// Free templates before premium, then alphabetical — the same stable order
    /// `TemplateService.loadBundledCarouselTemplates()` applies to the catalog
    /// as a whole, restated here because filtering by type re-partitions it.
    private static func ordered(_ templates: [CarouselTemplate]) -> [CarouselTemplate] {
        templates.sorted {
            $0.isPremium == $1.isPremium ? $0.name < $1.name : (!$0.isPremium && $1.isPremium)
        }
    }
}
