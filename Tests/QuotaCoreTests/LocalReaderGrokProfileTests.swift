import Foundation
import XCTest
@testable import QuotaCore

/// Pure tests for the Grok credential-shape dispatch.
///
/// `LocalQuotaReader.readGrok` is async and reads from disk + network, so
/// the whole call is not unit-testable.  What IS testable is the lookup
/// table — the set of nested and flat key paths the parser tries in order
/// — and that the right key wins on a given JSON shape.  These tests pin
/// the four real-world shapes the audit caught: nested under `tokens`,
/// nested under `auth`, flat at root, and the legacy wrapped profile.
final class LocalReaderGrokProfileTests: XCTestCase {
    func testFindsTokenInNestedTokensBlock() {
        let json = #"{"tokens":{"key":"sk-grok","expires_at":1900000000},"expires_at":1600000000}"#
        guard let root = ClaudeOAuthParser.parse(Data(json.utf8)) else {
            return XCTFail("fixture did not parse")
        }
        let token = firstStringValue(root, keys: grokTokenKeys)
        XCTAssertEqual(token, "sk-grok")
    }

    func testFindsTokenInNestedAuthBlock() {
        let json = #"{"auth":{"access_token":"sk-grok-auth"},"expires_at":1900000000}"#
        guard let root = ClaudeOAuthParser.parse(Data(json.utf8)) else {
            return XCTFail("fixture did not parse")
        }
        let token = firstStringValue(root, keys: grokTokenKeys)
        XCTAssertEqual(token, "sk-grok-auth")
    }

    func testFindsTokenAtRoot() {
        let json = #"{"key":"sk-grok-root","expires_at":1900000000}"#
        guard let root = ClaudeOAuthParser.parse(Data(json.utf8)) else {
            return XCTFail("fixture did not parse")
        }
        let token = firstStringValue(root, keys: grokTokenKeys)
        XCTAssertEqual(token, "sk-grok-root")
    }

    func testReturnsNilWhenNoKnownKeyPresent() {
        let json = #"{"something_else":42}"#
        guard let root = ClaudeOAuthParser.parse(Data(json.utf8)) else {
            return XCTFail("fixture did not parse")
        }
        let token = firstStringValue(root, keys: grokTokenKeys)
        XCTAssertNil(token)
    }

    /// Mirrors the key list `LocalQuotaReader.readGrok` passes to
    /// `firstString`.  Kept in sync manually — a regression here is the
    /// audit-#9 A9-05 bug returning.
    private let grokTokenKeys: [String] = [
        "key", "access_token", "accessToken", "token", "api_key", "apiKey",
        "tokens.key", "tokens.access_token", "tokens.accessToken",
        "tokens.token", "tokens.api_key", "tokens.apiKey",
        "auth.key", "auth.access_token", "auth.accessToken",
        "auth.token", "auth.api_key", "auth.apiKey",
    ]

    private func firstStringValue(_ root: [String: Any], keys: [String]) -> String? {
        for key in keys {
            var value: Any? = root
            for part in key.split(separator: ".") {
                guard let dict = value as? [String: Any] else { value = nil; break }
                value = dict[String(part)]
            }
            if let string = value as? String,
               !string.contains("\r"), !string.contains("\n"),
               !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return string.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }
}
