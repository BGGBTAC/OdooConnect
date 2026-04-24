import XCTest
@testable import OdooConnect

final class OAuthClientTests: XCTestCase {
    func testOAuthCallbackAcceptsExpectedCodeAndState() throws {
        let url = try XCTUnwrap(URL(string: "odooconnect://oauth-callback?code=abc123&state=nonce"))

        let callback = try OAuthCallback(callback: url, expectedState: "nonce")

        XCTAssertEqual(callback.code, "abc123")
    }

    func testOAuthCallbackRejectsUnexpectedHost() throws {
        let url = try XCTUnwrap(URL(string: "odooconnect://wrong-host?code=abc123&state=nonce"))

        XCTAssertThrowsError(try OAuthCallback(callback: url, expectedState: "nonce"))
    }

    func testOAuthCallbackRejectsStateMismatch() throws {
        let url = try XCTUnwrap(URL(string: "odooconnect://oauth-callback?code=abc123&state=other"))

        XCTAssertThrowsError(try OAuthCallback(callback: url, expectedState: "nonce"))
    }

    func testOAuthExchangeResponseDecodesCredentials() throws {
        let data = try XCTUnwrap("""
        {
          "api_key": "secret",
          "uid": 42,
          "login": "user@example.com",
          "database": "company"
        }
        """.data(using: .utf8))

        let result = try JSONDecoder().decode(OAuthExchangeResponse.self, from: data)

        XCTAssertEqual(result.apiKey, "secret")
        XCTAssertEqual(result.uid, 42)
        XCTAssertEqual(result.login, "user@example.com")
        XCTAssertEqual(result.database, "company")
    }
}
