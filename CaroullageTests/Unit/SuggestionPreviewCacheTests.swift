//
//  SuggestionPreviewCacheTests.swift
//  CaroullageTests
//
//  Home retention, phase 2. A suggestion thumbnail is the user's photos
//  rendered into the layout — provably, by pixels — and it is rendered once
//  per library state: memory, then disk, then Vision-free reuse.
//

import XCTest
@testable import Caroullage

@MainActor
final class SuggestionPreviewCacheTests: XCTestCase {

    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuggestionPreviewCacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func makeCache() -> SuggestionPreviewCache {
        SuggestionPreviewCache(maxDimension: 120, directory: directory)
    }

    private func solid(_ color: UIColor) -> CGImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }.cgImage!
    }

    private func photos(_ colors: [UIColor], prefix: String = "p") -> [RecentPhoto] {
        colors.enumerated().map { RecentPhoto(assetID: "\(prefix)\($0.offset)", image: solid($0.element)) }
    }

    private func pixels(_ image: CGImage?) -> Data? {
        image?.dataProvider?.data as Data?
    }

    // MARK: - Rendering

    func testAThumbnailIsThePhotosInTheLayout() async {
        let cache = makeCache()
        let warm = await cache.thumbnail(for: .fourSquare, photos: photos([.red, .green, .blue, .yellow]))
        let cool = await cache.thumbnail(for: .fourSquare, photos: photos([.cyan, .magenta, .black, .white], prefix: "q"))

        XCTAssertNotNil(warm)
        XCTAssertNotNil(cool)
        XCTAssertNotEqual(pixels(warm), pixels(cool), "Different photos must render differently")
        XCTAssertLessThanOrEqual(max(warm!.width, warm!.height), 120 * 3,
                                 "Bounded by maxDimension (at up to 3x scale)")
    }

    func testTheSameLibraryStateRendersOnce() async {
        let cache = makeCache()
        let library = photos([.red, .green, .blue, .yellow])

        _ = await cache.thumbnail(for: .fourSquare, photos: library)
        _ = await cache.thumbnail(for: .fourSquare, photos: library)

        XCTAssertEqual(cache.renderCount, 1, "The second call is a memory hit")
    }

    func testAChangedLibraryRendersAgain() async {
        let cache = makeCache()
        _ = await cache.thumbnail(for: .fourSquare, photos: photos([.red, .green, .blue, .yellow]))
        _ = await cache.thumbnail(for: .fourSquare, photos: photos([.red, .green, .blue, .yellow], prefix: "new"))
        XCTAssertEqual(cache.renderCount, 2, "New asset ids mean new photos, whatever they look like")
    }

    func testOnlyThePhotosTheLayoutUsesAreInTheKey() async {
        // A four-cell layout ignores a fifth photo, so adding one must not
        // invalidate its thumbnail.
        let cache = makeCache()
        let four = photos([.red, .green, .blue, .yellow])
        let five = four + photos([.purple], prefix: "extra")
        _ = await cache.thumbnail(for: .fourSquare, photos: four)
        _ = await cache.thumbnail(for: .fourSquare, photos: five)
        XCTAssertEqual(cache.renderCount, 1)
    }

    func testConcurrentRequestsForOneKeyShareARender() async {
        let cache = makeCache()
        let library = photos([.red, .green, .blue, .yellow])
        async let first = cache.thumbnail(for: .fourSquare, photos: library)
        async let second = cache.thumbnail(for: .fourSquare, photos: library)
        let both = await (first, second)
        XCTAssertNotNil(both.0)
        XCTAssertNotNil(both.1)
        XCTAssertEqual(cache.renderCount, 1)
    }

    // MARK: - Disk

    func testARelaunchFindsTheThumbnailOnDisk() async {
        let library = photos([.red, .green, .blue, .yellow])
        let first = makeCache()
        let rendered = await first.thumbnail(for: .fourSquare, photos: library)
        XCTAssertNotNil(rendered)

        let relaunched = makeCache()
        let reloaded = await relaunched.thumbnail(for: .fourSquare, photos: library)
        XCTAssertNotNil(reloaded)
        XCTAssertEqual(relaunched.renderCount, 0, "A disk hit is not a render")
        XCTAssertEqual(reloaded?.width, rendered?.width)
    }

    func testTheDiskCacheIsBounded() async {
        let cache = makeCache()
        for index in 0 ..< (SuggestionPreviewCache.diskCapacity + 4) {
            _ = await cache.thumbnail(for: .oneCell, photos: photos([.red], prefix: "lib\(index)-"))
        }
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasSuffix(".png") }   // the index file is not a thumbnail
        XCTAssertLessThanOrEqual(files.count, SuggestionPreviewCache.diskCapacity)
    }

    func testRemoveAllLeavesNothingBehind() async {
        let cache = makeCache()
        _ = await cache.thumbnail(for: .oneCell, photos: photos([.red]))
        cache.store(layouts: [.oneCell], forAssetIDs: ["p0"])
        cache.removeAll()
        XCTAssertNil(cache.cachedLayouts(forAssetIDs: ["p0"]))
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        XCTAssertTrue(files.isEmpty)
    }

    // MARK: - Layout results

    func testSuggestedLayoutsAreRememberedForExactlyThoseAssets() {
        let cache = makeCache()
        cache.store(layouts: [.fourSquare, .sixGrid], forAssetIDs: ["a", "b", "c", "d"])

        XCTAssertEqual(cache.cachedLayouts(forAssetIDs: ["a", "b", "c", "d"]), [.fourSquare, .sixGrid])
        XCTAssertNil(cache.cachedLayouts(forAssetIDs: ["a", "b", "c", "e"]), "One new photo is a new library")
        XCTAssertNil(cache.cachedLayouts(forAssetIDs: ["b", "a", "c", "d"]), "Order is part of the state")
    }
}
