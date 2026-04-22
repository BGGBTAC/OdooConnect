import Foundation
import Observation
import SwiftData

/// Main-actor coordinator that bridges UI triggers and the background
/// `OutboxProcessor`. Owns connectivity monitoring so a sync runs whenever
/// the device comes back online.
@Observable
@MainActor
final class DraftSync {
    private let processor: OutboxProcessor
    private let connectivity = Connectivity()
    private weak var auth: AuthManager?
    private var connectivityTask: Task<Void, Never>?

    var isSyncing: Bool = false
    var lastSyncedAt: Date?
    var lastError: String?

    init(container: ModelContainer, auth: AuthManager) {
        self.processor = OutboxProcessor(modelContainer: container)
        self.auth = auth
    }

    func start() {
        guard connectivityTask == nil else { return }
        let connectivity = connectivity
        connectivityTask = Task { [weak self] in
            for await online in await connectivity.updates() {
                guard !Task.isCancelled else { return }
                if online {
                    await self?.sync()
                }
            }
        }
    }

    func stop() async {
        connectivityTask?.cancel()
        connectivityTask = nil
        await connectivity.stop()
    }

    /// Manually trigger a sync pass. No-op when already syncing or offline.
    func sync() async {
        guard !isSyncing, let client = auth?.client else { return }
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }
        await processor.process(client: client)
        lastSyncedAt = .now
    }
}
