import XCTest
@testable import CodeCaps
import QuotaCore

/// The per-provider source ranking preference: when two readers report quota
/// for the same provider, the owner picks which one wins.  These tests pin
/// the behaviour so a future rewrite cannot silently change "lowest percent
/// wins" into "highest-ranked source wins" (or vice versa) and break a saved
/// preference.
@MainActor
final class SourceRankingTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.jays.agent-bar.tests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: helpers

    private func window(id: String,
                        provider: String,
                        providerKey: String,
                        source: String?,
                        remaining: Double,
                        observedAt: Date = Date(timeIntervalSince1970: 1_000_000)) -> QuotaWindow {
        QuotaWindow(
            id: id,
            provider: provider,
            providerKey: providerKey,
            providerLabel: provider,
            via: provider,
            sourceApp: "test",
            label: id,
            remainingPercent: remaining,
            remainingUnknown: false,
            occurredAt: ISO8601DateFormatter().string(from: observedAt),
            source: source
        )
    }

    private func makeModel(_ windows: [QuotaWindow]) -> MonitorModel {
        let model = MonitorModel(defaults: defaults)
        let response = QuotaResponse(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            windows: windows
        )
        let sections = response.platformSections(now: Date())
        model.injectForTests(sections: sections)
        return model
    }

    // MARK: discovery

    func testAvailableSourcesReturnsObservedDistinctSources() {
        let model = makeModel([
            window(id: "a", provider: "Grok", providerKey: "grok-bot", source: "Cursor DashboardService", remaining: 60),
            window(id: "b", provider: "Grok", providerKey: "grok-bot", source: "Grok CLI", remaining: 40),
            window(id: "c", provider: "Grok", providerKey: "grok-bot", source: "Cursor DashboardService", remaining: 50),
        ])
        XCTAssertEqual(model.availableSources(for: "grok-bot"),
                       ["Cursor DashboardService", "Grok CLI"])
    }

    func testAvailableSourcesSkipsEmptyAndNil() {
        let model = makeModel([
            window(id: "a", provider: "Grok", providerKey: "grok-bot", source: nil, remaining: 60),
            window(id: "b", provider: "Grok", providerKey: "grok-bot", source: "", remaining: 60),
            window(id: "c", provider: "Grok", providerKey: "grok-bot", source: "Grok CLI", remaining: 40),
        ])
        XCTAssertEqual(model.availableSources(for: "grok-bot"), ["Grok CLI"])
    }

    func testRankedSourcesComeFirst() {
        let model = makeModel([
            window(id: "a", provider: "Grok", providerKey: "grok-bot", source: "Cursor DashboardService", remaining: 60),
            window(id: "b", provider: "Grok", providerKey: "grok-bot", source: "Grok CLI", remaining: 40),
            window(id: "c", provider: "Grok", providerKey: "grok-bot", source: "Grok App", remaining: 30),
        ])
        model.setSourceRank(["Grok CLI", "Grok App"], for: "grok-bot")
        XCTAssertEqual(model.availableSources(for: "grok-bot"),
                       ["Grok CLI", "Grok App", "Cursor DashboardService"])
    }

    // MARK: ordering

    func testOrderedWindowsPutsHighestRankedFirstWhenPctsTie() {
        let model = makeModel([
            window(id: "a", provider: "Grok", providerKey: "grok-bot", source: "Cursor DashboardService", remaining: 50),
            window(id: "b", provider: "Grok", providerKey: "grok-bot", source: "Grok CLI", remaining: 50),
        ])
        model.setSourceRank(["Grok CLI", "Cursor DashboardService"], for: "grok-bot")
        let ordered = model.orderedWindows(for: "grok-bot")
        XCTAssertEqual(ordered.first?.window.source, "Grok CLI")
    }

    func testOrderedWindowsDropsDisabledSources() {
        let model = makeModel([
            window(id: "a", provider: "Grok", providerKey: "grok-bot", source: "Cursor DashboardService", remaining: 80),
            window(id: "b", provider: "Grok", providerKey: "grok-bot", source: "Grok CLI", remaining: 40),
        ])
        model.setSourceEnabled(false, "Cursor DashboardService", for: "grok-bot")
        let ordered = model.orderedWindows(for: "grok-bot")
        XCTAssertEqual(ordered.count, 1)
        XCTAssertEqual(ordered.first?.window.source, "Grok CLI")
    }

    // MARK: move + set

    func testMoveSourceSwapsNeighbors() {
        let model = makeModel([
            window(id: "a", provider: "Grok", providerKey: "grok-bot", source: "A", remaining: 10),
            window(id: "b", provider: "Grok", providerKey: "grok-bot", source: "B", remaining: 20),
            window(id: "c", provider: "Grok", providerKey: "grok-bot", source: "C", remaining: 30),
        ])
        model.setSourceRank(["A", "B", "C"], for: "grok-bot")
        // Move C up by one: swaps positions 2 and 1, yielding ["A", "C", "B"].
        // The UI only ever calls this with ±1 from a single button press.
        model.moveSource("C", by: -1, for: "grok-bot")
        XCTAssertEqual(model.availableSources(for: "grok-bot"), ["A", "C", "B"])
        // Then move A down by one: swaps positions 0 and 1, yielding ["C", "A", "B"].
        model.moveSource("A", by: 1, for: "grok-bot")
        XCTAssertEqual(model.availableSources(for: "grok-bot"), ["C", "A", "B"])
    }

    func testMoveSourceIgnoresUnknown() {
        let model = makeModel([
            window(id: "a", provider: "Grok", providerKey: "grok-bot", source: "A", remaining: 10),
            window(id: "b", provider: "Grok", providerKey: "grok-bot", source: "B", remaining: 20),
        ])
        model.setSourceRank(["A", "B"], for: "grok-bot")
        model.moveSource("nope", by: -1, for: "grok-bot")
        XCTAssertEqual(model.availableSources(for: "grok-bot"), ["A", "B"])
    }

    func testSetSourceRankAppendsUnknownSourcesAtTail() {
        let model = makeModel([
            window(id: "a", provider: "Grok", providerKey: "grok-bot", source: "A", remaining: 10),
            window(id: "b", provider: "Grok", providerKey: "grok-bot", source: "B", remaining: 20),
            window(id: "c", provider: "Grok", providerKey: "grok-bot", source: "C", remaining: 30),
        ])
        model.setSourceRank(["C"], for: "grok-bot")
        // A and B were never ranked; the rank call appends them alphabetically
        // so the preference stays complete even after a partial reorder.
        XCTAssertEqual(model.availableSources(for: "grok-bot"), ["C", "A", "B"])
    }

    // MARK: persistence

    func testSourceRankAndDisabledSourcesRoundTripThroughDefaults() {
        defaults.set(
            try? JSONEncoder().encode(["grok-bot": ["A", "B"]]),
            forKey: "sourceRank"
        )
        defaults.set(["A"], forKey: "disabledSources")
        let model = MonitorModel(defaults: defaults)
        XCTAssertEqual(model.sourceRank["grok-bot"], ["A", "B"])
        XCTAssertEqual(model.disabledSources, ["A"])
    }
}
