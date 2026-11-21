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

    // The answer rotates the authored loop to its first page of the preferred
    // kind; the loop's neighbours, and each kind's own order, are unchanged.

    func testCarouselMakersSeeCarouselsFirstInAuthoredOrder() throws {
        let ordered = HeroOrdering.order(try refs(), for: .carousels)
        XCTAssertEqual(ordered.map(\.id), ["c1", "t2", "c2", "t1", "v1"])
    }

    func testReelMakersSeeVideoFirst() throws {
        XCTAssertEqual(HeroOrdering.order(try refs(), for: .reels).map(\.id), ["v1", "c1", "t2", "c2", "t1"])
    }

    func testPinterestMakersSeeTemplatesFirst() throws {
        XCTAssertEqual(HeroOrdering.order(try refs(), for: .pinterest).map(\.id), ["t1", "v1", "c1", "t2", "c2"])
    }

    /// The loop's neighbours survive: whatever the answer, each page is
    /// followed by the same page as in the manifest (wrapping at the end).
    func testEveryAnswerKeepsTheAuthoredNeighbours() throws {
        let authored = try refs().map(\.id)
        func successors(_ ids: [String]) -> [String: String] {
            Dictionary(uniqueKeysWithValues: ids.indices.map { (ids[$0], ids[($0 + 1) % ids.count]) })
        }
        for kind in CreatorKind.allCases {
            let ordered = HeroOrdering.order(try refs(), for: kind).map(\.id)
            XCTAssertEqual(successors(ordered), successors(authored), "\(kind)")
        }
    }

    /// A kind the manifest does not carry leaves the order alone.
    func testAPreferredKindWithNoPageLeavesTheOrderAlone() throws {
        let json = #"[{"kind": "template", "id": "t1"}, {"kind": "carousel", "id": "c1"}]"#
        let refs = try JSONDecoder().decode([SampleContentManifest.HeroRef].self, from: Data(json.utf8))
        XCTAssertEqual(HeroOrdering.order(refs, for: .reels).map(\.id), ["t1", "c1"])
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
