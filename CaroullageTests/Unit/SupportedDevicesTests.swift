//
//  SupportedDevicesTests.swift
//  CaroullageTests
//
//  Pre-submission. v1 ships for iPhone only (owner's decision, 2026-09-26).
//  No screen was designed for iPad landscape, Split View or Stage Manager, and
//  declaring the iPad family commits the app to all of them — plus iPad
//  screenshots — from the first review onward, because iPad support cannot be
//  withdrawn from a live app. iPads still install it and run the iPhone layout.
//
//  Read from the BUILT plists, where Xcode writes `UIDeviceFamily` from
//  `TARGETED_DEVICE_FAMILY`, so a project.yml edit that did not take fails here.
//

import Foundation
import XCTest
@testable import Caroullage

final class SupportedDevicesTests: XCTestCase {

    private func plist(at url: URL?) throws -> [String: Any] {
        let url = try XCTUnwrap(url, "the plist is in the built product")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    private func appPlist() throws -> [String: Any] {
        try plist(at: Bundle.main.url(forResource: "Info", withExtension: "plist"))
    }

    private func widgetPlist() throws -> [String: Any] {
        try plist(at: Bundle.main.builtInPlugInsURL?
            .appendingPathComponent("CaroullageWidgets.appex/Info.plist"))
    }

    func testTheAppShipsForIPhoneOnly() throws {
        XCTAssertEqual(try appPlist()["UIDeviceFamily"] as? [Int], [1])
    }

    func testTheWidgetShipsForIPhoneOnly() throws {
        // An extension that claims a family its app does not is rejected at upload.
        XCTAssertEqual(try widgetPlist()["UIDeviceFamily"] as? [Int], [1])
    }

    func testNoIPadOrientationsAreDeclared() throws {
        XCTAssertNil(try appPlist()["UISupportedInterfaceOrientations~ipad"],
                     "an iPad orientation list on an iPhone-only app is dead weight at best")
    }

    func testTheIPhoneStaysPortrait() throws {
        XCTAssertEqual(try appPlist()["UISupportedInterfaceOrientations"] as? [String],
                       ["UIInterfaceOrientationPortrait"])
    }
}
