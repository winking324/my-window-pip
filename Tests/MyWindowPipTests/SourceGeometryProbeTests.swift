import AppKit
import XCTest
@testable import my_window_pip

final class SourceGeometryProbeTests: XCTestCase {
    func testSlowSystemQueryDoesNotBlockMainQueueAndOnlyOneRequestRuns() {
        let finished = expectation(description: "result applied on main")
        let mainResponsive = expectation(description: "main queue runs while query waits")
        let release = DispatchSemaphore(value: 0)
        let size = CGSize(width: 1280, height: 720)
        let probe = SourceGeometryProbe(queue: DispatchQueue(label: "geometry-test", qos: .utility)) { _, _ in
            XCTAssertFalse(Thread.isMainThread)
            XCTAssertEqual(release.wait(timeout: .now() + 2), .success)
            return (size, nil)
        }
        let old = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        probe.verify(windowID: 1, current: old, stableFrameSize: size) { verified in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertFalse(probe.isInFlight)
            XCTAssertEqual(verified, size)
            finished.fulfill()
        }
        XCTAssertTrue(probe.isInFlight)
        probe.verify(windowID: 1, current: old, stableFrameSize: size) { _ in
            XCTFail("A second concurrent request must not be submitted")
        }
        DispatchQueue.main.async {
            mainResponsive.fulfill()
            release.signal()
        }
        wait(for: [mainResponsive, finished], timeout: 3)
    }

    func testInvalidatedQueryCannotApplyLateResult() {
        let unexpected = expectation(description: "stale result")
        unexpected.isInverted = true
        let size = CGSize(width: 1280, height: 720)
        let queue = DispatchQueue(label: "geometry-test", qos: .utility)
        let probe = SourceGeometryProbe(queue: queue) { _, _ in
            (size, nil)
        }
        probe.verify(windowID: 1, current: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                     stableFrameSize: size) { _ in unexpected.fulfill() }
        // 主线程尚未让出，模拟关闭、重匹配或 retune 先于后台结果完成。
        probe.invalidate()
        queue.sync {} // 注入的查询已结束，主线程回调仍在等待执行。
        wait(for: [unexpected], timeout: 0.2)
        XCTAssertFalse(probe.isInFlight)
    }
}
