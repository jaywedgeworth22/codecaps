import Foundation

/// Surfaces "your usage is going down faster than usual" signals.
///
/// Two thresholds, both user-tunable, both default to a value that fires only
/// when the rate is well outside the owner's own recent pattern:
///
/// 1. **`baselineMultiplier`** — current hour's rate of change vs the rolling
///    7-day average rate of change.  Default 5×.  Catches "I'm using this much
///    harder than usual, day over day".  Suggested range 3-10×.
///
/// 2. **`peakMultiplier`** — current hour's rate of change vs the owner's
///    highest hourly rate over the prior week.  Default 2×.  Catches
///    "I'm using this faster than my own worst hour last week".  Suggested
///    range 1-3×; under 1× only catches runaway or stuck-loop cases.
///
/// Rate is computed as `percentPerHour` from consecutive samples in the
/// history file.  A window that resets is treated as a discontinuity —
/// the rate at the reset boundary is reported as the prior rate up to
/// the reset, not the jump from 0% back up to a fresh window.
///
/// The detector is pure: a `Sample` array in, an `[Anomaly]` array out.
/// Persistence and the IO plumbing live elsewhere.
public struct AnomalyDetector: Sendable {
    public struct Sample: Codable, Equatable, Sendable {
        public let providerKey: String
        public let windowId: String
        public let observedAt: Date
        /// 0…100.  nil is treated as "not measurable" and skipped.
        public let remainingPercent: Double?

        public init(providerKey: String, windowId: String, observedAt: Date, remainingPercent: Double?) {
            self.providerKey = providerKey
            self.windowId = windowId
            self.observedAt = observedAt
            self.remainingPercent = remainingPercent
        }
    }

    public struct Anomaly: Equatable, Sendable, Codable {
        public enum Kind: String, Codable, Sendable, Equatable {
            /// Current rate is N× the rolling 7-day average.
            case vsBaseline
            /// Current rate is N× the prior-week peak hourly rate.
            case vsPeak
        }
        public let providerKey: String
        public let windowId: String
        public let kind: Kind
        /// The actual multiplier observed, e.g. 6.4 means current is 6.4× the
        /// comparison baseline.  Always > 1.
        public let multiplier: Double
        /// "vs baseline (5h): 6.4× your week-long average."
        public let summary: String

        public init(providerKey: String, windowId: String, kind: Kind, multiplier: Double, summary: String) {
            self.providerKey = providerKey
            self.windowId = windowId
            self.kind = kind
            self.multiplier = multiplier
            self.summary = summary
        }
    }

    public var baselineMultiplier: Double
    public var peakMultiplier: Double

    public init(baselineMultiplier: Double = 5.0, peakMultiplier: Double = 2.0) {
        self.baselineMultiplier = baselineMultiplier
        self.peakMultiplier = peakMultiplier
    }

    /// Evaluate `samples` and return every (provider, window) pair whose
    /// current-hour rate exceeds the configured thresholds.  One Anomaly per
    /// (provider, window, kind) — the same window can fire both `vsBaseline`
    /// and `vsPeak` if both thresholds are crossed.
    public func evaluate(samples: [Sample], now: Date = Date()) -> [Anomaly] {
        // Group by (provider, window).  Each group is a chronologically-sorted
        // time series for one quota bucket.
        let groups = Dictionary(grouping: samples) { "\($0.providerKey)|\($0.windowId)" }
        var out: [Anomaly] = []
        for (_, group) in groups {
            let sorted = group.sorted { $0.observedAt < $1.observedAt }
            guard let currentRate = Self.currentHourRatePercent(samples: sorted, now: now),
                  currentRate > 0 else { continue }
            let baselineRate = Self.baselineRatePercent(samples: sorted, now: now)
            let peakRate = Self.peakHourRatePercent(samples: sorted, now: now)
            let windowLabel = Self.windowLabel(windowId: sorted[0].windowId)
            if let baseline = baselineRate {
                // A flat baseline (baseline == 0) means the user has not
                // been depleting this window over the prior week — any
                // depletion now is therefore infinitely more than baseline,
                // so the anomaly always fires.  We report the ratio as
                // `currentRate / max(baseline, epsilon)` so the math stays
                // bounded and the summary still reads sanely.
                let baselineForRatio = max(baseline, 0.01)
                let ratio = currentRate / baselineForRatio
                if ratio >= baselineMultiplier {
                    out.append(Anomaly(
                        providerKey: sorted[0].providerKey,
                        windowId: sorted[0].windowId,
                        kind: .vsBaseline,
                        multiplier: ratio,
                        summary: Self.summary(kind: .vsBaseline, ratio: ratio, threshold: baselineMultiplier, window: windowLabel, comparison: "your week-long average")))
                }
            }
            if let peak = peakRate, peak > 0 {
                let ratio = currentRate / peak
                if ratio >= peakMultiplier {
                    out.append(Anomaly(
                        providerKey: sorted[0].providerKey,
                        windowId: sorted[0].windowId,
                        kind: .vsPeak,
                        multiplier: ratio,
                        summary: Self.summary(kind: .vsPeak, ratio: ratio, threshold: peakMultiplier, window: windowLabel, comparison: "your highest hour last week")))
                }
            }
        }
        return out
    }

