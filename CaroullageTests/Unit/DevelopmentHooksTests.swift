//
//  DevelopmentHooksTests.swift
//  CaroullageTests
//
//  Pre-submission. The simulator, the UI tests and the screenshot pipeline
//  drive the app through launch arguments and preference keys — one of which
//  unlocks Premium. A customer cannot pass a launch argument, but anyone who
//  edits the app's preferences file (a restored backup, a jailbroken phone)
//  can set a key, so a hook compiled into the App Store build is a paywall
//  bypass rather than a curiosity.
//
//  Tests only ever run a Debug build, so they cannot watch a Release build
//  ignore the hooks. They check the source instead: every hook key lives in
//  `DevelopmentHooks.swift` and nowhere else, and there only inside
//  `#if DEBUG`. A new hook added anywhere else fails here.
//

import Foundation
import XCTest
@testable import Caroullage

final class DevelopmentHooksTests: XCTestCase {

    /// The quoted forms the hooks use in code. Doc comments name them in
    /// backticks, which is why only the quoted form counts. (`deepLink` is not
    /// listed: it is also the reminder notification's real userInfo key. Its
    /// launch-argument form is read only behind `-UITestMode`, which is.)
    private static let hookPatterns = [#""-UITestMode""#, #""-ScreenshotMode""#, #""debug."#]

    private static let hooksFile = "DevelopmentHooks.swift"

    func testNoHookIsReadOutsideTheHooksFile() throws {
        var offenders: [String] = []
        for (path, source) in try appSources() where !path.hasSuffix("/" + Self.hooksFile) {
            for (number, line) in source.components(separatedBy: .newlines).enumerated()
            where !Self.isComment(line) && Self.hookPatterns.contains(where: line.contains) {
                offenders.append("\(path.components(separatedBy: "/Caroullage/").last ?? path):\(number + 1)")
            }
        }
        XCTAssertEqual(offenders, [], "read these through DevelopmentHooks so Release compiles them out")
    }

    func testEveryHookIsCompiledOnlyIntoDebugBuilds() throws {
        let sources = try appSources()
        let source = try XCTUnwrap(sources.first { $0.path.hasSuffix("/" + Self.hooksFile) }?.source,
                                   "\(Self.hooksFile) exists")
        var hooksSeen = 0
        // A stack of "is this branch Debug-only?" for nested #if blocks.
        var debugOnly: [Bool] = []
        for (number, line) in source.components(separatedBy: .newlines).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#if") {
                debugOnly.append(trimmed == "#if DEBUG")
            } else if trimmed.hasPrefix("#else") || trimmed.hasPrefix("#elseif") {
                if !debugOnly.isEmpty { debugOnly[debugOnly.count - 1] = false }
            } else if trimmed.hasPrefix("#endif") {
                _ = debugOnly.popLast()
            } else if !Self.isComment(line) && Self.hookPatterns.contains(where: line.contains) {
                hooksSeen += 1
                XCTAssertTrue(debugOnly.contains(true),
                              "\(Self.hooksFile):\(number + 1) reads a hook outside #if DEBUG")
            }
        }
        XCTAssertGreaterThanOrEqual(hooksSeen, 4, "every hook is declared in \(Self.hooksFile)")
    }

    // MARK: - Debug builds keep the hooks working

    func testThePremiumOverrideStillWorksInDebug() {
        let defaults = UserDefaults(suiteName: "DevelopmentHooksTests")!
        defer { defaults.removePersistentDomain(forName: "DevelopmentHooksTests") }
        XCTAssertFalse(DevelopmentHooks.isPremiumOverridden(in: defaults))
        defaults.set(true, forKey: "debug.premiumUnlocked")
        XCTAssertTrue(DevelopmentHooks.isPremiumOverridden(in: defaults))
    }

    // MARK: - Helpers

    private static func isComment(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
    }

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Unit
            .deletingLastPathComponent()   // CaroullageTests
            .deletingLastPathComponent()   // repo root
    }

    /// Every Swift source in the app and widget targets, with its path.
    private func appSources() throws -> [(path: String, source: String)] {
        var sources: [(String, String)] = []
        for target in ["Caroullage", "CaroullageWidgets"] {
            let root = Self.repoRoot.appendingPathComponent(target)
            let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension == "swift" else { continue }
                sources.append((url.path, try String(contentsOf: url, encoding: .utf8)))
            }
        }
        XCTAssertGreaterThan(sources.count, 100, "the source scan found the app")
        return sources
    }
}
