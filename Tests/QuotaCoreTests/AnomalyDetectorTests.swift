import Foundation
import XCTest
@testable import QuotaCore

/// Pinned unit tests for `AnomalyDetector` — pure logic, no IO.
final class AnomalyDetectorTests: XCTestCase {
    /// A bucket that goes from 100% to 50% over an hour, on a flat baseline
    /// of "no change" — current rate is much higher than baseline.
    func testFlagsHighRateAgainstFlatBaseline() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var samples: [AnomalyDetector.Sample] = []
        // Baseline: 7 days of flat 100% — no depletion.  Sampled twice a
        // day across the week.
        for day in 1...6 {
            let t = now.addingTimeInterval(Double(-day) * 24 * 3600)
            samples.append(.init(providerKey: "anthropic", windowId: "anthropic:5h",
                                 observedAt: t, remainingPercent: 100))
            samples.append(.init(providerKey: "anthropic", windowId: "anthropic:5h",
                                 observedAt: t.addingTimeInterval(12 * 3600),
                                 remainingPercent: 100))
        }
        // Current hour: 100% -> 50% in 30 minutes, then a third sample at
        // 60 minutes, dropping to 0%.
        samples.append(.init(providerKey: "anthropic", windowId: "anthropic:5h",
                             observedAt: now.addingTimeInterval(-1800),
                             remainingPercent: 100))
        samples.append(.init(providerKey: "anthropic", windowId: "anthropic:5h",
                             observedAt: now.addingTimeInterval(-300),
                             remainingPercent: 0))
        let anomalies = AnomalyDetector().evaluate(samples: samples, now: now)
        XCTAssertFalse(anomalies.isEmpty, "Expected at least one anomaly")
        let vsBaseline = anomalies.first { $0.kind == .vsBaseline }
        XCTAssertNotNil(vsBaseline)
        XCTAssertEqual(vsBaseline?.providerKey, "anthropic")
        // The bucket drained at 100%/hour; baseline is ~0%/hour, so the
        // ratio is effectively infinite.  Capped by what the LS slope
        // computes; the exact value depends on sample spacing, but it is
        // comfortably above the 5× default threshold.
        XCTAssertGreaterThanOrEqual(vsBaseline?.multiplier ?? 0, 5.0)
    }

    /// A bucket whose current rate matches the baseline — should NOT fire.
    func testDoesNotFlagSteadyUsage() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var samples: [AnomalyDetector.Sample] = []
        // Baseline: drop 0.5 % per day, every day, for 6 days.  That gives a
        // constant pairwise rate of 0.5 / 24 = 0.0208 %/h — the baseline.
        // `day` is the number of full days before `now`.
        for day in 1...6 {
            let t = now.addingTimeInterval(-Double(day) * 24 * 3600)
            samples.append(.init(providerKey: "anthropic", windowId: "anthropic:5h",
                                 observedAt: t, remainingPercent: 100 - Double(day) * 0.5))
        }
        // Current hour: drop at the same 0.0208 %/h pace.  In 25 minutes the
        // expected drop is 0.0208 × (25 / 60) ≈ 0.0087 %.
        let drop = 0.0208 * (25.0 / 60.0)
        samples.append(.init(providerKey: "anthropic", windowId: "anthropic:5h",
                             observedAt: now.addingTimeInterval(-1800),
                             remainingPercent: 97.0))
        samples.append(.init(providerKey: "anthropic", windowId: "anthropic:5h",
                             observedAt: now.addingTimeInterval(-300),
                             remainingPercent: 97.0 - drop))
        let anomalies = AnomalyDetector().evaluate(samples: samples, now: now)
        XCTAssertTrue(anomalies.isEmpty, "Steady usage should not flag any anomaly, got \(anomalies)")
    }

    /// A bucket whose current rate is much higher than the prior-week peak —
    /// fires `vsPeak` but not necessarily `vsBaseline`.
    func testFlagsRateAbovePriorPeak() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var samples: [AnomalyDetector.Sample] = []
        // Prior week: a sharp one-hour drop of 30%, then flat — that is
        // the prior peak rate.
        for day in 1...6 {
            let t = now.addingTimeInterval(Double(-day) * 24 * 3600)
            samples.append(.init(providerKey: "anthropic", windowId: "anthropic:5h",
                                 observedAt: t, remainingPercent: 100))
        }
        // Three days ago, peak hour.
        let peakHourStart = now.addingTimeInterval(-3 * 24 * 3600)
        samples.append(.init(providerKey: "anthropic", windowId: "anthropic:5h",
                             observedAt: peakHourStart, remainingPercent: 100))
        samples.append(.init(providerKey: "anthropic", windowId: "anthropic:5h",
                             observedAt: peakHourStart.addingTimeInterval(3600),
                             remainingPercent: 70))
        // Current hour: drop 90% in 30 minutes — well above the prior peak.
        samples.append(.init(providerKey: "anthropic", windowId: "anthropic:5h",
                             observedAt: now.addingTimeInterval(-1800),
                             remainingPercent: 100))
        samples.append(.init(providerKey: "anthropic", windowId: "anthropic:5h",
                             observedAt: now.addingTimeInterval(-300),
                             remainingPercent: 10))
        let anomalies = AnomalyDetector().evaluate(samples: samples, now: now)
        let vsPeak = anomalies.first { $0.kind == .vsPeak }
        XCTAssertNotNil(vsPeak, "Expected a vsPeak anomaly; got \(anomalies.map(\.summary))")
        XCTAssertEqual(vsPeak?.providerKey, "anthropic")
    }

    /// Two separate provider/window pairs should produce separate entries.
    func testMultipleBucketsReportedIndependently() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var samples: [AnomalyDetector.Sample] = []
        // Anthropic 5h: flat baseline.
        for day in 1...6 {
            let t = now.addingTimeInterval(Double(-day) * 24 * 3600)
            samples.append(.init(providerKey: "anthropic", windowId: "anthropic:5h",
                                 observedAt: t, remainingPercent: 100))
        }
        samples.append(.init(providerKey: "anthropic", windowId: "anthropic:5h",
                             observedAt: now.addingTimeInterval(-1800),
                             remainingPercent: 100))
        samples.append(.init(providerKey: "anthropic", windowId: "anthropic:5h",
                             observedAt: now.addingTimeInterval(-300),
                             remainingPercent: 0))
        // Cursor weekly: also flat baseline, also draining fast.
        for day in 1...6 {
            let t = now.addingTimeInterval(Double(-day) * 24 * 3600)
            samples.append(.init(providerKey: "cursor", windowId: "cursor:weekly",
                                 observedAt: t, remainingPercent: 100))
        }
        samples.append(.init(providerKey: "cursor", windowId: "cursor:weekly",
                             observedAt: now.addingTimeInterval(-1800),
                             remainingPercent: 100))
        samples.append(.init(providerKey: "cursor", windowId: "cursor:weekly",
                             observedAt: now.addingTimeInterval(-300),
                             remainingPercent: 5))
        let anomalies = AnomalyDetector().evaluate(samples: samples, now: now)
        let keys = Set(anomalies.map { "\($0.providerKey)/\($0.windowId)" })
        XCTAssertTrue(keys.contains("anthropic/anthropic:5h"))
        XCTAssertTrue(keys.contains("cursor/cursor:weekly"))
    }

    /// Bucket ID suffix after the last colon becomes the human label.
    func testWindowLabelExtractsCadence() {
        XCTAssertEqual(AnomalyDetector.windowLabel(windowId: "anthropic:5h"), "5h")
        XCTAssertEqual(AnomalyDetector.windowLabel(windowId: "cursor:weekly"), "weekly")
        XCTAssertEqual(AnomalyDetector.windowLabel(windowId: "noColon"), "noColon")
    }
}
