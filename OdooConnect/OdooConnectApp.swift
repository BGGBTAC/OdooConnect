import SwiftUI

@main
struct OdooConnectApp: App {
    @State private var auth = AuthManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
        }
    }
}
