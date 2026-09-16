//
//  HeroOrderingTests.swift
//  CaroullageTests
//
//  Home retention, phase 2. The hero leads with the kind the user said they
//  make, and otherwise keeps the manifest's authored order exactly.
//

import XCTest
@testable import Caroullage

final class HeroOrderingTests: XCTestCase {

    private func refs() throws -> [SampleContentManifest.HeroRef] {
        let json = """
        [
          {"kind": "template", "id": "t1"},
          {"kind": "video", "id": "v1"},
          {"kind": "carousel", "id": "c1"},
          {"kind": "template", "id": "t2"},
          {"kind": "carousel", "id": "c2"}
        ]
        """
        return try JSONDecoder().decode([SampleContentManifest.HeroRef].self, from: Data(json.utf8))
    }

    func testCarouselMakersSeeCarouselsFirstInAuthoredOrder() throws {
        let ordered = HeroOrdering.order(try refs(), for: .carousels)
        XCTAssertEqual(ordered.map(\.id), ["c1", "c2", "t1", "v1", "t2"])
    }

    func testReelMakersSeeVideoFirst() throws {
        XCTAssertEqual(HeroOrdering.order(try refs(), for: .reels).map(\.id), ["v1", "t1", "c1", "t2", "c2"])
    }

    func testPinterestMakersSeeTemplatesFirst() throws {
        XCTAssertEqual(HeroOrdering.order(try refs(), for: .pinterest).map(\.id), ["t1", "t2", "v1", "c1", "c2"])
    }

    func testFunAndNoAnswerLeaveTheManifestAlone() throws {
        let authored = try refs().map(\.id)
        XCTAssertEqual(HeroOrdering.order(try refs(), for: .fun).map(\.id), authored)
        XCTAssertEqual(HeroOrdering.order(try refs(), for: nil).map(\.id), authored)
    }

    func testNothingIsEverDroppedOrDuplicated() throws {
        for kind in CreatorKind.allCases {
            let ordered = HeroOrdering.order(try refs(), for: kind)
            XCTAssertEqual(Set(ordered.map(\.id)), Set(try refs().map(\.id)))
            XCTAssertEqual(ordered.count, 5)
        }
    }
}
