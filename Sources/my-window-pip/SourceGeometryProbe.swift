import AppKit

/// 同步系统查询只在 utility queue 执行；单个会话至多一个在途请求。
/// 所有状态和 completion 都在主线程，失效后的迟到结果不会提交。
final class SourceGeometryProbe {
    typealias ReadSizes = (CGWindowID, CGRect) -> (window: CGSize?, ax: CGSize?)

    private let queue: DispatchQueue
    private let readSizes: ReadSizes
    private var revision: UInt64 = 0
    private(set) var isInFlight = false

    init(queue: DispatchQueue, readSizes: @escaping ReadSizes = SourceGeometryProbe.readSizes) {
        self.queue = queue
        self.readSizes = readSizes
    }

    func invalidate() {
        dispatchPrecondition(condition: .onQueue(.main))
        revision &+= 1
    }

    func verify(windowID: CGWindowID, current: CGRect, stableFrameSize: CGSize,
                completion: @escaping (CGSize?) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !isInFlight else { return }
        isInFlight = true
        let requestedRevision = revision
        let readSizes = self.readSizes
        queue.async { [weak self] in
            let sizes = readSizes(windowID, current)
            let verified = Geo.verifiedWindowSize(
                current: current, windowSize: sizes.window, axSize: sizes.ax,
                stableFrameSize: stableFrameSize
            )
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isInFlight = false
                guard self.revision == requestedRevision else { return }
                completion(verified)
            }
        }
    }

    private static func readSizes(windowID: CGWindowID, current: CGRect) -> (window: CGSize?, ax: CGSize?) {
        let window = SourceWindowActivator.currentWindowServerSize(of: windowID)
        let unchanged = window.map {
            abs($0.width - current.width) <= 1 && abs($0.height - current.height) <= 1
        } ?? false
        let ax = unchanged ? nil : SourceWindowActivator.currentSize(of: windowID)
        return (window, ax)
    }
}
