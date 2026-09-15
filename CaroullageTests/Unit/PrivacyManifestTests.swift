//
//  PrivacyManifestTests.swift
//  CaroullageTests
//
//  Step 06 phase 6.6. The privacy manifest and the Info.plist as App Review
//  reads them — from the BUILT app bundle, not the source files, so a manifest
//  that XcodeGen forgot to copy, or a plist key that did not survive
//  generation, fails here rather than at submission.
//
//  The manifest's Required Reason API declarations are also checked against
//  the source: an API family that appears in the code must be declared, and a
//  declared family must appear in the code. App Review rejects both — the
//  first as an undeclared use, the second as an incorrect declaration.
//

import Foundation
import XCTest
@testable import Caroullage

final class PrivacyManifestTests: XCTestCase {

    // MARK: - The built manifest

    private func manifest() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
                                "PrivacyInfo.xcprivacy is not in the app bundle")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    func testTheAppDoesNotTrackAndCollectsNoData() throws {
        let manifest = try manifest()
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((manifest["NSPrivacyTrackingDomains"] as? [Any])?.count, 0)
        XCTAssertEqual((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.count, 0,
                       "no analytics SDK, no account, no collected data — a declaration here is a new decision")
    }

    func testUserDefaultsIsDeclaredWithTheAppsOwnSettingsReason() throws {
        let declared = try declaredAPIReasons()
        XCTAssertEqual(declared["NSPrivacyAccessedAPICategoryUserDefaults"], ["CA92.1"],
                       "UserDefaults holds the app's own settings (onboarding, credits, offer cooldown)")
    }

    // MARK: - Declarations against the code

    /// The API families Apple requires a reason for, and the source patterns
    /// that mean the family is in use. Each family is either declared and
    /// used, or neither.
    private static let requiredReasonFamilies: [(category: String, patterns: [String])] = [
        ("NSPrivacyAccessedAPICategoryUserDefaults", ["UserDefaults", "@AppStorage"]),
        ("NSPrivacyAccessedAPICategoryFileTimestamp",
         [".creationDateKey", ".contentModificationDateKey", "attributesOfItem(atPath", ".fileModificationDate", ".fileCreationDate", "stat("]),
        ("NSPrivacyAccessedAPICategoryDiskSpace",
         ["volumeAvailableCapacity", ".systemFreeSize", "statfs("]),
        ("NSPrivacyAccessedAPICategorySystemBootTime",
         ["systemUptime", "mach_absolute_time", "sysctl("]),
        ("NSPrivacyAccessedAPICategoryActiveKeyboards", ["activeInputModes"]),
    ]

    func testEveryRequiredReasonAPIInTheCodeIsDeclaredAndNothingElseIs() throws {
        let declared = try declaredAPIReasons()
        let sources = try appSources()
        for family in Self.requiredReasonFamilies {
            let used = sources.contains { source in family.patterns.contains { source.contains($0) } }
            let isDeclared = declared[family.category] != nil
            XCTAssertEqual(used, isDeclared,
                           "\(family.category): used in code = \(used), declared = \(isDeclared)")
        }
    }

    // MARK: - Info.plist, as built

    func testEncryptionExportComplianceIsAnsweredInThePlist() {
        // Standard encryption only (HTTPS, StoreKit). With this key the App
        // Store Connect export-compliance question is answered per build.
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "ITSAppUsesNonExemptEncryption") as? Bool, false)
    }

    func testOnlyThePermissionsTheAppUsesHaveAUsageString() {
        let info = Bundle.main.infoDictionary ?? [:]
        for key in ["NSPhotoLibraryUsageDescription",      // RecentPhotoProvider reads the library
                    "NSPhotoLibraryAddUsageDescription",   // exports save to Photos
                    "NSCameraUsageDescription"] {          // the camera door on Start Editing
            let value = info[key] as? String ?? ""
            XCTAssertFalse(value.isEmpty, "\(key) is missing or empty")
        }
        // No audio is captured anywhere; a string for it would prompt Review to
        // ask why, and the OS to offer a permission the app never uses.
        XCTAssertNil(info["NSMicrophoneUsageDescription"])
    }

    func testTheUsageStringsAreLocalizedIntoEveryShippingLanguage() throws {
        let catalog = try infoPlistCatalog()
        let shipping = ["en", "es", "fr", "de", "pt-BR", "ja", "ko", "zh-Hans", "hi", "it", "ar"]
        for key in ["NSPhotoLibraryUsageDescription", "NSPhotoLibraryAddUsageDescription", "NSCameraUsageDescription"] {
            let entry = try XCTUnwrap(catalog[key] as? [String: Any], "InfoPlist.xcstrings lacks \(key)")
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            for language in shipping {
                let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                let value = unit?["value"] as? String ?? ""
                XCTAssertFalse(value.trimmingCharacters(in: .whitespaces).isEmpty, "\(language) is missing for \(key)")
            }
        }
    }

    // MARK: - Helpers

    private func declaredAPIReasons() throws -> [String: [String]] {
        let types = try manifest()["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []
        var result: [String: [String]] = [:]
        for type in types {
            guard let category = type["NSPrivacyAccessedAPIType"] as? String else { continue }
            result[category] = type["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? []
        }
        return result
    }

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Unit
            .deletingLastPathComponent()   // CaroullageTests
            .deletingLastPathComponent()   // repo root
    }

    /// Every Swift source in the app and widget targets.
    private func appSources() throws -> [String] {
        var sources: [String] = []
        for target in ["Caroullage", "CaroullageWidgets"] {
            let root = Self.repoRoot.appendingPathComponent(target)
            let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension == "swift" else { continue }
                sources.append(try String(contentsOf: url, encoding: .utf8))
            }
        }
        XCTAssertGreaterThan(sources.count, 100, "the source scan found the app")
        return sources
    }

    private func infoPlistCatalog() throws -> [String: Any] {
        let url = Self.repoRoot.appendingPathComponent("Caroullage/Resources/InfoPlist.xcstrings")
        let data = try Data(contentsOf: url)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(root["strings"] as? [String: Any])
    }
}
