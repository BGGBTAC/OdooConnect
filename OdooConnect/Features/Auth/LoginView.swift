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
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    brandBanner

                    serverField

                    primaryAction

                    advancedDisclosure
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.xxxl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.pageVeil.ignoresSafeArea())
            .navigationBarHidden(true)
            .onSubmit { advanceFocus() }
        }
    }

    // MARK: - Sections

    private var brandBanner: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: "bolt.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                }
                Text("OdooCompanion")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Dein Odoo. In der Hand.")
                    .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text("Verkauf, Lager, Lieferung & Inventur — direkt vom iPhone und iPad.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .cardSurface(.banner)
        .padding(.top, Spacing.lg)
    }

    private var serverField: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label("Odoo Server", systemImage: "server.rack")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("https://mycompany.odoo.com", text: $serverURL)
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .serverURL)
                .submitLabel(.next)
                .padding(.vertical, Spacing.sm)
            if let hint = serverURLHint {
                Label(hint, systemImage: "exclamationmark.shield.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
            }
        }
        .cardSurface(.standard)
    }

    /// Returns the server URL only if it's a syntactically valid HTTPS URL
    /// with a host. http://, file://, ftp:// etc. are rejected here so the
    /// API key can never be sent over a cleartext channel.
    private var validServerURL: URL? {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let url = URL(string: trimmed),
            url.scheme?.lowercased() == "https",
            let host = url.host(), !host.isEmpty
        else { return nil }
        return url
    }

    private var serverURLHint: String? {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, validServerURL == nil else { return nil }
        if let url = URL(string: trimmed), url.scheme?.lowercased() == "http" {
            return "Nur HTTPS — über HTTP würde dein API-Key im Klartext übertragen."
        }
        return "Bitte vollständige HTTPS-URL eintragen, z.B. https://mycompany.odoo.com"
    }

    private var primaryAction: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                Task { await performOAuth() }
            } label: {
                HStack(spacing: Spacing.sm) {
                    if oauthInFlight {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "globe")
                            .font(.headline)
                    }
                    Text("Über Browser anmelden")
                        .font(.headline.weight(.semibold))
                    Spacer()
                    if !oauthInFlight {
                        Image(systemName: "arrow.right")
                            .font(.subheadline.weight(.bold))
                            .opacity(0.85)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md + 2)
                .frame(maxWidth: .infinity)
                .background(Theme.bannerGradient, in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(validServerURL == nil || oauthInFlight)
            .opacity((validServerURL == nil || oauthInFlight) ? 0.55 : 1.0)
            .animation(.snappy, value: oauthInFlight)

            if let oauthError {
                bridgeMissingHint(message: oauthError)
            } else {
                Text("Funktioniert mit Passwort, Google, Microsoft — alles was dein Odoo unterstützt. Setzt das `odooconnect_bridge` Modul auf dem Server voraus.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Spacing.sm)
            }
        }
    }

    @ViewBuilder
    private func bridgeMissingHint(message: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label("Browser-Login hat nicht zurück zur App geleitet", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.warning)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Wahrscheinlichste Ursache:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("Das `odooconnect_bridge` Odoo-Modul ist auf deinem Server nicht installiert. Ohne dieses Modul gibt es keinen Endpoint, der einen API-Key generiert und zur App zurückleitet — du landest stattdessen im normalen Odoo Backend.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, Spacing.xs)

            VStack(alignment: .leading, spacing: 4) {
                Text("Test:")
                    .font(.caption.weight(.semibold))
                Text("Öffne in Safari (eingeloggt in Odoo): \(testURL)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("Erscheint die Seite \"Erfolg / wirst zurückgeleitet\" - alles ok. Bei 404 fehlt das Modul.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, Spacing.xs)

            Text("Wenn der Test funktioniert aber der App-Login trotzdem im /web hängenbleibt: prüfe Odoo Server Logs auf \"OdooConnect bridge minted API key\".")
                .font(.caption.italic())
                .foregroundStyle(.tertiary)
                .padding(.top, Spacing.xs)
        }
        .cardSurface(.inset)
    }

    private var testURL: String {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "\(trimmed)/api/odooconnect/oauth_complete?state=diagnostic"
    }

    private var advancedDisclosure: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            VStack(spacing: Spacing.md) {
                inputField(
                    "Datenbank", systemImage: "cylinder.split.1x2",
                    text: $database, focus: .database, submit: .next
                )
                inputField(
                    "E-Mail oder Login", systemImage: "person.fill",
                    text: $login, focus: .login, submit: .next, content: .username
                )
                secureField(
                    "API-Key", systemImage: "key.fill",
                    text: $apiKey, focus: .apiKey
                )
                Button {
                    focusedField = nil
                    Task { await performManualSignIn() }
                } label: {
                    HStack {
                        if auth.state == .signingIn {
                            ProgressView().tint(.primary)
                        } else {
                            Text("Mit API-Key anmelden")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .disabled(!canSubmitManual || auth.state == .signingIn)
                .padding(.top, Spacing.xs)

                if let err = auth.lastError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.danger)
                }
                Text("API-Keys erstellst du in Odoo unter Einstellungen → Benutzer → Konto-Sicherheit → API-Keys.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, Spacing.md)
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "key.horizontal")
                    .foregroundStyle(Theme.slate)
                Text("Manuell mit API-Key")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
        .tint(Theme.slate)
        .cardSurface(.inset)
    }

    @ViewBuilder
    private func inputField(
        _ title: String,
        systemImage: String,
        text: Binding<String>,
        focus: Field,
        submit: SubmitLabel,
        content: UITextContentType? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(content)
                .focused($focusedField, equals: focus)
                .submitLabel(submit)
        }
    }

    @ViewBuilder
    private func secureField(
        _ title: String,
        systemImage: String,
        text: Binding<String>,
        focus: Field
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            SecureField(title, text: text)
                .textContentType(.password)
                .focused($focusedField, equals: focus)
                .submitLabel(.go)
        }
    }

    // MARK: - Helpers

    private var canSubmitManual: Bool {
        validServerURL != nil &&
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
        guard let url = validServerURL else { return }
        await auth.signIn(baseURL: url, database: database, login: login, apiKey: apiKey)
    }

    private func performOAuth() async {
        guard let url = validServerURL else { return }
        oauthError = nil
        oauthInFlight = true
        let startedAt = Date()
        defer { oauthInFlight = false }
        do {
            let result = try await oauthClient.signIn(serverURL: url)
            await auth.completeOAuth(serverURL: url, result: result)
        } catch OAuthError.cancelled {
            // If the user spent enough time in the browser to plausibly
            // have logged in, treat the cancel as "the bridge endpoint
            // didn't redirect me back" — most often the bridge module
            // isn't installed yet. < 2s → genuine intentional cancel.
            if Date().timeIntervalSince(startedAt) > 2 {
                oauthError = "Der Browser wurde geschlossen ohne dass die App eine Antwort vom Server bekommen hat."
            }
        } catch {
            oauthError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