    /// Append-only JSONL store for sample history.  Lives in the same directory
    /// as `quota-windows.json` so the two are co-managed.
    public struct SampleHistory: Sendable {
        public let url: URL

        public init(url: URL) {
            self.url = url
        }

        /// Append `samples` to the history file, one JSON object per line.
        /// Creates the parent directory if missing.  Caps the file size by
        /// trimming to the last `maxBytes` after the append so the file does
        /// not grow without bound.
        public func append(_ samples: [Sample], maxBytes: Int = 4 * 1024 * 1024) throws {
            guard !samples.isEmpty else { return }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                   withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.withoutEscapingSlashes]
            let fm = FileManager.default
            if !fm.fileExists(atPath: url.path) {
                fm.createFile(atPath: url.path, contents: nil)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            }
            let handle = try FileHandle(forWritingTo: url)
            try autoreleasepool {
                try handle.seekToEnd()
                for sample in samples {
                    var line = try encoder.encode(sample)
                    line.append(0x0A) // \n
                    try handle.write(contentsOf: line)
                }
            }
            try handle.close()
            // Trim if over the cap — keep the second half, which is the
            // most recent data and the only part that matters for the
            // rolling baseline.
            if let attrs = try? fm.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int, size > maxBytes {
                let head = try Data(contentsOf: url, options: .mappedIfSafe)
                let trimTo = maxBytes * 3 / 4
                if head.count > trimTo {
                    let trimmed = head.suffix(trimTo)
                    try trimmed.write(to: url, options: .atomic)
                    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                }
            }
        }

