//
//  ScreenshotCaptionTests.swift
//  CaroullageTests
//
//  Pre-submission. The captions `Tools/ScreenshotFramer` sets over the App
//  Store screenshots are product-page metadata, and App Review holds metadata
//  to guideline 2.3.7 and 5.2.1: no other company's trademark in the
//  screenshots' marketing copy. Inside the app, naming a platform an export is
//  sized for ("Instagram 4:5") is a functional description and stays; a
//  caption selling the app as an "Instagram carousel" maker is not.
//

import Foundation
import XCTest

final class ScreenshotCaptionTests: XCTestCase {

    /// Brands a caption could plausibly lean on. Matched case-insensitively,
    /// in every language (the names are not translated).
    private static let thirdPartyNames = [
        "instagram", "tiktok", "reels", "facebook", "snapchat", "youtube", "pinterest",
        "canva", "scrl", "unfold",
    ]

    func testNoCaptionNamesAnotherCompanysProduct() throws {
        var offenders: [String] = []
        for (scene, byLanguage) in try captions() {
            for (language, caption) in byLanguage {
                let lowered = caption.lowercased()
                for name in Self.thirdPartyNames where lowered.contains(name) {
                    offenders.append("\(scene) [\(language)] names \"\(name)\"")
                }
            }
        }
        XCTAssertEqual(offenders, [])
    }

    func testEverySceneIsCaptionedInEveryShippingLanguage() throws {
        let languages: Set = ["en", "es", "fr", "de", "pt-BR", "ja", "ko", "zh-Hans", "hi", "it", "ar"]
        for (scene, byLanguage) in try captions() {
            XCTAssertEqual(Set(byLanguage.keys), languages, "\(scene)")
            for (language, caption) in byLanguage {
                XCTAssertFalse(caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                               "\(scene) [\(language)] is empty")
            }
        }
    }

    // MARK: - Helpers

    private func captions() throws -> [String: [String: String]] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Unit
            .deletingLastPathComponent()   // CaroullageTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Marketing/Screenshots/captions.json")
        let data = try Data(contentsOf: url)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var result: [String: [String: String]] = [:]
        for (scene, value) in root {
            result[scene] = try XCTUnwrap(value as? [String: String], "\(scene) is a language → caption map")
        }
        XCTAssertFalse(result.isEmpty)
        return result
    }
}
