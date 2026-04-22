import SwiftUI

struct LoginView: View {
    @Environment(AuthManager.self) private var auth

    @State private var serverURL: String = "https://mycompany.odoo.com"
    @State private var database: String = ""
    @State private var login: String = ""
    @State private var apiKey: String = ""
    @FocusState private var focusedField: Field?

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
                    TextField("Datenbank", text: $database)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .database)
                        .submitLabel(.next)
                }
                Section("Zugangsdaten") {
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
                }
                Section {
                    Button {
                        focusedField = nil
                        Task { await performSignIn() }
                    } label: {
                        if auth.state == .signingIn {
                            ProgressView()
                        } else {
                            Text("Anmelden").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit || auth.state == .signingIn)
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let err = auth.lastError {
                            Text(err).foregroundStyle(.red)
                        }
                        Text("Den API‑Key erstellst du in Odoo unter Einstellungen → Benutzer → Konto‑Sicherheit → API‑Keys.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("OdooConnect")
            .onSubmit { advanceFocus() }
        }
    }

    private var canSubmit: Bool {
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
            if canSubmit { Task { await performSignIn() } }
        case nil: break
        }
    }

    private func performSignIn() async {
        guard let url = URL(string: serverURL) else { return }
        await auth.signIn(baseURL: url, database: database, login: login, apiKey: apiKey)
    }
}
