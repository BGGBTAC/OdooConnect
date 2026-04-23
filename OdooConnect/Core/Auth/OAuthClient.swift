import Foundation
import AuthenticationServices
import Synchronization
import UIKit

/// Drives the browser-based sign-in flow against Odoo. Opens
/// `/web/login?redirect=/api/odooconnect/oauth_complete` in
/// `ASWebAuthenticationSession`, lets the user authenticate by any means
/// the server supports (password, Google, Microsoft, SAML, …), and
/// receives the resulting API key over a custom URL scheme.
///
/// Requires the `odooconnect_bridge` Odoo module to be installed on the
/// target server — without it, the redirect URL 404s and the flow throws
/// `OAuthError.bridgeMissing`.
@MainActor
final class OAuthClient {
    static let callbackScheme = "odooconnect"
    private static let callbackHost = "oauth-callback"
    private static let bridgePath = "/api/odooconnect/oauth_complete"

    private let presentationProvider = OAuthPresentationProvider()

    func signIn(serverURL: URL) async throws -> OAuthResult {
        let authURL = Self.buildAuthURL(serverURL: serverURL)

        // ASWebAuthenticationSession on iOS 26 sometimes fires the
        // completion handler twice (once on URL intercept, once on the
        // session's own dismissal), and `session.start()` returning
        // `false` after a queued completion handler can race the same
        // way. Wrap the resume in an idempotency guard so a second
        // call is a no-op instead of crashing CheckedContinuation.
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
            // Don't share Odoo cookies with the user's regular Safari —
            // the OAuth session here is single-purpose.
            session.prefersEphemeralWebBrowserSession = true
            if !session.start() {
                single.resume {
                    continuation.resume(throwing: OAuthError.failedToStart)
                }
            }
        }

        return try OAuthResult(callback: callbackURL)
    }

    /// Open the bridge endpoint directly. Odoo's `auth='user'` machinery
    /// will detect "no session" and redirect to its own login page with the
    /// proper `?redirect=` already set internally — far more reliable than
    /// us hand-crafting `/web/login?redirect=...`, which Odoo sometimes
    /// drops across OAuth-provider round-trips.
    private static func buildAuthURL(serverURL: URL) -> URL {
        serverURL.appendingPathComponent(bridgePath)
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

/// Strongly-typed payload received over `odooconnect://oauth-callback`.
struct OAuthResult: Sendable {
    let apiKey: String
    let uid: Int
    let login: String
    let database: String

    init(callback: URL) throws {
        guard let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              let items = components.queryItems else {
            throw OAuthError.malformedCallback
        }
        let dict = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        guard let apiKey = dict["api_key"], !apiKey.isEmpty,
              let uidString = dict["uid"], let uid = Int(uidString),
              let login = dict["login"], !login.isEmpty,
              let database = dict["database"], !database.isEmpty
        else {
            throw OAuthError.malformedCallback
        }
        self.apiKey = apiKey
        self.uid = uid
        self.login = login
        self.database = database
    }
}

enum OAuthError: LocalizedError {
    case cancelled
    case failedToStart
    case malformedCallback
    case bridgeMissing
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Anmeldung wurde abgebrochen."
        case .failedToStart:
            return "Browser-Anmeldung konnte nicht gestartet werden."
        case .malformedCallback:
            return "Antwort vom Server war unvollständig — ist das OdooConnect-Bridge-Modul installiert?"
        case .bridgeMissing:
            return "Auf dem Odoo-Server fehlt das OdooConnect-Bridge-Modul."
        case .underlying(let error):
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// `ASWebAuthenticationSession` needs a `UIWindow` to anchor its
/// presentation. We grab the current key window from the active scene.
/// Tiny mutex around a "did we already resume this continuation" flag.
/// Lives outside the `@MainActor` actor isolation so the iOS-internal
/// completion handler thread can hit it safely. `Mutex` lets the
/// compiler prove `Sendable` correctness without `@unchecked`.
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
            // The user can only tap the OAuth button when at least one
            // window scene exists; the force-unwrap here is for the
            // never-happens path.
            return scene?.windows.first(where: { $0.isKeyWindow })
                ?? ASPresentationAnchor(windowScene: scene!)
        }
    }
}
