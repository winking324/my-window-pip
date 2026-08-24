import AppKit
import ScreenCaptureKit
import XCTest
@testable import my_window_pip

final class CapturedContentAspectTests: XCTestCase {

    func testFrameGeometryRestoresOriginalSourcePointSize() {
        let info: [SCStreamFrameInfo: Any] = [
            .contentRect: CGRect(x: 0, y: 0, width: 320, height: 160).dictionaryRepresentation,
            .scaleFactor: CGFloat(2),
            .contentScale: CGFloat(0.2),
        ]

        let geometry = FrameGate.contentGeometry(from: info)

        XCTAssertEqual(geometry?.surfacePixelSize, CGSize(width: 640, height: 320))
        XCTAssertEqual(geometry?.sourcePointSize, CGSize(width: 1600, height: 800))
    }

    func testMissingContentScaleDoesNotInventSourceCoordinates() {
        let info: [SCStreamFrameInfo: Any] = [
            .contentRect: CGRect(x: 0, y: 0, width: 320, height: 160).dictionaryRepresentation,
            .scaleFactor: CGFloat(2),
        ]

        let geometry = FrameGate.contentGeometry(from: info)

        XCTAssertEqual(geometry?.surfacePixelSize, CGSize(width: 640, height: 320))
        XCTAssertNil(geometry?.sourcePointSize)
    }

    func testStableGeometryRequiresBothSamplesAndDuration() {
        var tracker = CapturedContentGeometryTracker()
        let source = CGSize(width: 1600, height: 800)

        XCTAssertNil(tracker.observe(sourceSize: source, at: 0.00))
        XCTAssertNil(tracker.observe(sourceSize: source, at: 0.10))
        XCTAssertNil(tracker.observe(sourceSize: source, at: 0.20))
        XCTAssertNil(tracker.observe(sourceSize: source, at: 0.29))
        XCTAssertEqual(tracker.observe(sourceSize: source, at: 0.31), source)
    }

    func testStableGeometryAtFiveFPSIsAcceptedWithoutExtraDelay() {
        var tracker = CapturedContentGeometryTracker()
        let source = CGSize(width: 1600, height: 800)

        XCTAssertNil(tracker.observe(sourceSize: source, at: 0.0))
        XCTAssertNil(tracker.observe(sourceSize: source, at: 0.2))
        XCTAssertEqual(tracker.observe(sourceSize: source, at: 0.4), source)
    }

    func testGeometryChangeResetsStabilityWindow() {
        var tracker = CapturedContentGeometryTracker()
        let old = CGSize(width: 1600, height: 800)
        let new = CGSize(width: 1200, height: 800)

        XCTAssertNil(tracker.observe(sourceSize: old, at: 0.0))
        XCTAssertNil(tracker.observe(sourceSize: old, at: 0.2))
        XCTAssertNil(tracker.observe(sourceSize: new, at: 0.31))
        XCTAssertNil(tracker.observe(sourceSize: new, at: 0.50))
        XCTAssertEqual(tracker.observe(sourceSize: new, at: 0.62), new)
    }

    func testFrameGeometryRemainsAuthoritativeAcrossRecovery() {
        var authority = SourceGeometryAuthority()
        XCTAssertTrue(authority.acceptsWindowServerSamples)

        authority.confirmFrameSize(CGSize(width: 1600, height: 800))

        XCTAssertFalse(authority.acceptsWindowServerSamples)
        XCTAssertEqual(authority.frameConfirmedSize, CGSize(width: 1600, height: 800))

        authority.resetForNewTarget()
        XCTAssertTrue(authority.acceptsWindowServerSamples)
        XCTAssertNil(authority.frameConfirmedSize)
    }

    func testOnlyUnzoomedWholeWindowUsesFrameGeometry() {
        let whole = PositionMemoryIdentity.window(appPreferenceKey: "cursor", windowID: 1)
        let region = PositionMemoryIdentity.windowRegion(
            appPreferenceKey: "cursor",
            windowID: 1,
            rect: CGRect(x: 0, y: 0, width: 640, height: 320)
        )

        XCTAssertTrue(whole.usesUncroppedWholeWindow(at: 1))
        XCTAssertFalse(whole.usesUncroppedWholeWindow(at: 2))
        XCTAssertFalse(region.usesUncroppedWholeWindow(at: 1))
    }
}
