//
//  PaywallClaimsTests.swift
//  CaroullageTests
//
//  Pre-submission. Every line the paywall promises is something App Review can
//  check by buying, and the reviewer does: a count the catalog does not reach,
//  or a feature that answers "Coming Soon" after purchase, is a rejection under
//  guidelines 2.3.1 and 3.1.1 — and, once live, a refund request.
//
//  The screenshot captions make the same promises on the product page, so the
//  template count is held against the bundled catalog there too.
//

import Foundation
import XCTest
@testable import Caroullage

@MainActor
final class PaywallClaimsTests: XCTestCase {

    /// Everything the paywall says Premium is: the feature grid and the hero cards.
    private var claims: [String] {
        (PaywallViewModel.features + PaywallViewModel.heroCards).map(\.title)
    }

    /// Collage plus carousel templates — both galleries a buyer can open.
    private func bundledTemplateCount() -> Int {
        let service = TemplateService()
        return service.loadBundledTemplates().count + service.loadBundledCarouselTemplates().count
    }

    func testThePaywallHasSomethingToSay() {
        XCTAssertFalse(PaywallViewModel.features.isEmpty)
        XCTAssertFalse(PaywallViewModel.heroCards.isEmpty)
    }

    func testNoTemplateCountOnThePaywallIsLargerThanTheCatalog() {
        let bundled = bundledTemplateCount()
        XCTAssertGreaterThan(bundled, 0, "the catalog loaded")
        for claim in claims where claim.localizedCaseInsensitiveContains("template") {
            for number in Self.numbers(in: claim) {
                XCTAssertLessThanOrEqual(number, bundled, "\"\(claim)\" promises more templates than the \(bundled) bundled")
            }
        }
    }

    func testThePaywallSellsNoAIFeature() {
        // Premium's one AI entry, generative backgrounds, has no Image Playground
        // sheet behind it yet, and the AI tools that do ship (subject lift, the
        // magic eraser) are free. A paywall line about AI therefore sells
        // something the purchase does not change. When a premium AI feature
        // ships, this test is the place to say so.
        for claim in claims {
            XCTAssertNil(claim.range(of: #"\bAI\b"#, options: .regularExpression),
                         "\"\(claim)\" advertises AI that Premium does not add")
        }
    }

    func testNoScreenshotCaptionPromisesMoreTemplatesThanTheCatalog() throws {
        let bundled = bundledTemplateCount()
        let url = Self.repoRoot.appendingPathComponent("Marketing/Screenshots/captions.json")
        let data = try Data(contentsOf: url)
        let captions = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let templateScenes = captions.filter { $0.key.contains("template") }
        XCTAssertFalse(templateScenes.isEmpty, "the template scene's captions were found")
        for (scene, value) in templateScenes {
            let byLanguage = try XCTUnwrap(value as? [String: String], "\(scene) is a language → caption map")
            for (language, caption) in byLanguage {
                for number in Self.numbers(in: caption) {
                    XCTAssertLessThanOrEqual(number, bundled,
                                             "\(scene) [\(language)] \"\(caption)\" promises more than the \(bundled) bundled")
                }
            }
        }
    }

    // MARK: - Helpers

    private static func numbers(in text: String) -> [Int] {
        text.split(whereSeparator: { !$0.isASCII || !$0.isNumber }).compactMap { Int($0) }
    }

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Unit
            .deletingLastPathComponent()   // CaroullageTests
            .deletingLastPathComponent()   // repo root
    }
}