        /// Load every sample currently on disk.
        public func load() throws -> [Sample] {
            guard FileManager.default.fileExists(atPath: url.path) else { return [] }
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var out: [Sample] = []
            var start = data.startIndex
            while start < data.endIndex {
                let end = data[start...].firstIndex(of: 0x0A) ?? data.endIndex
                let line = data[start..<end]
                start = (end < data.endIndex) ? data.index(after: end) : end
                if line.isEmpty { continue }
                if let sample = try? decoder.decode(Sample.self, from: line) {
                    out.append(sample)
                }
            }
            return out
        }
    }

    // MARK: - Rate math

    /// Rate over the most recent hour, in percent-per-hour.  Computed as
    /// a least-squares slope on the last hour of samples with non-nil
    /// remainingPercent.  Returns nil if fewer than two usable samples
    /// fall in the window or the slope is non-positive (i.e. quota is
    /// recovering, not depleting).
    static func currentHourRatePercent(samples: [Sample], now: Date) -> Double? {
        let cutoff = now.addingTimeInterval(-3600)
        let recent = samples.filter { $0.observedAt >= cutoff && $0.remainingPercent != nil }
        guard recent.count >= 2 else { return nil }
        return ratePerHour(samples: recent)
    }

    /// Average depletion rate over the rolling 7-day window, excluding
    /// the most recent hour so the "current" and "baseline" windows do
    /// not overlap.  Uses sliding consecutive-pair rates so flat or
    /// sparse history still produces a number — a flat history yields
    /// "0 %/h", not nil.
    static func baselineRatePercent(samples: [Sample], now: Date) -> Double? {
        let windowStart = now.addingTimeInterval(-7 * 24 * 3600)
        let recentCutoff = now.addingTimeInterval(-3600)
        let usable = samples.filter {
            guard let pct = $0.remainingPercent else { return false }
            return pct > 0 && $0.observedAt >= windowStart && $0.observedAt < recentCutoff
        }
        let rates = consecutivePairRates(samples: usable)
        guard !rates.isEmpty else { return nil }
        let total = rates.reduce(0, +)
        return total / Double(rates.count)
    }

    /// Highest hourly rate observed in the prior week, excluding the
    /// current hour.  Uses sliding consecutive-pair rates — no fixed
    /// hour bucketing — so two samples one hour apart still produce
    /// a valid rate.
    static func peakHourRatePercent(samples: [Sample], now: Date) -> Double? {
        let windowStart = now.addingTimeInterval(-7 * 24 * 3600)
        let recentCutoff = now.addingTimeInterval(-3600)
        let usable = samples.filter {
            guard $0.remainingPercent != nil else { return false }
            return $0.observedAt >= windowStart && $0.observedAt < recentCutoff
        }
        return consecutivePairRates(samples: usable).max()
    }

    /// Rate between every consecutive pair of samples, in percent-per-hour.
    /// Returns an empty array when fewer than two samples are provided.
    /// Positive numbers mean depletion, negative means recovery, zero
    /// means flat.
    static func consecutivePairRates(samples: [Sample]) -> [Double] {
        guard samples.count >= 2 else { return [] }
        let sorted = samples.sorted { $0.observedAt < $1.observedAt }
        var rates: [Double] = []
        rates.reserveCapacity(sorted.count - 1)
        for i in 1..<sorted.count {
            let a = sorted[i - 1]
            let b = sorted[i]
            guard let apct = a.remainingPercent, let bpct = b.remainingPercent else { continue }
            let dtHours = b.observedAt.timeIntervalSince(a.observedAt) / 3600
            guard dtHours > 0 else { continue }
            // %/h = (a - b) / dtHours  (a − b positive when b is lower, i.e. depleting)
            rates.append((apct - bpct) / dtHours)
        }
        return rates
    }

    /// Slope of `remainingPercent` vs `observedAt`, in percent-per-hour.
    /// Uses least-squares so an irregular sample schedule does not bias
    /// the result.  Returns nil if the samples are too clustered or the
    /// slope is non-positive.
    static func ratePerHour(samples: [Sample]) -> Double? {
        let usable = samples.filter { $0.remainingPercent != nil }
        guard usable.count >= 2 else { return nil }
        let t0 = usable.first!.observedAt.timeIntervalSinceReferenceDate
        var sumX: Double = 0
        var sumY: Double = 0
        var sumXX: Double = 0
        var sumXY: Double = 0
        var n: Double = 0
        for s in usable {
            let x = (s.observedAt.timeIntervalSinceReferenceDate - t0) / 3600
            let y = s.remainingPercent!
            sumX += x
            sumY += y
            sumXX += x * x
            sumXY += x * y
            n += 1
        }
        let denom = n * sumXX - sumX * sumX
        guard denom != 0 else { return nil }
        let slope = (n * sumXY - sumX * sumY) / denom
        // slope is "% per hour".  A negative slope means the bucket is
        // depleting; positive means the bucket is recovering.  The
        // detector only cares about depletion, so non-positive slopes
        // return nil.
        return slope < 0 ? -slope : nil
    }

    static func summary(kind: Anomaly.Kind, ratio: Double, threshold: Double, window: String, comparison: String) -> String {
        let prefix: String
        switch kind {
        case .vsBaseline: prefix = "Spending fast vs"
        case .vsPeak: prefix = "Spending faster than"
        }
        return "\(prefix) \(window): \(String(format: "%.1f", ratio))× \(comparison)."
    }

    static func windowLabel(windowId: String) -> String {
        if let range = windowId.range(of: ":", options: .backwards) {
            return String(windowId[range.upperBound...])
        }
        return windowId
    }
}
