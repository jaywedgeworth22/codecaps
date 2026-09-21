import XCTest
@testable import QuotaCore

/// `LocalQuotaSnapshot.isUserSafe` is the gate between the in-memory issue
/// string and the bytes that reach `quota-windows.json`.  A leak here lands
/// a token, a path, or a header on disk — the failure mode the whole file
/// was written to avoid.  These cases cover the audit-#9 A9-11 gap and the
/// dangerous-copy shapes the file's docstring promises are caught.
final class DangerousCopyTests: XCTestCase {
    func testRejectsBearerHeaderForms() {
        // All four shapes a header line can take after lowercasing.
        XCTAssertFalse(LocalQuotaSnapshot.isUserSafe("Authorization: Bearer abc"))
        XCTAssertFalse(LocalQuotaSnapshot.isUserSafe("Bearer=abc"))
        XCTAssertFalse(LocalQuotaSnapshot.isUserSafe("Bearer:abc"))
        XCTAssertFalse(LocalQuotaSnapshot.isUserSafe("Bearer\tabc"))
    }

    func testRejectsUppercasePEMMarker() {
        XCTAssertFalse(LocalQuotaSnapshot.isUserSafe("Failed: -----BEGIN RSA PRIVATE KEY-----"))
        XCTAssertFalse(LocalQuotaSnapshot.isUserSafe("Failed: -----BEGIN PRIVATE KEY-----"))
    }

    func testRejectsJWTHeaderFragment() {
        // First 32 chars of a real JWT header.  `eyJ` is enough on its own.
        XCTAssertFalse(LocalQuotaSnapshot.isUserSafe("Authorization: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.payload"))
    }

    func testRejectsAbsolutePath() {
        XCTAssertFalse(LocalQuotaSnapshot.isUserSafe("Read /Users/jay/.config/foo failed"))
        XCTAssertFalse(LocalQuotaSnapshot.isUserSafe("Read /home/jay/.config/foo failed"))
        XCTAssertFalse(LocalQuotaSnapshot.isUserSafe("Read ~/Library/secrets.txt failed"))
    }

    func testRejectsVendorKeyPrefixes() {
        XCTAssertFalse(LocalQuotaSnapshot.isUserSafe("Source sk-abc123 returned 401"))
        XCTAssertFalse(LocalQuotaSnapshot.isUserSafe("Source ghp_abc123 returned 401"))
        XCTAssertFalse(LocalQuotaSnapshot.isUserSafe("Source xai-abc123 returned 401"))
        XCTAssertFalse(LocalQuotaSnapshot.isUserSafe("Source github_pat_abc123 returned 401"))
    }

    func testRejectsLongUnbrokenToken() {
        // 20+ chars, letters and digits, no spaces — what a secret looks like.
        XCTAssertFalse(LocalQuotaSnapshot.isUserSafe("Failed with code AbCdEfGhIjKlMnOpQrStUvWxYz1234567890"))
    }

    func testRejectsEmailAddress() {
        XCTAssertFalse(LocalQuotaSnapshot.isUserSafe("Quota for jay@example.com is unavailable"))
    }

    func testAcceptsPlainProse() {
        XCTAssertTrue(LocalQuotaSnapshot.isUserSafe("Codex returned no readable quota windows."))
        XCTAssertTrue(LocalQuotaSnapshot.isUserSafe("Cursor key expired.  Re-authenticate."))
    }

    func testRejectsExcessivelyLongString() {
        let long = String(repeating: "ok ", count: 200)
        XCTAssertFalse(LocalQuotaSnapshot.isUserSafe(long))
    }

    func testRejectsControlCharacters() {
        XCTAssertFalse(LocalQuotaSnapshot.isUserSafe("Failed\u{0001}to read"))
    }
}
