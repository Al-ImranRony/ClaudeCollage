//
//  TemplateStyleDecorationTests.swift
//  CaroullageTests
//
//  2026-11-21 — styled templates and decorations: they parse defensively,
//  persist without disturbing older projects, and — the point of the design —
//  the gallery preview and the opened project lay out the same picture.
//

import XCTest
@testable import Caroullage

@MainActor
final class TemplateStyleDecorationTests: XCTestCase {

    private let styledJSON = #"""
    {"id":"styled","name":"Styled","category":"instant","isPremium":false,"canvasAspectRatio":"1:1",
     "style":{"spacing":20,"cornerRadius":30,"outerMargin":40,"shadow":0.5,"outlineWidth":6,"outlineHex":"#000000"},
     "decorations":[{"frame":{"x":0.1,"y":0.1,"width":0.5,"height":0.5},"color":"#FFFFFFCC","cornerRadius":0.01,"shadow":0.4},
                    {"frame":{"x":0.8,"y":0.8,"width":0.5,"height":0.5},"shape":"ellipse"}],
     "cells":[{"id":"a","type":"photo","frame":{"x":0,"y":0,"width":0.5,"height":1},"shape":"rectangle"},
              {"id":"b","type":"photo","frame":{"x":0.5,"y":0,"width":0.5,"height":1},"shape":"rectangle"}],
     "background":{"type":"solid","color":"#EEEEEE"}}
    """#

    private func styled() throws -> CollageTemplate {
        try TemplateParser().parse(data: Data(styledJSON.utf8))
    }

    func testStyleAndDecorationsParse() throws {
        let template = try styled()
        let style = try XCTUnwrap(template.style)
        XCTAssertEqual(style.spacing, 20)
        XCTAssertEqual(style.cornerRadius, 30)
        XCTAssertEqual(style.frameStyle, FrameStyle(outerMargin: 40, shadow: 0.5, outlineWidth: 6, outlineHex: "#000000"))

        XCTAssertEqual(template.decorations.count, 2)
        XCTAssertEqual(template.decorations[0].colorHex, "#FFFFFFCC", "the JSON's `color` spelling is read")
        XCTAssertEqual(template.decorations[0].shadow, 0.4)
        XCTAssertEqual(template.decorations[1].shape, .ellipse)
        XCTAssertEqual(template.decorations[1].frame.maxX, 1, accuracy: 1e-9,
                       "a decoration is clamped to the canvas like a cell")
        XCTAssertEqual(template.photoCount, 2)
    }

    func testALegacyTemplateHasNoStyleAndNoDecorations() throws {
        let json = ##"{"id":"l","name":"L","category":"grid","isPremium":false,"canvasAspectRatio":"1:1","cells":[],"background":{"type":"solid","color":"#FFFFFF"}}"##
        let template = try TemplateParser().parse(data: Data(json.utf8))
        XCTAssertNil(template.style)
        XCTAssertTrue(template.decorations.isEmpty)
    }

    func testAMalformedStyleDegradesInsteadOfFailingTheTemplate() throws {
        let json = ##"{"id":"m","name":"M","category":"grid","isPremium":false,"canvasAspectRatio":"1:1","style":"oops","decorations":7,"cells":[],"background":{"type":"solid","color":"#FFFFFF"}}"##
        let template = try TemplateParser().parse(data: Data(json.utf8))
        XCTAssertNil(template.style)
        XCTAssertTrue(template.decorations.isEmpty)
    }

    // MARK: - Persistence

    func testDecorationsRoundTripThroughTheSavedState() throws {
        let template = try styled()
        let state = GridEditorState(layout: .template(TemplateService.editorLayout(for: template)),
                                    decorations: template.decorations)
        let decoded = try JSONDecoder().decode(GridEditorState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded.decorations, template.decorations)
    }

    /// Decorations are drawn for the template's own cells. Switching layout
    /// drops them rather than leaving print cards where no cell is; keeping
    /// the same layout leaves them alone.
    func testSwitchingLayoutDropsTheTemplatesDecorations() throws {
        let template = try styled()
        XCTAssertFalse(template.decorations.isEmpty, "the fixture is decorated")
        var state = GridEditorState(layout: .template(TemplateService.editorLayout(for: template)),
                                    decorations: template.decorations)

        state.applyLayout(state.layout)
        XCTAssertEqual(state.decorations, template.decorations, "re-applying the same layout keeps them")

        state.applyLayout(.grid(.twoUpHorizontal))
        XCTAssertTrue(state.decorations.isEmpty, "a different layout drops them")
    }

    func testAPlainCollageSavesNoDecorationsKeyAndOlderBlobsDecodeEmpty() throws {
        let data = try JSONEncoder().encode(GridEditorState())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["decorations"], "a collage without decorations writes the blob it always wrote")
        XCTAssertTrue(try JSONDecoder().decode(GridEditorState.self, from: data).decorations.isEmpty)
    }

    // MARK: - Preview == project

    func testTheStyledPreviewLaysOutTheSameCellsTheEditorOpens() throws {
        let template = try styled()
        let style = try XCTUnwrap(template.style)
        let maxDimension: CGFloat = 540
        let request = TemplateService(bundle: Bundle(for: CollageRenderer.self))
            .renderRequest(for: template, maxDimension: maxDimension)

        let canvas = CanvasSize.size(forAspectRatio: template.canvasAspectRatio)
        let viewModel = GridEditorViewModel(
            canvasSize: canvas,
            state: GridEditorState(
                layout: .template(TemplateService.editorLayout(for: template)),
                borderWidth: style.spacing, cornerRadius: style.cornerRadius,
                frameStyle: style.frameStyle, decorations: template.decorations))
        let editor = viewModel.exportRequest()

        let scale = maxDimension / max(canvas.width, canvas.height)
        XCTAssertEqual(request.cells.count, editor.cells.count)
        for (preview, project) in zip(request.cells, editor.cells) {
            XCTAssertEqual(preview.frame.minX, project.frame.minX * scale, accuracy: 0.5)
            XCTAssertEqual(preview.frame.minY, project.frame.minY * scale, accuracy: 0.5)
            XCTAssertEqual(preview.frame.width, project.frame.width * scale, accuracy: 0.5)
            XCTAssertEqual(preview.cornerRadius, project.cornerRadius * scale, accuracy: 0.01)
        }
        XCTAssertEqual(request.decorations, editor.decorations)
        XCTAssertEqual(request.frameStyle.shadow, editor.frameStyle.shadow)
        XCTAssertEqual(request.frameStyle.outlineWidth, editor.frameStyle.outlineWidth * Double(scale), accuracy: 0.001)

        // The gap is really there: margin on the outside, spacing between.
        let first = try XCTUnwrap(request.cells.first?.frame)
        XCTAssertEqual(first.minX, 40 * scale, accuracy: 0.5)
        XCTAssertEqual(request.cells[1].frame.minX - first.maxX, 20 * scale, accuracy: 0.5)
    }

    func testTheContentFingerprintMovesWithStyleAndDecorations() throws {
        let base = try styled()
        let restyled = try TemplateParser().parse(data: Data(styledJSON.replacingOccurrences(
            of: #""spacing":20"#, with: #""spacing":24"#).utf8))
        let redecorated = try TemplateParser().parse(data: Data(styledJSON.replacingOccurrences(
            of: "#FFFFFFCC", with: "#000000CC").utf8))
        let print = TemplateService.contentFingerprint(of:)
        XCTAssertNotEqual(print(base), print(restyled))
        XCTAssertNotEqual(print(base), print(redecorated))
    }

    func testDecorationsPaintBetweenTheBackgroundAndTheCells() throws {
        // A black card on a white ground, no cells: the card's centre is black,
        // outside it stays white. Proves the renderer draws decorations at all.
        let request = RenderRequest(
            canvasSize: CGSize(width: 100, height: 100), background: .white, cells: [],
            decorations: [CanvasDecoration(frame: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
                                           colorHex: "#000000")])
        let image = try XCTUnwrap(CollageRenderer().render(request, scale: 1))
        XCTAssertLessThan(try luminance(of: image, at: CGPoint(x: 50, y: 50)), 0.05)
        XCTAssertGreaterThan(try luminance(of: image, at: CGPoint(x: 10, y: 10)), 0.95)
    }

    private func luminance(of image: CGImage, at point: CGPoint) throws -> Double {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let scaleX = CGFloat(image.width) / 100, scaleY = CGFloat(image.height) / 100
        context.draw(image, in: CGRect(x: -point.x * scaleX, y: -(CGFloat(image.height) - point.y * scaleY),
                                       width: CGFloat(image.width), height: CGFloat(image.height)))
        return (Double(pixel[0]) + Double(pixel[1]) + Double(pixel[2])) / (3 * 255)
    }
}
