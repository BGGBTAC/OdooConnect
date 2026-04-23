import Foundation
import Network

/// Wraps `NWPathMonitor` as multi-subscriber `AsyncStream`s of online/offline
/// transitions. Subscribers are tracked individually so a second listener
/// never silently overwrites the first. Cancellation flows back through
/// `onTermination`, and the underlying monitor stops only when the actor's
/// `stop()` method is called explicitly — never inside `deinit`, which would
/// violate Swift 6 actor isolation.
actor Connectivity {
    private let monitor = NWPathMonitor()
    // NWPathMonitor.start(queue:) requires a DispatchQueue — there is no
    // Swift Concurrency-native API for it. Path updates hop back into the
    // actor via `Task { await self.publish(_:) }` in pathUpdateHandler.
    private let queue = DispatchQueue(label: "com.odooconnect.connectivity")
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]
    private var monitorRunning = false
    private(set) var lastKnownState: Bool?

    func updates() -> AsyncStream<Bool> {
        let id = UUID()
        return AsyncStream { continuation in
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task { await self.unregister(id: id) }
            }
            Task { await self.register(id: id, continuation: continuation) }
        }
    }

    func stop() {
        if monitorRunning {
            monitor.cancel()
            monitorRunning = false
        }
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }

    private func register(id: UUID, continuation: AsyncStream<Bool>.Continuation) {
        continuations[id] = continuation
        if let last = lastKnownState {
            continuation.yield(last)
        }
        startMonitorIfNeeded()
    }

    private func unregister(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func startMonitorIfNeeded() {
        guard !monitorRunning else { return }
        monitorRunning = true
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            guard let self else { return }
            Task { await self.publish(online) }
        }
        monitor.start(queue: queue)
    }

    private func publish(_ online: Bool) {
        lastKnownState = online
        for continuation in continuations.values {
            continuation.yield(online)
        }
    }
}
