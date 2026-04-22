import SwiftUI

struct LoginView: View {
    @Environment(AuthManager.self) private var auth

    @State private var serverURL: String = "https://mycompany.odoo.com"
    @State private var database: String = ""
    @State private var login: String = ""
    @State private var apiKey: String = ""
    @State private var oauthError: String?
    @State private var oauthInFlight = false
    @State private var showAdvanced: Bool = false
    @FocusState private var focusedField: Field?

    private let oauthClient = OAuthClient()

    private enum Field: Hashable {
        case serverURL, database, login, apiKey
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Odoo Server") {
                    TextField("https://mycompany.odoo.com", text: $serverURL)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .serverURL)
                        .submitLabel(.next)
                }

                Section {
                    Button {
                        Task { await performOAuth() }
                    } label: {
                        HStack {
                            if oauthInFlight {
                                ProgressView()
                            } else {
                                Image(systemName: "globe")
                                Text("Über Browser anmelden").bold()
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(URL(string: serverURL) == nil || oauthInFlight)
                } footer: {
                    if let oauthError {
                        Text(oauthError).foregroundStyle(.red).font(.footnote)
                    } else {
                        Text("Funktioniert mit Passwort, Google, Microsoft — alles was dein Odoo unterstützt. Setzt das `odooconnect_bridge` Modul auf dem Server voraus.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    DisclosureGroup("Manuell mit API-Key", isExpanded: $showAdvanced) {
                        TextField("Datenbank", text: $database)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .database)
                            .submitLabel(.next)
                        TextField("E‑Mail oder Login", text: $login)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .login)
                            .submitLabel(.next)
                        SecureField("API‑Key", text: $apiKey)
                            .textContentType(.password)
                            .focused($focusedField, equals: .apiKey)
                            .submitLabel(.go)
                        Button {
                            focusedField = nil
                            Task { await performManualSignIn() }
                        } label: {
                            if auth.state == .signingIn {
                                ProgressView()
                            } else {
                                Text("Anmelden").frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!canSubmitManual || auth.state == .signingIn)
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let err = auth.lastError {
                            Text(err).foregroundStyle(.red)
                        }
                        Text("API‑Keys erstellst du in Odoo unter Einstellungen → Benutzer → Konto‑Sicherheit → API‑Keys.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("OdooCompanion")
            .onSubmit { advanceFocus() }
        }
    }

    private var canSubmitManual: Bool {
        URL(string: serverURL) != nil &&
        !database.trimmingCharacters(in: .whitespaces).isEmpty &&
        !login.trimmingCharacters(in: .whitespaces).isEmpty &&
        !apiKey.isEmpty
    }

    private func advanceFocus() {
        switch focusedField {
        case .serverURL: focusedField = .database
        case .database: focusedField = .login
        case .login: focusedField = .apiKey
        case .apiKey:
            focusedField = nil
            if canSubmitManual { Task { await performManualSignIn() } }
        case nil: break
        }
    }

    private func performManualSignIn() async {
        guard let url = URL(string: serverURL) else { return }
        await auth.signIn(baseURL: url, database: database, login: login, apiKey: apiKey)
    }

    private func performOAuth() async {
        guard let url = URL(string: serverURL) else { return }
        oauthError = nil
        oauthInFlight = true
        defer { oauthInFlight = false }
        do {
            let result = try await oauthClient.signIn(serverURL: url)
            await auth.completeOAuth(serverURL: url, result: result)
        } catch OAuthError.cancelled {
            // user dismissed — silent
        } catch {
            oauthError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
