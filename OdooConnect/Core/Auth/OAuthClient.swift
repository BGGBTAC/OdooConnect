import Foundation
import AuthenticationServices
import Security
import Synchronization
import UIKit

/// Drives the browser-based sign-in flow against Odoo. The browser callback
/// carries only a short-lived one-time code; the app exchanges that code for
/// the API key over HTTPS so credentials never appear in a custom-scheme URL.
///
/// Requires the `odooconnect_bridge` module on the target server.
@MainActor
final class OAuthClient {
    static let callbackScheme = "odooconnect"
    static let callbackHost = "oauth-callback"
    private static let bridgePath = "/api/odooconnect/oauth_complete"
    private static let exchangePath = "/api/odooconnect/oauth_exchange"

    private let presentationProvider = OAuthPresentationProvider()

    func signIn(serverURL: URL) async throws -> OAuthResult {
        let state = Self.makeState()
        let authURL = Self.buildAuthURL(serverURL: serverURL, state: state)

        // ASWebAuthenticationSession on iOS 26 sometimes fires the
        // completion handler twice (once on URL intercept, once on the
        // session's own dismissal), and `session.start()` returning
        // `false` after a queued completion handler can race the same way.
        let single = SingleResume()

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: Self.callbackScheme
            ) { url, error in
                single.resume {
                    if let error {
                        continuation.resume(throwing: Self.translate(error))
                    } else if let url {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: OAuthError.cancelled)
                    }
                }
            }
            session.presentationContextProvider = presentationProvider
            session.prefersEphemeralWebBrowserSession = true
            if !session.start() {
                single.resume {
                    continuation.resume(throwing: OAuthError.failedToStart)
                }
            }
        }

        let callback = try OAuthCallback(callback: callbackURL, expectedState: state)
        return try await Self.exchange(callback: callback, serverURL: serverURL)
    }

    /// Open the bridge endpoint directly. Odoo's `auth='user'` machinery
    /// redirects unauthenticated users to its own login page and preserves
    /// the original URL, including our state parameter.
    private static func buildAuthURL(serverURL: URL, state: String) -> URL {
        var components = URLComponents(
            url: appendingOdooPath(bridgePath, to: serverURL),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "state", value: state)]
        return components?.url ?? appendingOdooPath(bridgePath, to: serverURL)
    }

    private static func exchange(callback: OAuthCallback, serverURL: URL) async throws -> OAuthResult {
        var request = URLRequest(url: appendingOdooPath(exchangePath, to: serverURL))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(OAuthExchangeRequest(code: callback.code))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw OAuthError.underlying(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw OAuthError.malformedExchangeResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if let serverError = try? JSONDecoder().decode(OAuthExchangeErrorResponse.self, from: data),
               !serverError.error.isEmpty {
                throw OAuthError.serverMessage(serverError.error)
            }
            throw OAuthError.serverMessage("OAuth-Code konnte nicht eingeloest werden (HTTP \(http.statusCode)).")
        }

        let payload = try JSONDecoder().decode(OAuthExchangeResponse.self, from: data)
        return try OAuthResult(response: payload)
    }

    private static func appendingOdooPath(_ path: String, to serverURL: URL) -> URL {
        guard var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false) else {
            return serverURL.appendingPathComponent(path)
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let childPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, childPath]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        components.query = nil
        components.fragment = nil
        return components.url ?? serverURL.appendingPathComponent(path)
    }

    private static func makeState() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let count = bytes.count
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            return UUID().uuidString + UUID().uuidString
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func translate(_ error: Error) -> OAuthError {
        if let asError = error as? ASWebAuthenticationSessionError {
            switch asError.code {
            case .canceledLogin: return .cancelled
            case .presentationContextInvalid: return .failedToStart
            case .presentationContextNotProvided: return .failedToStart
            @unknown default: return .underlying(error)
            }
        }
        return .underlying(error)
    }
}

/// Payload received over `odooconnect://oauth-callback`.
/// It deliberately contains no secret.
struct OAuthCallback: Sendable {
    let code: String

    init(callback: URL, expectedState: String) throws {
        guard
            callback.scheme?.lowercased() == OAuthClient.callbackScheme,
            callback.host() == OAuthClient.callbackHost,
            let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
            let items = components.queryItems
        else {
            throw OAuthError.malformedCallback
        }

        var dict: [String: String] = [:]
        for item in items {
            dict[item.name] = item.value ?? ""
        }

        guard dict["state"] == expectedState else {
            throw OAuthError.stateMismatch
        }
        guard let code = dict["code"], !code.isEmpty else {
            throw OAuthError.malformedCallback
        }
        self.code = code
    }
}

struct OAuthExchangeRequest: Encodable, Sendable {
    let code: String
}

struct OAuthExchangeResponse: Decodable, Sendable {
    let apiKey: String
    let uid: Int
    let login: String
    let database: String

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case uid, login, database
    }
}

private struct OAuthExchangeErrorResponse: Decodable, Sendable {
    let error: String
}

struct OAuthResult: Sendable {
    let apiKey: String
    let uid: Int
    let login: String
    let database: String

    init(response: OAuthExchangeResponse) throws {
        guard
            !response.apiKey.isEmpty,
            response.uid > 0,
            !response.login.isEmpty,
            !response.database.isEmpty
        else {
            throw OAuthError.malformedExchangeResponse
        }
        self.apiKey = response.apiKey
        self.uid = response.uid
        self.login = response.login
        self.database = response.database
    }
}

enum OAuthError: LocalizedError {
    case cancelled
    case failedToStart
    case malformedCallback
    case stateMismatch
    case malformedExchangeResponse
    case bridgeMissing
    case serverMessage(String)
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Anmeldung wurde abgebrochen."
        case .failedToStart:
            return "Browser-Anmeldung konnte nicht gestartet werden."
        case .malformedCallback:
            return "Antwort vom Server war unvollstaendig. Ist das OdooConnect-Bridge-Modul aktuell installiert?"
        case .stateMismatch:
            return "Browser-Anmeldung wurde aus Sicherheitsgruenden abgebrochen."
        case .malformedExchangeResponse:
            return "Antwort vom Server war unvollstaendig. Bitte OdooConnect-Bridge aktualisieren."
        case .bridgeMissing:
            return "Auf dem Odoo-Server fehlt das OdooConnect-Bridge-Modul."
        case .serverMessage(let message):
            return message
        case .underlying(let error):
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// Tiny mutex around a "did we already resume this continuation" flag.
/// Lives outside the `@MainActor` actor isolation so the iOS-internal
/// completion handler thread can hit it safely.
private final class SingleResume: Sendable {
    private let done = Mutex<Bool>(false)

    func resume(_ work: () -> Void) {
        let shouldRun = done.withLock { state in
            guard !state else { return false }
            state = true
            return true
        }
        if shouldRun { work() }
    }
}

@MainActor
private final class OAuthPresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
            return scene?.windows.first(where: { $0.isKeyWindow })
                ?? ASPresentationAnchor(windowScene: scene!)
        }
    }
}
