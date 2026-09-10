import AppKit

/// 同步系统查询只在 utility queue 执行；单个会话至多一个在途请求。
/// 所有状态和 completion 都在主线程，失效后的迟到结果不会提交。
final class SourceGeometryProbe {
    struct WindowSnapshot: Equatable {
        let ownerPID: pid_t
        let size: CGSize
    }
    typealias ReadWindow = (CGWindowID) -> WindowSnapshot?
    typealias ReadAX = (CGWindowID, pid_t) -> CGSize?

    private let queue: DispatchQueue
    private let readWindow: ReadWindow
    private let readAX: ReadAX
    private var revision: UInt64 = 0
    private(set) var isInFlight = false

    init(queue: DispatchQueue, readWindow: @escaping ReadWindow = SourceGeometryProbe.readWindow,
         readAX: @escaping ReadAX = { SourceWindowActivator.currentSize(of: $0, expectedPID: $1) }) {
        self.queue = queue
        self.readWindow = readWindow
        self.readAX = readAX
    }

    func invalidate() {
        dispatchPrecondition(condition: .onQueue(.main))
        revision &+= 1
    }

    func verify(windowID: CGWindowID, expectedPID: pid_t, current: CGRect, stableFrameSize: CGSize,
                completion: @escaping (CGSize?) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !isInFlight else { return }
        isInFlight = true
        let requestedRevision = revision
        let readWindow = self.readWindow
        let readAX = self.readAX
        queue.async { [weak self] in
            let verified: CGSize? = {
                guard expectedPID > 0, let snapshot = readWindow(windowID),
                      snapshot.ownerPID == expectedPID else { return nil }
                let unchanged = abs(snapshot.size.width - current.width) <= 1
                    && abs(snapshot.size.height - current.height) <= 1
                // AX 只能查询原 owner，不能根据复用后的 ID 切换到另一个进程。
                let ax = unchanged ? nil : readAX(windowID, expectedPID)
                // AX IPC 期间窗口可能关闭、换 owner 或继续 resize。此时整份结果作废。
                guard let after = readWindow(windowID), after == snapshot else { return nil }
                return Geo.verifiedWindowSize(
                    current: current, windowSize: snapshot.size, axSize: ax,
                    stableFrameSize: stableFrameSize
                )
            }()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isInFlight = false
                guard self.revision == requestedRevision else { return }
                completion(verified)
            }
        }
    }

    /// owner 与 bounds 必须来自同一次 WindowServer 快照。
    private static func readWindow(windowID: CGWindowID) -> WindowSnapshot? {
        guard let info = SourceWindowActivator.windowInfo(of: windowID),
              let pid = info[kCGWindowOwnerPID as String] as? NSNumber,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
        return WindowSnapshot(ownerPID: pid_t(pid.int32Value), size: rect.size)
    }
}
