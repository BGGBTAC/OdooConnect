import SwiftUI
import SwiftData
import BackgroundTasks
import UserNotifications
import os

@main
struct OdooConnectApp: App {
    @State private var auth: AuthManager
    @State private var draftSync: DraftSync
    @State private var orderWatcher: OrderWatcher
    @State private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase
    private let container: ModelContainer

    @MainActor
    init() {
        let container = Self.makeContainer()
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

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: OrderWatcher.backgroundTaskIdentifier,
            using: nil
        ) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            // setTaskCompleted MUST be called exactly once: once from the
            // work Task on success, or once from the expiration handler
            // when the system reclaims the task. Calling it twice — or
            // not at all from the expiration handler — terminates the
            // app and shows up as a crash in the next launch.
            let didComplete = OSAllocatedUnfairLock<Bool>(initialState: false)
            @Sendable func complete(_ success: Bool) {
                let shouldFinish: Bool = didComplete.withLock { state in
                    guard !state else { return false }
                    state = true
                    return true
                }
                if shouldFinish {
                    refresh.setTaskCompleted(success: success)
                }
            }

            let work = Task { @MainActor in
                _ = await watcher.performRefresh()
                complete(true)
            }
            refresh.expirationHandler = {
                work.cancel()
                complete(false)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .modelContainer(container)
                .environment(draftSync)
                .environment(orderWatcher)
                .environment(router)
                .task { draftSync.start() }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background {
                        orderWatcher.scheduleNextRefresh()
                    }
                }
        }
    }

    private static func makeContainer() -> ModelContainer {
        if let persistent = try? ModelContainer(for: DraftQuote.self, DraftLine.self) {
            return persistent
        }
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(
                for: DraftQuote.self, DraftLine.self,
                configurations: configuration
            )
        } catch {
            fatalError("Unable to create even an in-memory ModelContainer: \(error)")
        }
    }
}
