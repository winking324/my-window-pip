import AppKit
import ScreenCaptureKit
import XCTest
@testable import my_window_pip

final class CapturedContentGeometryTests: XCTestCase {

    private let fullConfiguration = CaptureFrameConfiguration(generation: 1, sourceRect: .zero)

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

        XCTAssertNil(tracker.observe(sourceSize: source, at: 0.00, configuration: fullConfiguration))
        XCTAssertNil(tracker.observe(sourceSize: source, at: 0.10, configuration: fullConfiguration))
        XCTAssertNil(tracker.observe(sourceSize: source, at: 0.20, configuration: fullConfiguration))
        XCTAssertNil(tracker.observe(sourceSize: source, at: 0.29, configuration: fullConfiguration))
        XCTAssertEqual(
            tracker.observe(sourceSize: source, at: 0.31, configuration: fullConfiguration),
            source
        )
    }

    func testStableGeometryAtFiveFPSIsAcceptedWithoutExtraDelay() {
        var tracker = CapturedContentGeometryTracker()
        let source = CGSize(width: 1600, height: 800)

        XCTAssertNil(tracker.observe(sourceSize: source, at: 0.0, configuration: fullConfiguration))
        XCTAssertNil(tracker.observe(sourceSize: source, at: 0.2, configuration: fullConfiguration))
        XCTAssertEqual(
            tracker.observe(sourceSize: source, at: 0.4, configuration: fullConfiguration),
            source
        )
    }

    func testGeometryChangeResetsStabilityWindow() {
        var tracker = CapturedContentGeometryTracker()
        let old = CGSize(width: 1600, height: 800)
        let new = CGSize(width: 1200, height: 800)

        XCTAssertNil(tracker.observe(sourceSize: old, at: 0.0, configuration: fullConfiguration))
        XCTAssertNil(tracker.observe(sourceSize: old, at: 0.2, configuration: fullConfiguration))
        XCTAssertNil(tracker.observe(sourceSize: new, at: 0.31, configuration: fullConfiguration))
        XCTAssertNil(tracker.observe(sourceSize: new, at: 0.50, configuration: fullConfiguration))
        XCTAssertEqual(
            tracker.observe(sourceSize: new, at: 0.62, configuration: fullConfiguration),
            new
        )
    }

    func testDelayedCroppedFramesCannotBecomeWholeWindowGeometryAfterZoomReset() {
        var tracker = CapturedContentGeometryTracker()
        let cropped = CaptureFrameConfiguration(
            generation: 1,
            sourceRect: CGRect(x: 400, y: 200, width: 800, height: 400)
        )
        let full = CaptureFrameConfiguration(generation: 2, sourceRect: .zero)
        let croppedSize = CGSize(width: 800, height: 400)
        let fullSize = CGSize(width: 1600, height: 800)

        // 即使旧裁剪配置持续超过稳定时长，也不能把局部尺寸提交为完整源尺寸。
        XCTAssertNil(tracker.observe(sourceSize: croppedSize, at: 0.0, configuration: cropped))
        XCTAssertNil(tracker.observe(sourceSize: croppedSize, at: 0.2, configuration: cropped))
        XCTAssertNil(tracker.observe(sourceSize: croppedSize, at: 0.4, configuration: cropped))

        // 新整窗配置需要独立完成自己的稳定窗口。
        XCTAssertNil(tracker.observe(sourceSize: fullSize, at: 0.41, configuration: full))
        XCTAssertNil(tracker.observe(sourceSize: fullSize, at: 0.61, configuration: full))
        XCTAssertEqual(
            tracker.observe(sourceSize: fullSize, at: 0.81, configuration: full),
            fullSize
        )
    }

    func testFullGeometryStabilityDoesNotCrossConfigurationGenerations() {
        var tracker = CapturedContentGeometryTracker()
        let source = CGSize(width: 1600, height: 800)
        let first = CaptureFrameConfiguration(generation: 1, sourceRect: .zero)
        let second = CaptureFrameConfiguration(generation: 2, sourceRect: .zero)

        XCTAssertNil(tracker.observe(sourceSize: source, at: 0.0, configuration: first))
        XCTAssertNil(tracker.observe(sourceSize: source, at: 0.2, configuration: first))
        XCTAssertNil(tracker.observe(sourceSize: source, at: 0.31, configuration: second))
        XCTAssertNil(tracker.observe(sourceSize: source, at: 0.51, configuration: second))
        XCTAssertEqual(
            tracker.observe(sourceSize: source, at: 0.71, configuration: second),
            source
        )
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

    func testOnlyUnzoomedWholeWindowRequestsUncroppedConfiguration() {
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
