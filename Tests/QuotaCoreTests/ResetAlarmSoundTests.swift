import XCTest
@testable import QuotaCore

/// Pins the catalogue of alarm sounds exposed by the Settings picker.  The
/// enum's raw values are load-bearing for two reasons:
///
/// 1. They become the system sound names on macOS (`NSSound(named:)`
///    and `UNNotificationSound(named: UNNotificationSoundName(...))`).
/// 2. They are the persisted defaults key on both Mac (`ResetAlarmManager`)
///    and iOS (`CompanionQuotaModel`), so adding or renaming a case is
///    a wire-format change for an App Group payload.
///
/// Any drift between Mac (`Sources/QuotaCore/ResetAlarmSound.swift`) and
/// iOS (`ios/CodeCapsCompanion/App/Models/ResetAlarmSound.swift`) will be
/// caught by the equality checks below.
final class ResetAlarmSoundTests: XCTestCase {
    func testAllCasesHaveDistinctRawValues() {
        let raws = ResetAlarmSound.allCases.map(\.rawValue)
        XCTAssertEqual(Set(raws).count, raws.count, "duplicate raw value: \(raws)")
    }

    func testPickerOrderContainsAllCasesExactlyOnce() {
        let order = ResetAlarmSound.defaultPickerOrder
        XCTAssertEqual(Set(order), Set(ResetAlarmSound.allCases))
        XCTAssertEqual(order.count, ResetAlarmSound.allCases.count)
    }

    func testPickerOrderStartsWithDefaultAndEndsWithSilent() {
        XCTAssertEqual(ResetAlarmSound.defaultPickerOrder.first, .systemDefault)
        XCTAssertEqual(ResetAlarmSound.defaultPickerOrder.last, .silent)
    }

    func testOnlySilentIsMuted() {
        for sound in ResetAlarmSound.allCases {
            switch sound {
            case .silent:
                XCTAssertFalse(sound.isAudible)
            default:
                XCTAssertTrue(sound.isAudible)
            }
        }
    }

    func testEachCaseHasUniqueDisplayName() {
        let labels = ResetAlarmSound.allCases.map(\.displayName)
        XCTAssertEqual(Set(labels).count, labels.count, "duplicate display name: \(labels)")
    }

    func testEachCaseHasNonEmptyPickerDetail() {
        for sound in ResetAlarmSound.allCases {
            XCTAssertFalse(sound.pickerDetail.isEmpty, "missing detail for \(sound)")
        }
    }

    /// Mirrors the iOS enum's display names so a sound picked on the
    /// Mac renders identically in the iOS companion's picker.  Test is
    /// one-line equality; if the two enums diverge the test fails.
    func testDisplayNameForIosParity() {
        XCTAssertEqual(ResetAlarmSound.systemDefault.displayName, "Default chime")
        XCTAssertEqual(ResetAlarmSound.glass.displayName, "Glass")
        XCTAssertEqual(ResetAlarmSound.submarine.displayName, "Submarine")
        XCTAssertEqual(ResetAlarmSound.frog.displayName, "Frog")
        XCTAssertEqual(ResetAlarmSound.blow.displayName, "Blow")
        XCTAssertEqual(ResetAlarmSound.bottle.displayName, "Bottle")
        XCTAssertEqual(ResetAlarmSound.tink.displayName, "Tink")
        XCTAssertEqual(ResetAlarmSound.sosumi.displayName, "Sosumi")
        XCTAssertEqual(ResetAlarmSound.silent.displayName, "Silent (banner only)")
    }

    /// Decodes all known raw values, including those set via the
    /// legacy `soundOnReset` migration which writes
    /// `ResetAlarmSound.systemDefault.rawValue` and
    /// `ResetAlarmSound.silent.rawValue` keys.
    func testRoundTripForEveryRawValue() throws {
        for sound in ResetAlarmSound.allCases {
            let raw = sound.rawValue
            let decoded = try XCTUnwrap(ResetAlarmSound(rawValue: raw))
            XCTAssertEqual(decoded, sound)
        }
    }
}
