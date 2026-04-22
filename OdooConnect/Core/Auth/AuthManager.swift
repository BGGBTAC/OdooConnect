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
    var lastError: String?

    private let configKey = "odoo.config"
    private let apiKeyKey = "odoo.apiKey"
    private let uidKey = "odoo.uid"

    init() {
        restore()
    }

    func signIn(baseURL: URL, database: String, login: String, apiKey: String) async {
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
        state = .signedOut
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
    }
}
