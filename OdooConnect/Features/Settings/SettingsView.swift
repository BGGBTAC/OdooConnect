import SwiftUI

struct SettingsView: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        Form {
            if case .signedIn(let config, let uid) = auth.state {
                Section("Verbindung") {
                    LabeledContent("Server", value: config.baseURL.absoluteString)
                    LabeledContent("Datenbank", value: config.database)
                    LabeledContent("Benutzer", value: config.login)
                    LabeledContent("UID", value: "\(uid)")
                }
            }
            Section {
                Button("Abmelden", role: .destructive) { auth.signOut() }
            }
            Section("Über") {
                LabeledContent("App", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
            }
        }
        .navigationTitle("Einstellungen")
    }
}
