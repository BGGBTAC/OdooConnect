import Foundation
import Observation

@Observable
@MainActor
final class AuthManager {
    enum State: Equatable {
        case signedOut
        case signingIn
        case signedIn(OdooClient.Config, uid: Int)
    }

    private(set) var state: State = .signedOut
    private(set) var client: OdooClient?
    private(set) var company: Company?
    private(set) var companyCurrency: Currency = .eur
    var lastError: String?

    private let configKey = "odoo.config"
    private let apiKeyKey = "odoo.apiKey"
    private let uidKey = "odoo.uid"

    init() {
        restore()
    }

    func signIn(baseURL: URL, database: String, login: String, apiKey: String) async {
        // Belt-and-braces: LoginView already enforces this, but a future
        // caller (deep link, restored config) might forget. Refusing
        // anything but HTTPS here means the API key can never leave the
        // device over a cleartext channel.
        guard baseURL.scheme?.lowercased() == "https" else {
            self.lastError = "Server-URL muss HTTPS verwenden."
            self.state = .signedOut
            return
        }
        state = .signingIn
        lastError = nil
        do {
            let uid = try await OdooClient.authenticate(
                baseURL: baseURL,
                database: database,
                login: login,
                apiKey: apiKey
            )
            let config = OdooClient.Config(baseURL: baseURL, database: database, login: login)
            try persist(config: config, apiKey: apiKey, uid: uid)
            self.client = OdooClient(config: config, apiKey: apiKey, uid: uid)
            self.state = .signedIn(config, uid: uid)
            await refreshCompanyContext()
        } catch {
            self.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            self.state = .signedOut
        }
    }

    /// Used by the browser-based OAuth flow: the bridge module on the server
    /// already minted an API key, so we skip `OdooClient.authenticate` and
    /// jump straight to building the client + persisting credentials.
    func completeOAuth(serverURL: URL, result: OAuthResult) async {
        state = .signingIn
        lastError = nil
        let config = OdooClient.Config(
            baseURL: serverURL,
            database: result.database,
            login: result.login
        )
        do {
            try persist(config: config, apiKey: result.apiKey, uid: result.uid)
            self.client = OdooClient(config: config, apiKey: result.apiKey, uid: result.uid)
            self.state = .signedIn(config, uid: result.uid)
            await refreshCompanyContext()
        } catch {
            self.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            self.state = .signedOut
        }
    }

    func signOut() {
        KeychainStore.remove(configKey)
        KeychainStore.remove(apiKeyKey)
        KeychainStore.remove(uidKey)
        client = nil
        company = nil
        companyCurrency = .eur
        state = .signedOut
    }

    /// Loads the user's main company and its currency. Called on sign-in and
    /// lazily on app launch when restoring an existing session. No-op unless
    /// we hold a real, signed-in UID.
    func refreshCompanyContext() async {
        guard
            case .signedIn(_, let uid) = state,
            uid > 0,
            let client
        else { return }

        do {
            let users: [UserCompanyDTO] = try await client.searchRead(
                model: "res.users",
                domain: [.array([.string("id"), .string("="), .int(uid)])],
                fields: ["company_id"],
                limit: 1
            )
            guard let companyId = users.first?.company_id.id, companyId > 0 else { return }

            let companies: [Company] = try await client.searchRead(
                model: "res.company",
                domain: [.array([.string("id"), .string("="), .int(companyId)])],
                fields: Company.fields,
                limit: 1
            )
            guard let company = companies.first else { return }
            self.company = company

            let currencies: [Currency] = try await client.searchRead(
                model: "res.currency",
                domain: [.array([.string("id"), .string("="), .int(company.currency_id.id)])],
                fields: Currency.fields,
                limit: 1
            )
            if let currency = currencies.first {
                self.companyCurrency = currency
            }
        } catch {
            // Non-fatal — fall back to EUR until the next refresh succeeds.
            self.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func persist(config: OdooClient.Config, apiKey: String, uid: Int) throws {
        let data = try JSONEncoder().encode(config)
        guard let json = String(data: data, encoding: .utf8) else { return }
        try KeychainStore.set(json, for: configKey)
        try KeychainStore.set(apiKey, for: apiKeyKey)
        try KeychainStore.set(String(uid), for: uidKey)
    }

    private func restore() {
        guard
            let json = KeychainStore.get(configKey),
            let data = json.data(using: .utf8),
            let config = try? JSONDecoder().decode(OdooClient.Config.self, from: data),
            let apiKey = KeychainStore.get(apiKeyKey),
            let uidString = KeychainStore.get(uidKey),
            let uid = Int(uidString)
        else { return }
        self.client = OdooClient(config: config, apiKey: apiKey, uid: uid)
        self.state = .signedIn(config, uid: uid)
        Task { await refreshCompanyContext() }
    }
}

private struct UserCompanyDTO: Decodable, Sendable {
    let company_id: Many2One
}
