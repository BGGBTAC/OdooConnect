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
        }
        .cardSurface(.standard)
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
                .shadow(color: Theme.brand.opacity(0.45), radius: 16, x: 0, y: 8)
            }
            .buttonStyle(.plain)
            .disabled(URL(string: serverURL) == nil || oauthInFlight)
            .opacity((URL(string: serverURL) == nil || oauthInFlight) ? 0.55 : 1.0)
            .animation(.snappy, value: oauthInFlight)

            if let oauthError {
                Label(oauthError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal, Spacing.sm)
            } else {
                Text("Funktioniert mit Passwort, Google, Microsoft — alles was dein Odoo unterstützt. Setzt das `odooconnect_bridge` Modul auf dem Server voraus.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Spacing.sm)
            }
        }
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
