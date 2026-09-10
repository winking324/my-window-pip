import AppKit
import XCTest
@testable import my_window_pip

final class SourceGeometryProbeTests: XCTestCase {
    func testSlowSystemQueryDoesNotBlockMainQueueAndOnlyOneRequestRuns() {
        let finished = expectation(description: "result applied on main")
        let mainResponsive = expectation(description: "main queue runs while query waits")
        let release = DispatchSemaphore(value: 0)
        let size = CGSize(width: 1280, height: 720)
        let probe = SourceGeometryProbe(
            queue: DispatchQueue(label: "geometry-test", qos: .utility),
            readWindow: { _ in .init(ownerPID: 42, size: size) }
        ) { _, pid in
            XCTAssertEqual(pid, 42)
            XCTAssertFalse(Thread.isMainThread)
            XCTAssertEqual(release.wait(timeout: .now() + 2), .success)
            return nil
        }
        let old = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        probe.verify(windowID: 1, expectedPID: 42, current: old, stableFrameSize: size) { verified in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertFalse(probe.isInFlight)
            XCTAssertEqual(verified, size)
            finished.fulfill()
        }
        XCTAssertTrue(probe.isInFlight)
        probe.verify(windowID: 1, expectedPID: 42, current: old, stableFrameSize: size) { _ in
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
        let probe = SourceGeometryProbe(queue: queue,
            readWindow: { _ in .init(ownerPID: 42, size: size) }, readAX: { _, _ in nil })
        probe.verify(windowID: 1, expectedPID: 42, current: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                     stableFrameSize: size) { _ in unexpected.fulfill() }
        // 主线程尚未让出，模拟关闭、重匹配或 retune 先于后台结果完成。
        probe.invalidate()
        queue.sync {} // 注入的查询已结束，主线程回调仍在等待执行。
        wait(for: [unexpected], timeout: 0.2)
        XCTAssertFalse(probe.isInFlight)
    }

    func testRejectsMissingOrReusedWindowBeforeQueryingAX() {
        for snapshot: SourceGeometryProbe.WindowSnapshot? in [
            nil, .init(ownerPID: 99, size: CGSize(width: 1280, height: 720))
        ] {
            let finished = expectation(description: "reject wrong owner")
            let probe = SourceGeometryProbe(queue: DispatchQueue(label: "owner-test"),
                readWindow: { _ in snapshot }, readAX: { _, _ in
                    XCTFail("Must not query AX for a replacement window")
                    return CGSize(width: 800, height: 600)
                })
            probe.verify(windowID: 1, expectedPID: 42,
                         current: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                         stableFrameSize: CGSize(width: 1280, height: 720)) { size in
                XCTAssertNil(size)
                finished.fulfill()
            }
            wait(for: [finished], timeout: 2)
        }
    }

    func testRejectsWindowReplacementClosureOrResizeDuringAXQuery() {
        let original = SourceGeometryProbe.WindowSnapshot(
            ownerPID: 42, size: CGSize(width: 1280, height: 720)
        )
        for after: SourceGeometryProbe.WindowSnapshot? in [
            nil, .init(ownerPID: 99, size: original.size),
            .init(ownerPID: 42, size: CGSize(width: 800, height: 600))
        ] {
            let finished = expectation(description: "reject stale snapshot after AX")
            var axWasQueried = false
            let probe = SourceGeometryProbe(queue: DispatchQueue(label: "owner-test"),
                readWindow: { _ in axWasQueried ? after : original }, readAX: { _, pid in
                    XCTAssertEqual(pid, 42)
                    axWasQueried = true
                    return original.size
                })
            probe.verify(windowID: 1, expectedPID: 42,
                         current: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                         stableFrameSize: original.size) { size in
                XCTAssertTrue(axWasQueried)
                XCTAssertNil(size)
                finished.fulfill()
            }
            wait(for: [finished], timeout: 2)
        }
    }

    func testMatchingOwnerAcceptsAXGeometry() {
        let finished = expectation(description: "verified owner")
        let observed = SourceGeometryProbe.WindowSnapshot(
            ownerPID: 42, size: CGSize(width: 1280, height: 720)
        )
        let actual = CGSize(width: 1600, height: 900)
        let probe = SourceGeometryProbe(queue: DispatchQueue(label: "owner-test"),
            readWindow: { _ in observed }, readAX: { _, pid in
                XCTAssertEqual(pid, 42)
                return actual
            })
        probe.verify(windowID: 1, expectedPID: 42,
                     current: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                     stableFrameSize: actual) { size in
            XCTAssertEqual(size, actual)
            finished.fulfill()
        }
        wait(for: [finished], timeout: 2)
    }
}
