import SwiftUI
import SwiftData
import UserNotifications

@main
struct OdooConnectApp: App {
    @State private var auth: AuthManager
    @State private var draftSync: DraftSync
    @State private var orderWatcher: OrderWatcher
    @State private var router: AppRouter
    @State private var storageHealth: StorageHealth
    @Environment(\.scenePhase) private var scenePhase
    private let container: ModelContainer

    @MainActor
    init() {
        let (container, degraded, reason) = Self.makeContainer()
        self.container = container

        let auth = AuthManager()
        let watcher = OrderWatcher(auth: auth)
        let router = AppRouter()

        NotificationDelegate.shared.router = router
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared

        _auth = State(initialValue: auth)
        _draftSync = State(initialValue: DraftSync(container: container, auth: auth))
        _orderWatcher = State(initialValue: watcher)
        _router = State(initialValue: router)
        _storageHealth = State(initialValue: StorageHealth(isDegraded: degraded, degradedReason: reason))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Theme.brand)
                .environment(auth)
                .modelContainer(container)
                .environment(draftSync)
                .environment(orderWatcher)
                .environment(router)
                .environment(storageHealth)
                .task { draftSync.start() }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background {
                        orderWatcher.scheduleNextRefresh()
                    }
                }
        }
        // SwiftUI's .backgroundTask handles BGTaskScheduler.register +
        // setTaskCompleted + expiration via Task cancellation behind the
        // scenes. Replaces the manual register block we used to do from
        // init(), which crashed under Swift 6 strict concurrency with
        // EXC_BREAKPOINT in `swift_task_checkIsolatedSwift` when iOS
        // invoked the closure on a non-main system worker queue.
        .backgroundTask(.appRefresh(OrderWatcher.backgroundTaskIdentifier)) {
            await orderWatcher.performRefresh()
        }
    }

    /// Opens the on-disk SwiftData store. On failure it makes ONE recovery
    /// attempt (deleting the corrupt store + its SQLite sidecars at the
    /// default location, then reopening) before degrading to a volatile
    /// in-memory store. The degraded flag drives a persistent warning banner
    /// so silent data loss can't masquerade as normal operation.
    private static func makeContainer() -> (container: ModelContainer, degraded: Bool, reason: String?) {
        func openPersistent() throws -> ModelContainer {
            try ModelContainer(for: DraftQuote.self, DraftLine.self)
        }

        // 1) Normal open at the default store location.
        if let persistent = try? openPersistent() {
            return (persistent, false, nil)
        }

        // 2) One recovery attempt: remove the default store + its WAL/SHM
        //    sidecars and reopen. Sacrifices unreadable existing data but
        //    restores durable persistence for new drafts.
        let base = URL.applicationSupportDirectory
        for name in ["default.store", "default.store-shm", "default.store-wal"] {
            try? FileManager.default.removeItem(at: base.appending(path: name))
        }
        if let recovered = try? openPersistent() {
            return (recovered, false, nil)
        }

        // 3) Degrade to in-memory; drafts live only for this session.
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        do {
            let memory = try ModelContainer(
                for: DraftQuote.self, DraftLine.self,
                configurations: configuration
            )
            let reason = String(localized: "Lokaler Speicher konnte nicht geöffnet werden. Neue Entwürfe gehen beim Beenden der App verloren.")
            return (memory, true, reason)
        } catch {
            fatalError("Unable to create even an in-memory ModelContainer: \(error)")
        }
    }
}
