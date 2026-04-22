import Foundation

enum OdooError: LocalizedError, Sendable {
    case invalidCredentials
    case transport(Error)
    case httpStatus(Int)
    case server(code: Int, message: String, data: String?)
    case unexpectedResponse(String)
    case notAuthenticated

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
        }
    }
}
