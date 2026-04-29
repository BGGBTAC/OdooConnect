import SwiftUI
import SwiftData
import UserNotifications

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
