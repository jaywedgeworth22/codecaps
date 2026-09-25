import Security
import XCTest
@testable import CodeCaps

/// `TokenStore` talks to the real Keychain, so only its pure parts are pinned
/// here: which service name a bundle identifier produces, and the state that
/// decides whether a settings group offers Re-Authorize Saved Token.
final class TokenStoreTests: XCTestCase {

    // MARK: Service names

    /// The installed app has to keep the exact service names its existing
    /// Keychain items already carry, or the owner's saved tokens disappear.
    func testReleaseIdentifierKeepsTheShippedServiceNames() {
        XCTAssertEqual(TokenStore.serviceName(suffix: "read-token", bundleIdentifier: "com.jays.agent-bar.mac"),
                       "com.jays.agent-bar.mac.read-token")
        XCTAssertEqual(TokenStore.serviceName(suffix: "sync-token", bundleIdentifier: "com.jays.agent-bar.mac"),
                       "com.jays.agent-bar.mac.sync-token")
    }

    /// A dev build gets its own items, so it can never overwrite or forget the
    /// installed app's tokens.
    func testDevIdentifierGetsItsOwnServiceNames() {
        XCTAssertEqual(TokenStore.serviceName(suffix: "read-token", bundleIdentifier: "com.jays.agent-bar.mac.dev"),
                       "com.jays.agent-bar.mac.dev.read-token")
        XCTAssertNotEqual(TokenStore.serviceName(suffix: "read-token", bundleIdentifier: "com.jays.agent-bar.mac.dev"),
                          TokenStore.serviceName(suffix: "read-token", bundleIdentifier: "com.jays.agent-bar.mac"))
    }

    /// Run from a test host or straight out of `.build` there is no bundle
    /// identifier, and the release name is the safe answer.
    func testMissingOrBlankIdentifierFallsBackToTheReleaseName() {
        for identifier in [nil, "", "   ", "\n"] as [String?] {
            XCTAssertEqual(TokenStore.serviceName(suffix: "read-token", bundleIdentifier: identifier),
                           "com.jays.agent-bar.mac.read-token")
        }
    }

    // MARK: Re-authorize caption

    func testNothingSavedNeedsNoAuthorization() {
        let state = SavedTokenState.resolve(hasSavedFlag: false, silentReadSucceeded: false)
        XCTAssertEqual(state, .none)
        XCTAssertFalse(state.needsReauthorization)
    }

    func testSavedAndReadableNeedsNoAuthorization() {
        let state = SavedTokenState.resolve(hasSavedFlag: true, silentReadSucceeded: true)
        XCTAssertEqual(state, .readable)
        XCTAssertFalse(state.needsReauthorization)
    }

    /// The case the owner actually hit: the flag says a token was saved, and
    /// this build's silent read comes back empty because it is not on the
    /// item's access list.
    func testSavedButUnreadableAsksForAuthorization() {
        let state = SavedTokenState.resolve(hasSavedFlag: true, silentReadSucceeded: false)
        XCTAssertEqual(state, .unreadable)
        XCTAssertTrue(state.needsReauthorization)
    }

    /// A read that succeeds while nothing is on file is still nothing on file —
    /// the flag governs, so a stale read can never light the caption.
    func testFlagGovernsOverTheReadResult() {
        XCTAssertEqual(SavedTokenState.resolve(hasSavedFlag: false, silentReadSucceeded: true), .none)
    }
    // MARK: Save strategy

    /// A delete that removed the item, or found nothing, leaves room for a
    /// clean add.  Anything else means the old item is still there.
    func testCleanDeleteGoesStraightToAdd() {
        XCTAssertFalse(TokenStore.shouldUpdateInPlace(afterDelete: errSecSuccess))
        XCTAssertFalse(TokenStore.shouldUpdateInPlace(afterDelete: errSecItemNotFound))
    }

    /// The owner's case on 2026-09-25: the delete was refused with -25244 and
    /// the add then collided with -25299.  A refused delete must update the
    /// item in place instead of adding a duplicate.
    func testRefusedDeleteUpdatesInPlace() {
        XCTAssertTrue(TokenStore.shouldUpdateInPlace(afterDelete: errSecInvalidOwnerEdit))
        XCTAssertTrue(TokenStore.shouldUpdateInPlace(afterDelete: errSecInteractionNotAllowed))
        XCTAssertTrue(TokenStore.shouldUpdateInPlace(afterDelete: errSecAuthFailed))
    }

    // MARK: Failure wording

    private let service = "com.jays.agent-bar.mac.sync-token"
    private let gap = "\u{00A0} "

    /// Only a locked or refused Keychain asks the owner to unlock it.
    func testOnlyTheLockedCaseAsksForAnUnlock() {
        let locked = TokenStore.writeFailureMessage(status: errSecInteractionNotAllowed, service: service)
        XCTAssertTrue(locked.contains("Unlock your login Keychain"))
        XCTAssertTrue(locked.contains("\(errSecInteractionNotAllowed)"))
        for status in [errSecInvalidOwnerEdit, errSecDuplicateItem, errSecMissingEntitlement, errSecParam] {
            XCTAssertFalse(TokenStore.writeFailureMessage(status: status, service: service).contains("Unlock"),
                           "status \(status) must not blame a locked Keychain")
        }
        XCTAssertFalse(TokenStore.writeFailureMessage(status: nil, service: service).contains("Unlock"))
    }

    /// An old item that cannot be replaced names itself, so the owner knows
    /// exactly what to delete in Keychain Access.
    func testAnItemInTheWayIsNamed() {
        for status in [errSecInvalidOwnerEdit, errSecDuplicateItem] {
            let message = TokenStore.writeFailureMessage(status: status, service: service)
            XCTAssertTrue(message.contains(service))
            XCTAssertTrue(message.contains("Keychain Access"))
            XCTAssertTrue(message.contains("\(status)"))
        }
    }

    /// A call still running at its bound is a panel nobody answered, not a
    /// locked Keychain.
    func testATimeoutPointsAtThePanel() {
        let message = TokenStore.writeFailureMessage(status: nil, service: service)
        XCTAssertTrue(message.contains("30 seconds"))
        XCTAssertTrue(message.contains("panel"))
    }

    /// Anything unrecognized still carries its number.
    func testAnUnknownStatusCarriesItsNumber() {
        XCTAssertTrue(TokenStore.writeFailureMessage(status: -12345, service: service).contains("-12345"))
    }

    /// Two sentences in one string use the no-break-space gap, never one space.
    func testEveryMessageUsesTheSentenceGap() {
        let statuses: [OSStatus?] = [errSecInteractionNotAllowed, errSecInvalidOwnerEdit, errSecMissingEntitlement, nil]
        for status in statuses {
            let message = TokenStore.writeFailureMessage(status: status, service: service)
            XCTAssertTrue(message.contains("." + gap), message)
            XCTAssertFalse(message.contains(". "), message)
        }
    }

    func testTheErrorDescriptionIsTheMessage() {
        let failure = TokenStore.Failure.write(status: errSecInvalidOwnerEdit, service: service)
        XCTAssertEqual(failure.errorDescription,
                       TokenStore.writeFailureMessage(status: errSecInvalidOwnerEdit, service: service))
    }
}
