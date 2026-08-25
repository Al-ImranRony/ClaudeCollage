//
//  LocalizationTests.swift
//  CaroullageTests
//
//  Step 06 phase 6.4 — the 11 day-one languages.
//
//  Two things can go wrong with a String Catalog and neither shows up in a
//  build: a key can be missing a language, and a translation can quietly drop a
//  format specifier — which crashes at runtime the moment the string is used
//  with an argument. Both are checked here against the catalog in the source
//  tree, and the compiled result is checked against the app bundle.
//

import XCTest
@testable import Caroullage

final class LocalizationTests: XCTestCase {

    /// The languages the app ships on day one.
    private static let shipping = [
        "en", "es", "fr", "de", "pt-BR", "ja", "ko", "zh-Hans", "hi", "it", "ar",
    ]

    private func catalog(named name: String, in directory: String) throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Unit
            .deletingLastPathComponent()   // CaroullageTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent(directory)
            .appendingPathComponent("\(name).xcstrings")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "source tree not available")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return try XCTUnwrap(json as? [String: Any])
    }

    private func strings(_ catalog: [String: Any]) throws -> [String: [String: Any]] {
        try XCTUnwrap(catalog["strings"] as? [String: [String: Any]])
    }

    private func value(_ entry: [String: Any], language: String) -> String? {
        guard
            let localizations = entry["localizations"] as? [String: Any],
            let localization = localizations[language] as? [String: Any],
            let unit = localization["stringUnit"] as? [String: Any]
        else { return nil }
        return unit["value"] as? String
    }

    // MARK: - Completeness

    func testEveryStringIsTranslatedIntoAllElevenLanguages() throws {
        let entries = try strings(try catalog(named: "Localizable", in: "Caroullage/Resources"))
        XCTAssertFalse(entries.isEmpty)

        for (key, entry) in entries {
            for language in Self.shipping {
                let translation = value(entry, language: language)
                XCTAssertNotNil(translation, "\(language) is missing for \"\(key)\"")
                XCTAssertFalse(
                    (translation ?? "").trimmingCharacters(in: .whitespaces).isEmpty,
                    "\(language) is empty for \"\(key)\""
                )
            }
        }
    }

    func testTheWidgetCarriesItsOwnCatalogBecauseItIsItsOwnBundle() throws {
        let entries = try strings(try catalog(named: "Localizable", in: "CaroullageWidgets"))

        XCTAssertFalse(entries.isEmpty, "the widget extension cannot read the app's catalog")
        for (key, entry) in entries {
            for language in Self.shipping {
                XCTAssertNotNil(value(entry, language: language), "\(language) is missing for \"\(key)\"")
            }
        }
    }

    // MARK: - Format specifiers

    func testEveryTranslationKeepsTheFormatSpecifiersOfItsKey() throws {
        let entries = try strings(try catalog(named: "Localizable", in: "Caroullage/Resources"))

        for (key, entry) in entries {
            let expected = Self.specifierCounts(in: key)
            guard !expected.isEmpty else { continue }

            for language in Self.shipping {
                guard let translation = value(entry, language: language) else { continue }
                XCTAssertEqual(
                    Self.specifierCounts(in: translation), expected,
                    "\(language) changes the arguments of \"\(key)\" — that is a crash, not a typo"
                )
            }
        }
    }

    /// Counts `%@` and `%lld`, with or without a positional prefix like `%1$@`.
    private static func specifierCounts(in text: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        let pattern = try? NSRegularExpression(pattern: "%(?:\\d+\\$)?(@|lld)")
        let range = NSRange(text.startIndex..., in: text)
        pattern?.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match, let kind = Range(match.range(at: 1), in: text) else { return }
            counts[String(text[kind]), default: 0] += 1
        }
        return counts
    }

    // MARK: - The compiled result

    func testTheBuiltAppActuallyContainsTheTranslations() throws {
        let bundle = Bundle(for: CollageRenderer.self)

        for language in Self.shipping {
            let path = bundle.path(forResource: language, ofType: "lproj")
            XCTAssertNotNil(path, "\(language) did not make it into the built app")
        }
    }

    func testAKeyResolvesDifferentlyInADifferentLanguage() throws {
        let bundle = Bundle(for: CollageRenderer.self)
        let spanishPath = try XCTUnwrap(bundle.path(forResource: "es", ofType: "lproj"))
        let spanish = try XCTUnwrap(Bundle(path: spanishPath))

        let key = "Subscribe"
        let translated = spanish.localizedString(forKey: key, value: nil, table: nil)

        XCTAssertEqual(translated, "Suscribirse")
    }

    func testTheRightToLeftLanguageIsShipped() throws {
        let bundle = Bundle(for: CollageRenderer.self)
        let arabicPath = try XCTUnwrap(bundle.path(forResource: "ar", ofType: "lproj"),
                                       "Arabic drives the RTL layout pass")
        let arabic = try XCTUnwrap(Bundle(path: arabicPath))

        XCTAssertEqual(Locale.Language(identifier: "ar").characterDirection, .rightToLeft)
        XCTAssertFalse(arabic.localizedString(forKey: "Continue", value: nil, table: nil).isEmpty)
    }
}
