import Foundation

enum OdooError: LocalizedError, Sendable {
    case invalidCredentials
    case transport(Error)
    case httpStatus(Int)
    case server(code: Int, message: String, data: String?)
    case unexpectedResponse(String)
    case notAuthenticated
    /// Optimistic-concurrency conflict: the record's `write_date` on the
    /// server has moved since the client last read it, i.e. somebody
    /// else saved changes in between. The caller is expected to surface
    /// a "reload" UX rather than retry the write.
    case conflict(model: String, id: Int)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Login or API key is invalid."
        case .transport(let error):
            return "Network error: \(error.localizedDescription)"
        case .httpStatus(let code):
            return "Server returned HTTP \(code)."
        case .server(_, let message, let data):
            return data ?? message
        case .unexpectedResponse(let detail):
            return "Unexpected server response: \(detail)"
        case .notAuthenticated:
            return "Not signed in."
        case .conflict:
            return "Diese Daten wurden zwischenzeitlich von einer anderen Stelle geändert. Bitte aktualisiere die Ansicht und versuche es erneut."
        }
    }
}
