import XCTest
@testable import XuZhuo

final class IslandPlacementTests: XCTestCase {
    private let mainScreen = CGRect(x: 0, y: 24, width: 1440, height: 876)

    private func assertVisible(_ frame: CGRect, in screen: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(frame.origin.x.isFinite && frame.origin.y.isFinite, "位置必须有效", file: file, line: line)
        XCTAssertTrue(frame.width.isFinite && frame.height.isFinite, "尺寸必须有效", file: file, line: line)
        XCTAssertGreaterThan(frame.width, 0, file: file, line: line)
        XCTAssertGreaterThan(frame.height, 0, file: file, line: line)
        XCTAssertTrue(screen.contains(frame), "整枚胶囊应可见：\(frame)", file: file, line: line)
    }

    func testExpandingAndCollapsingKeepsTopAnchorWhenThereIsRoom() {
        let anchor = IslandPlacement.defaultAnchor(in: mainScreen)
        let collapsed = IslandPlacement.frame(size: IslandPlacement.collapsedSize, anchor: anchor, visibleFrames: [mainScreen])
        let expanded = IslandPlacement.frame(size: IslandPlacement.expandedSize, anchor: anchor, visibleFrames: [mainScreen])

        assertVisible(collapsed, in: mainScreen)
        assertVisible(expanded, in: mainScreen)
        XCTAssertEqual(IslandPlacement.centerTop(of: collapsed), anchor)
        XCTAssertEqual(IslandPlacement.centerTop(of: expanded), anchor, "展开应向下延伸，让桌面入口保持在原处")
    }

    func testDraggingBeyondEachEdgeKeepsTheWholeIslandVisible() {
        let anchors = [CGPoint(x: -10000, y: 500), CGPoint(x: 10000, y: 500),
                       CGPoint(x: 700, y: -10000), CGPoint(x: 700, y: 10000)]
        for anchor in anchors {
            let frame = IslandPlacement.frame(size: IslandPlacement.expandedSize, anchor: anchor, visibleFrames: [mainScreen])
            assertVisible(frame, in: mainScreen)
        }
    }

    func testSecondaryDisplayWithNegativeCoordinatesRetainsItsPosition() {
        let leftScreen = CGRect(x: -1920, y: 24, width: 1920, height: 1056)
        let anchor = CGPoint(x: -800, y: 900)
        let frame = IslandPlacement.frame(size: IslandPlacement.expandedSize, anchor: anchor, visibleFrames: [mainScreen, leftScreen])

        assertVisible(frame, in: leftScreen)
        XCTAssertEqual(IslandPlacement.centerTop(of: frame), anchor)
    }

    func testUnpluggedDisplayCannotStrandTheSavedIsland() {
        let savedAnchor = CGPoint(x: -800, y: 1040)
        let frame = IslandPlacement.frame(size: IslandPlacement.expandedSize, anchor: savedAnchor, visibleFrames: [mainScreen])

        assertVisible(frame, in: mainScreen)
    }

    func testOffscreenAnchorUsesNearestAvailableDisplay() {
        let rightScreen = CGRect(x: 1600, y: 24, width: 1600, height: 976)
        let anchor = CGPoint(x: 3500, y: 900)
        let frame = IslandPlacement.frame(size: IslandPlacement.collapsedSize, anchor: anchor, visibleFrames: [mainScreen, rightScreen])

        assertVisible(frame, in: rightScreen)
    }

    func testMalformedSavedPositionFallsBackToAVisibleIsland() {
        for anchor in [CGPoint(x: CGFloat.nan, y: 800), CGPoint(x: 800, y: CGFloat.infinity), CGPoint(x: -CGFloat.infinity, y: CGFloat.nan)] {
            let frame = IslandPlacement.frame(size: IslandPlacement.expandedSize, anchor: anchor, visibleFrames: [mainScreen])
            assertVisible(frame, in: mainScreen)
            XCTAssertEqual(IslandPlacement.centerTop(of: frame), IslandPlacement.defaultAnchor(in: mainScreen))
        }
    }

    func testIslandFitsADisplaySmallerThanItsRequestedSize() {
        let smallScreen = CGRect(x: 40, y: 60, width: 300, height: 220)
        let frame = IslandPlacement.frame(size: IslandPlacement.expandedSize,
                                          anchor: IslandPlacement.defaultAnchor(in: smallScreen), visibleFrames: [smallScreen])

        assertVisible(frame, in: smallScreen)
        XCTAssertEqual(frame.size, smallScreen.size)
    }

    func testMalformedRequestedSizeUsesSafeDimensions() {
        for size in [CGSize(width: CGFloat.nan, height: CGFloat.infinity), CGSize(width: 0, height: -50)] {
            let frame = IslandPlacement.frame(size: size, anchor: IslandPlacement.defaultAnchor(in: mainScreen), visibleFrames: [mainScreen])
            assertVisible(frame, in: mainScreen)
            XCTAssertEqual(frame.size, IslandPlacement.collapsedSize)
        }
    }

    func testNoDisplaysReturnsAFiniteFallbackForLaterRepositioning() {
        let frame = IslandPlacement.frame(size: IslandPlacement.expandedSize, anchor: CGPoint(x: CGFloat.nan, y: CGFloat.nan), visibleFrames: [])

        XCTAssertEqual(frame.size, IslandPlacement.collapsedSize)
        XCTAssertTrue(frame.origin.x.isFinite && frame.origin.y.isFinite)
    }
}
