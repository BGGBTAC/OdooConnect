import Foundation

/// Bridge between out-of-process App Intent execution and the
/// in-app session. App Intents run in a separate process when invoked
/// by Siri / Shortcuts / CarPlay / Spotlight, so they can't read the
/// MainActor-isolated AuthManager. They can however reach the same
/// Keychain items the app stored — this helper rehydrates an
/// `OdooClient` from those stored credentials.
enum IntentSession {
    private static let configKey = "odoo.config"
    private static let apiKeyKey = "odoo.apiKey"
    private static let uidKey = "odoo.uid"
    private static let currencyKey = "intent.currencyCode"

    /// Build an OdooClient from persisted credentials. Throws
    /// `IntentError.notSignedIn` when there's no usable session, so
    /// the calling intent can fall back to a friendly Siri dialog.
    static func requireClient() throws -> OdooClient {
        guard
            let json = KeychainStore.get(configKey),
            let data = json.data(using: .utf8),
            let config = try? JSONDecoder().decode(OdooClient.Config.self, from: data),
            let apiKey = KeychainStore.get(apiKeyKey),
            let uidString = KeychainStore.get(uidKey),
            let uid = Int(uidString)
        else {
            throw IntentError.notSignedIn
        }
        return OdooClient(config: config, apiKey: apiKey, uid: uid)
    }

    /// Currency code last seen by the app — populated by
    /// `AuthManager.refreshCompanyContext()` so out-of-process intents
    /// can format amounts in the right currency without a network call.
    /// Falls back to EUR when the user has never opened the app.
    static var cachedCurrencyCode: String {
        UserDefaults.standard.string(forKey: currencyKey) ?? "EUR"
    }

    static func cacheCurrencyCode(_ code: String) {
        UserDefaults.standard.set(code, forKey: currencyKey)
    }
}

enum IntentError: LocalizedError {
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Bitte zuerst in OdooCompanion anmelden, dann erneut versuchen."
        }
    }
}
