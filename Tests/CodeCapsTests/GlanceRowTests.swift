import XCTest
@testable import CodeCaps
import QuotaCore

/// Pins Glance popover layout helpers so future refactors of `GlanceRow` cannot
/// silently change the visible countdown format and trip an owner who has
/// learned what "5h 12m" or "12h 30m" means at a glance.
///
/// SwiftUI view bodies are not exercised directly (the codebase uses plain
/// XCTest, not ViewInspector).  The free helper that produces the trailing
/// column's countdown is the surface that actually drives the row's text and
/// that the popover depends on for every row, so it is the right thing to
/// lock down.
final class GlanceRowTests: XCTestCase {
    func testCountdownReturnsEmptyStringForNilReset() {
        let result = glanceResetCountdown(nil, now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(result, "")
    }

    func testCountdownReturnsDueForPastReset() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let reset = now.addingTimeInterval(-60)
        XCTAssertEqual(glanceResetCountdown(reset, now: now), "due")
    }

    func testCountdownRoundsUpToWholeMinute() {
        // The popover shows time in whole minutes; any sub-minute remainder
        // rounds up so a window with 30.4s left reads "1m", not "0m".
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let reset = now.addingTimeInterval(30)
        XCTAssertEqual(glanceResetCountdown(reset, now: now), "1m")
    }

    func testCountdownFormatSwitchesFromMinutesToHours() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let in59min = now.addingTimeInterval(59 * 60)
        let in60min = now.addingTimeInterval(60 * 60)
        let in61min = now.addingTimeInterval(61 * 60)
        XCTAssertEqual(glanceResetCountdown(in59min, now: now), "59m")
        XCTAssertEqual(glanceResetCountdown(in60min, now: now), "1h 0m")
        XCTAssertEqual(glanceResetCountdown(in61min, now: now), "1h 1m")
    }

    func testCountdownFormatSwitchesFromHoursToDays() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let daySeconds: TimeInterval = 24 * 60 * 60
        let in23h59m = now.addingTimeInterval(23 * 60 * 60 + 59 * 60)
        let in24h = now.addingTimeInterval(daySeconds)
        let in25h = now.addingTimeInterval(daySeconds + 60 * 60)
        XCTAssertEqual(glanceResetCountdown(in23h59m, now: now), "23h 59m")
        XCTAssertEqual(glanceResetCountdown(in24h, now: now), "1d 0h")
        XCTAssertEqual(glanceResetCountdown(in25h, now: now), "1d 1h")
    }

    func testCountdownFitsInTrailingColumnForCodepath() {
        // The trailing column on the popover is fixed at 64pt wide.  Any
        // countdown value that would clip in that column is a layout bug;
        // a regression here is a regression of the PR-#38 width bump.
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let values: [String] = [
            glanceResetCountdown(now.addingTimeInterval(60), now: now),
            glanceResetCountdown(now.addingTimeInterval(60 * 60 + 50 * 60), now: now),
            glanceResetCountdown(now.addingTimeInterval(2 * 24 * 60 * 60 + 5 * 60 * 60), now: now),
        ]
        for value in values {
            // Five characters is the most the column has been shown to fit
            // in practice after the widen; longer strings have already been
            // observed to clip in the screenshot that drove PR #38.
            XCTAssertLessThanOrEqual(value.count, 6,
                "countdown '\(value)' is longer than the 64pt trailing column can render")
        }
    }
}
