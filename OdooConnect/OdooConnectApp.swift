import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct OdooConnectApp: App {
    @State private var auth: AuthManager
    @State private var draftSync: DraftSync
    @State private var orderWatcher: OrderWatcher
    @Environment(\.scenePhase) private var scenePhase
    private let container: ModelContainer

    @MainActor
    init() {
        let container = Self.makeContainer()
        self.container = container

        let auth = AuthManager()
        let watcher = OrderWatcher(auth: auth)
        _auth = State(initialValue: auth)
        _draftSync = State(initialValue: DraftSync(container: container, auth: auth))
        _orderWatcher = State(initialValue: watcher)

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: OrderWatcher.backgroundTaskIdentifier,
            using: nil
        ) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let work = Task { @MainActor in
                _ = await watcher.performRefresh()
                refresh.setTaskCompleted(success: true)
            }
            refresh.expirationHandler = { work.cancel() }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .modelContainer(container)
                .environment(draftSync)
                .environment(orderWatcher)
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
