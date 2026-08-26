import CoreGraphics
import XCTest
@testable import my_window_pip

final class WindowSnappingTests: XCTestCase {

    func testSnapCandidateMustBeActuallyVisibleOnCurrentSpace() {
        XCTAssertTrue(PiPSession.canParticipateInSnapping(
            isHidden: false,
            isWindowVisible: true,
            isOcclusionVisible: true
        ))
        XCTAssertFalse(PiPSession.canParticipateInSnapping(
            isHidden: true,
            isWindowVisible: true,
            isOcclusionVisible: true
        ))
        XCTAssertFalse(PiPSession.canParticipateInSnapping(
            isHidden: false,
            isWindowVisible: false,
            isOcclusionVisible: true
        ))
        XCTAssertFalse(PiPSession.canParticipateInSnapping(
            isHidden: false,
            isWindowVisible: true,
            isOcclusionVisible: false
        ))
    }

    func testScreenEdgeSnappingHasNoGapOnNegativeVisibleFrameCoordinates() {
        // 模拟副屏完整高度为 900pt、顶部菜单栏占用 40pt 后的可用区域。
        let visibleFrame = CGRect(x: -1200, y: -100, width: 1200, height: 860)
        let cases: [(proposed: CGRect, expected: CGRect)] = [
            (CGRect(x: -1199, y: 200, width: 300, height: 180),
             CGRect(x: -1200, y: 200, width: 300, height: 180)),
            (CGRect(x: -301, y: 200, width: 300, height: 180),
             CGRect(x: -300, y: 200, width: 300, height: 180)),
            (CGRect(x: -800, y: -99, width: 300, height: 180),
             CGRect(x: -800, y: -100, width: 300, height: 180)),
            (CGRect(x: -800, y: 659, width: 300, height: 100),
             CGRect(x: -800, y: 660, width: 300, height: 100)),
        ]

        for testCase in cases {
            let snapped = Geo.snappedWindowFrame(
                testCase.proposed,
                in: visibleFrame,
                siblings: []
            )

            XCTAssertEqual(snapped, testCase.expected)
            XCTAssertEqual(snapped.size, testCase.proposed.size)
        }
    }

    func testSiblingSnappingJoinsEveryAdjacentEdgeWithNoGap() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 2000, height: 1200)
        let sibling = CGRect(x: 900, y: 400, width: 200, height: 100)

        let cases: [(proposed: CGRect, expectedOrigin: CGPoint)] = [
            (CGRect(x: 902, y: 503, width: 200, height: 100), CGPoint(x: 900, y: 500)),
            (CGRect(x: 902, y: 297, width: 200, height: 100), CGPoint(x: 900, y: 300)),
            (CGRect(x: 697, y: 402, width: 200, height: 100), CGPoint(x: 700, y: 400)),
            (CGRect(x: 1103, y: 402, width: 200, height: 100), CGPoint(x: 1100, y: 400)),
        ]

        for testCase in cases {
            let snapped = Geo.snappedWindowFrame(
                testCase.proposed,
                in: visibleFrame,
                siblings: [sibling]
            )

            XCTAssertEqual(snapped.origin.x, testCase.expectedOrigin.x, accuracy: 0.001)
            XCTAssertEqual(snapped.origin.y, testCase.expectedOrigin.y, accuracy: 0.001)
            XCTAssertEqual(snapped.size, testCase.proposed.size)
        }
    }

    func testScreenEdgeOutsideThresholdDoesNotSnap() {
        let visibleFrame = CGRect(x: -1200, y: -100, width: 1200, height: 900)
        let proposed = CGRect(x: -327, y: 200, width: 300, height: 180)

        let snapped = Geo.snappedWindowFrame(proposed, in: visibleFrame, siblings: [])

        XCTAssertEqual(snapped, proposed)
    }

    func testDistantSiblingDoesNotInfluenceAlignment() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 2000, height: 1200)
        let proposed = CGRect(x: 650, y: 650, width: 200, height: 100)
        let distantSibling = CGRect(x: 649, y: 50, width: 200, height: 100)

        let snapped = Geo.snappedWindowFrame(
            proposed,
            in: visibleFrame,
            siblings: [distantSibling]
        )

        XCTAssertEqual(snapped, proposed)
    }
}
