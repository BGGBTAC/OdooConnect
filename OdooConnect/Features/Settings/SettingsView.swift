import SwiftUI
import SwiftData
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(DraftSync.self) private var draftSync
    @Environment(OrderWatcher.self) private var orderWatcher
    @Environment(\.openURL) private var openURL
    @Query(sort: \DraftQuote.createdAt, order: .reverse) private var drafts: [DraftQuote]

    @State private var notificationsOn: Bool = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            if case .signedIn(let config, let uid) = auth.state {
                Section("Verbindung") {
                    LabeledContent("Server", value: config.baseURL.absoluteString)
                    LabeledContent("Datenbank", value: config.database)
                    LabeledContent("Benutzer", value: config.login)
                    LabeledContent("UID", value: "\(uid)")
                }
                Section("Unternehmen") {
                    LabeledContent("Firma", value: auth.company?.name ?? "–")
                    LabeledContent("Währung", value: currencyLabel)
                    Button("Aktualisieren") {
                        Task { await auth.refreshCompanyContext() }
                    }
                }
                Section("Offline-Entwürfe") {
                    LabeledContent("Lokal gespeichert", value: "\(drafts.count)")
                    LabeledContent("Wartet auf Sync", value: "\(pendingCount)")
                    LabeledContent("Fehlgeschlagen", value: "\(failedCount)")
                    if let lastSyncedAt = draftSync.lastSyncedAt {
                        LabeledContent("Letzter Sync", value: lastSyncedAt.formatted(date: .omitted, time: .shortened))
                    }
                    Button {
                        Task { await draftSync.sync() }
                    } label: {
                        HStack {
                            Text("Jetzt synchronisieren")
                            Spacer()
                            if draftSync.isSyncing { ProgressView() }
                        }
                    }
                    .disabled(draftSync.isSyncing || drafts.isEmpty)
                }
                Section("Benachrichtigungen") {
                    if notificationStatus == .denied {
                        // iOS silently swallows further requestAuthorization
                        // calls once the user has denied — only the system
                        // Settings app can reverse it.
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        } label: {
                            Label("In den Einstellungen aktivieren", systemImage: "gear")
                        }
                        Text("Du hast Benachrichtigungen für OdooCompanion deaktiviert. Aktiviere sie in den iOS-Einstellungen, um neue Bestellungen zu erhalten.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Toggle("Neue Bestellungen melden", isOn: $notificationsOn)
                            .onChange(of: notificationsOn) { _, newValue in
                                Task {
                                    if newValue {
                                        let granted = await orderWatcher.requestAuthorization()
                                        if !granted { notificationsOn = false }
                                        notificationStatus = await orderWatcher.authorizationStatus()
                                    } else {
                                        orderWatcher.disable()
                                    }
                                }
                            }
                        Text("Wir wecken die App im Hintergrund (~alle 15 Min) und prüfen, ob neue bestätigte Aufträge vorliegen.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
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
        .onAppear { notificationsOn = orderWatcher.notificationsEnabled }
        .task {
            notificationStatus = await orderWatcher.authorizationStatus()
        }
    }

    private var currencyLabel: String {
        let currency = auth.companyCurrency
        if let symbol = currency.symbol, !symbol.isEmpty {
            return "\(currency.code) (\(symbol))"
        }
        return currency.code
    }

    private var pendingCount: Int {
        drafts.filter { $0.status == .pending || $0.status == .sending }.count
    }

    private var failedCount: Int {
        drafts.filter { $0.status == .failed }.count
    }
}
