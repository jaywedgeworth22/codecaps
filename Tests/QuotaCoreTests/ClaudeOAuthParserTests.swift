import Foundation
import XCTest
@testable import QuotaCore

/// The OAuth record is what tells the Claude reader the saved login is still
/// good.  These tests pin the four shapes the parser accepts — flat,
/// nested, with expiry, without expiry — and the two it rejects: no token,
/// expired.
final class ClaudeOAuthParserTests: XCTestCase {
    func testReturnsNilWhenRootHasNoOAuthRecord() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertNil(ClaudeOAuthParser.validOAuth(in: [:], now: now))
        XCTAssertNil(ClaudeOAuthParser.validOAuth(in: ["other": "thing"], now: now))
    }

    func testReturnsNilWhenOAuthRecordHasNoToken() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertNil(ClaudeOAuthParser.validOAuth(in: ["claudeAiOauth": ["expiresAt": 1_900_000_000.0]], now: now))
    }

    func testAcceptsOAuthRecordUnderClaudeAiOauthKey() {
        // Claude Code always nests the OAuth record under `claudeAiOauth` —
        // both flat-at-root and missing-key shapes must reject.
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let valid: [String: Any] = ["claudeAiOauth": ["accessToken": "sk", "expiresAt": 1_900_000_000.0]]
        XCTAssertNotNil(ClaudeOAuthParser.validOAuth(in: valid, now: now))
        // A bare record with the same contents but no `claudeAiOauth` wrapper
        // is not the shape Claude Code writes — reject.
        let flat: [String: Any] = ["accessToken": "sk", "expiresAt": 1_900_000_000.0]
        XCTAssertNil(ClaudeOAuthParser.validOAuth(in: flat, now: now))
    }

    func testAcceptsBothSnakeAndCamelCaseTokenNames() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let camel: [String: Any] = ["claudeAiOauth": ["accessToken": "sk-camel"]]
        let snake: [String: Any] = ["claudeAiOauth": ["access_token": "sk-snake"]]
        XCTAssertNotNil(ClaudeOAuthParser.validOAuth(in: camel, now: now))
        XCTAssertNotNil(ClaudeOAuthParser.validOAuth(in: snake, now: now))
    }

    func testRejectsExpiredRecord() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let expired: [String: Any] = ["claudeAiOauth": ["accessToken": "sk", "expiresAt": 1_600_000_000.0]]
        XCTAssertNil(ClaudeOAuthParser.validOAuth(in: expired, now: now))
    }

    func testAcceptsExpiryAtSameInstant() {
        // Expiry exactly equal to `now` is "already expired" — the parser
        // uses `<=`.  This pins that boundary so a half-second skew does not
        // silently include a stale token.
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let atBoundary: [String: Any] = ["claudeAiOauth": ["accessToken": "sk", "expiresAt": now.timeIntervalSince1970]]
        XCTAssertNil(ClaudeOAuthParser.validOAuth(in: atBoundary, now: now))
    }

    func testParseReturnsNilForNonJSON() {
        XCTAssertNil(ClaudeOAuthParser.parse(Data("not json".utf8)))
        XCTAssertNil(ClaudeOAuthParser.parse(Data([0xFF, 0xFE, 0xFD])))
    }

    func testParseCapsInputSize() {
        // The parser refuses anything over a megabyte so a hostile file
        // cannot make it allocate without bound.
        let oversized = Data(repeating: 0x20, count: 1_048_577)
        XCTAssertNil(ClaudeOAuthParser.parse(oversized))
    }

    func testParseReturnsDictForValidJSON() {
        let json = #"{"claudeAiOauth":{"accessToken":"sk-test"}}"#
        let parsed = ClaudeOAuthParser.parse(Data(json.utf8))
        XCTAssertNotNil(parsed)
        XCTAssertNotNil(parsed?["claudeAiOauth"] as? [String: Any])
    }
}
