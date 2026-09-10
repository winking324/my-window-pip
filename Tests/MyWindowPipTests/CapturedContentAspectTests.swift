import AppKit
import ScreenCaptureKit
import XCTest
@testable import my_window_pip

final class CapturedContentGeometryTests: XCTestCase {

    private let fullConfiguration = CaptureFrameConfiguration.applied(
        generation: 1,
        sourceRect: .zero
    )

    func testCaptureDoesNotExpandToIncludeChildWindows() throws {
        guard #available(macOS 14.2, *) else {
            throw XCTSkip("Child-window capture configuration requires macOS 14.2")
        }
        // 整窗和放大后都必须保持同一目标，不能在 retune 时重新包含附属窗口。
        for rect in [CGRect.zero, CGRect(x: 100, y: 100, width: 960, height: 525)] {
            let configuration = CaptureEngine.makeConfiguration(
                sourceRect: rect, pointSize: CGSize(width: 640, height: 350),
                scale: 2, fps: 5, showsCursor: false
            )
            XCTAssertFalse(configuration.includeChildWindows)
            XCTAssertEqual(configuration.sourceRect, rect)
            XCTAssertEqual(configuration.width, 1280)
            XCTAssertEqual(configuration.height, 700)
        }
    }

    func testFrameGeometryRestoresOriginalSourcePointSize() {
        let info: [SCStreamFrameInfo: Any] = [
            .contentRect: CGRect(x: 0, y: 0, width: 320, height: 160).dictionaryRepresentation,
            .scaleFactor: CGFloat(2),
            .contentScale: CGFloat(0.2),
        ]

        let geometry = FrameGate.sourceContentGeometry(from: info)

        XCTAssertEqual(geometry?.surfacePixelSize, CGSize(width: 640, height: 320))
        XCTAssertEqual(geometry?.sourcePointSize, CGSize(width: 1600, height: 800))
    }

    func testMissingContentScaleDoesNotInventSourceCoordinates() {
        let info: [SCStreamFrameInfo: Any] = [
            .contentRect: CGRect(x: 0, y: 0, width: 320, height: 160).dictionaryRepresentation,
            .scaleFactor: CGFloat(2),
        ]

        let geometry = FrameGate.sourceContentGeometry(from: info)

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
        let cropped = CaptureFrameConfiguration.applied(
            generation: 1,
            sourceRect: CGRect(x: 400, y: 200, width: 800, height: 400)
        )
        let full = CaptureFrameConfiguration.applied(generation: 2, sourceRect: .zero)
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
        let first = CaptureFrameConfiguration.applied(generation: 1, sourceRect: .zero)
        let second = CaptureFrameConfiguration.applied(generation: 2, sourceRect: .zero)

        XCTAssertNil(tracker.observe(sourceSize: source, at: 0.0, configuration: first))
        XCTAssertNil(tracker.observe(sourceSize: source, at: 0.2, configuration: first))
        XCTAssertNil(tracker.observe(sourceSize: source, at: 0.31, configuration: second))
        XCTAssertNil(tracker.observe(sourceSize: source, at: 0.51, configuration: second))
        XCTAssertEqual(
            tracker.observe(sourceSize: source, at: 0.71, configuration: second),
            source
        )
    }

    func testTransitioningFramesCannotCommitCroppedGeometryAsFullSource() {
        var tracker = CapturedContentGeometryTracker()
        let transition = CaptureFrameConfiguration.transitioning(generation: 2)
        let croppedSize = CGSize(width: 800, height: 400)

        // 模拟 SCK 已开始输出新裁剪帧、但配置完成回调被主线程阻塞超过稳定窗口。
        XCTAssertNil(tracker.observe(sourceSize: croppedSize, at: 0.0, configuration: transition))
        XCTAssertNil(tracker.observe(sourceSize: croppedSize, at: 0.2, configuration: transition))
        XCTAssertNil(tracker.observe(sourceSize: croppedSize, at: 0.4, configuration: transition))
        XCTAssertFalse(transition.capturesFullSource)
    }

    func testVerifiedWindowGeometryRemainsAuthoritativeAcrossRecovery() {
        var authority = SourceGeometryAuthority()
        XCTAssertTrue(authority.acceptsWindowServerSamples)

        authority.confirmVerifiedSize(CGSize(width: 1600, height: 800))

        XCTAssertFalse(authority.acceptsWindowServerSamples)
        XCTAssertEqual(authority.verifiedSize, CGSize(width: 1600, height: 800))

        authority.resetForNewTarget()
        XCTAssertTrue(authority.acceptsWindowServerSamples)
        XCTAssertNil(authority.verifiedSize)
    }

    func testOnlyUnzoomedWholeWindowRequestsUncroppedConfiguration() {
        let whole = PositionMemoryIdentity.window(appPreferenceKey: "cursor", windowID: 1)
        let region = PositionMemoryIdentity.windowRegion(
            appPreferenceKey: "cursor",
            windowID: 1,
            rect: CGRect(x: 0, y: 0, width: 640, height: 320)
        )

        XCTAssertTrue(whole.usesUncroppedWholeWindow(at: 1))
        XCTAssertFalse(whole.usesUncroppedWholeWindow(at: 1, hasSelectionCrop: true))
        XCTAssertFalse(whole.usesUncroppedWholeWindow(at: 2))
        XCTAssertFalse(region.usesUncroppedWholeWindow(at: 1))
    }

    func testConversationChangesDoNotResizeAnUnchangedWindow() throws {
        let windowSize = CGSize(width: 1920, height: 1050)
        var base = CGRect(origin: .zero, size: windowSize)
        var tracker = CapturedContentGeometryTracker()
        // 日志中的尺寸来回跳动，每个状态持续超过旧逻辑的稳定窗口。
        for (index, width) in [1920.0, 1962, 1920, 1962, 1920].enumerated() {
            let frameSize = CGSize(width: width, height: 1050)
            let start = Double(index)
            XCTAssertNil(tracker.observe(sourceSize: frameSize, at: start,
                                         configuration: fullConfiguration))
            XCTAssertNil(tracker.observe(sourceSize: frameSize, at: start + 0.2,
                                         configuration: fullConfiguration))
            XCTAssertNotNil(tracker.observe(sourceSize: frameSize, at: start + 0.4,
                                            configuration: fullConfiguration))
            base.size = try XCTUnwrap(Geo.verifiedWindowSize(
                current: base, windowSize: windowSize, axSize: nil
            ))
            XCTAssertEqual(base.size, windowSize)
        }
    }

    func testRealWindowResizeIsAcceptedWithoutAccessibility() {
        let base = CGRect(x: 0, y: 0, width: 1920, height: 1050)
        let resized = CGSize(width: 1440, height: 1050)
        XCTAssertEqual(Geo.verifiedWindowSize(current: base, windowSize: resized, axSize: nil), resized)
    }

    func testAccessibilityAllowsRealProportionalResize() {
        let base = CGRect(x: 0, y: 0, width: 1920, height: 1050)
        let resized = CGSize(width: 1280, height: 700)
        XCTAssertEqual(Geo.verifiedWindowSize(current: base, windowSize: resized, axSize: resized), resized)
    }

    func testMissionControlTransformCannotResizeThePiP() {
        let base = CGRect(x: 0, y: 0, width: 1920, height: 1050)
        let overview = CGSize(width: 1280, height: 700)
        XCTAssertNil(Geo.verifiedWindowSize(current: base, windowSize: overview, axSize: nil))
        XCTAssertEqual(Geo.verifiedWindowSize(current: base, windowSize: overview, axSize: base.size), base.size)
    }

    func testMissingOrInvalidWindowGeometryDoesNotAuthorizeResize() {
        let base = CGRect(x: 0, y: 0, width: 1920, height: 1050)
        for size: CGSize? in [nil, .zero, CGSize(width: CGFloat.nan, height: 1050),
                              CGSize(width: 1920, height: CGFloat.infinity)] {
            XCTAssertNil(Geo.verifiedWindowSize(current: base, windowSize: size, axSize: nil))
        }
        XCTAssertEqual(Geo.verifiedWindowSize(current: base, windowSize: nil, axSize: base.size), base.size)
    }
}
