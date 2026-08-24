import AppKit
import ScreenCaptureKit
import XCTest
@testable import my_window_pip

final class CapturedContentAspectTests: XCTestCase {

    func testStableBlackPaddingMismatchProducesCorrection() {
        var tracker = CapturedContentAspectTracker()
        let expected = CGSize(width: 640, height: 350)
        let captured = CGSize(width: 640, height: 320)

        XCTAssertNil(tracker.observe(contentSize: captured, expectedSize: expected))
        XCTAssertNil(tracker.observe(contentSize: captured, expectedSize: expected))
        let corrected = tracker.observe(contentSize: captured, expectedSize: expected)

        XCTAssertEqual(corrected ?? 0, 2, accuracy: 0.0001)
    }

    func testFrameContentRectMetadataConvertsPointsToPixels() {
        let info: [SCStreamFrameInfo: Any] = [
            .contentRect: CGRect(x: 0, y: 0, width: 320, height: 160).dictionaryRepresentation,
            .scaleFactor: CGFloat(2),
        ]

        let size = FrameGate.contentRectPixelSize(from: info)

        XCTAssertEqual(size, CGSize(width: 640, height: 320))
    }

    func testTransientContentRectDoesNotResizeWindow() {
        var tracker = CapturedContentAspectTracker()
        let expected = CGSize(width: 640, height: 350)

        XCTAssertNil(tracker.observe(
            contentSize: CGSize(width: 640, height: 320), expectedSize: expected
        ))
        XCTAssertNil(tracker.observe(
            contentSize: CGSize(width: 640, height: 300), expectedSize: expected
        ))
        XCTAssertNil(tracker.observe(
            contentSize: CGSize(width: 640, height: 320), expectedSize: expected
        ))
    }

    func testPixelRoundingDifferenceIsIgnored() {
        var tracker = CapturedContentAspectTracker()
        let expected = CGSize(width: 640, height: 350)
        let rounded = CGSize(width: 640, height: 349)

        for _ in 0..<CapturedContentAspectTracker.requiredStableSamples {
            XCTAssertNil(tracker.observe(contentSize: rounded, expectedSize: expected))
        }
    }

    func testCorrectedSizePreservesWidth() {
        let corrected = CapturedContentAspectTracker.correctedSize(
            CGSize(width: 1600, height: 875), matching: 2
        )

        XCTAssertEqual(corrected?.width, 1600)
        XCTAssertEqual(corrected?.height, 800)
    }

    func testOnlyWholeWindowIdentityTracksFrameGeometry() {
        let whole = PositionMemoryIdentity.window(appPreferenceKey: "cursor", windowID: 1)
        let region = PositionMemoryIdentity.windowRegion(
            appPreferenceKey: "cursor",
            windowID: 1,
            rect: CGRect(x: 0, y: 0, width: 640, height: 320)
        )

        XCTAssertTrue(whole.capturesWholeWindow)
        XCTAssertFalse(region.capturesWholeWindow)
    }
}
