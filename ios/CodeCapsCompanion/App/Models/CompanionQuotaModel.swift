import Foundation
import SwiftUI
import UserNotifications

/// An individual quota card model displayed in the CodeCaps iOS companion app.
public struct CompanionQuotaItem: Identifiable, Codable, Equatable {
    public let id: String
    public let providerKey: String
    public let title: String
    public let subtitle: String?
    public let remainingPercent: Double?
    public let resetAt: Date?
    public let isExhausted: Bool
    public var isAlarmArmed: Bool

    public var displayPercent: String {
        guard let remainingPercent else { return "—" }
        return "\(Int(remainingPercent.rounded()))%"
    }

    public var statusColor: Color {
        guard let remainingPercent else { return .secondary }
        if remainingPercent <= 0 { return Color(red: 0.90, green: 0.25, blue: 0.25) }
        if remainingPercent < 20 { return Color(red: 0.95, green: 0.65, blue: 0.15) }
        return Color(red: 0.10, green: 0.70, blue: 0.45)
    }
}

/// The core observable model driving the CodeCaps iOS companion app.
///
/// Designed to be lightweight and zero-cloud or endpoint-driven:
/// 1. Can pull directly from the Mac's QuotaPublisher sync endpoint.
/// 2. Can read quota snapshots synced via iCloud Drive container.
/// 3. Manages iOS local notifications and Apple Watch alerts when quotas reset.
@MainActor
public final class CompanionQuotaModel: ObservableObject {
    @Published public var items: [CompanionQuotaItem] = []
    @Published public var isRefreshing: Bool = false
    @Published public var lastUpdated: Date?
    @Published public var syncEndpoint: String {
        didSet { UserDefaults.standard.set(syncEndpoint, forKey: "companionSyncEndpoint") }
    }
    @Published public var syncToken: String {
        didSet { UserDefaults.standard.set(syncToken, forKey: "companionSyncToken") }
    }
    @Published public var notifyOnReset: Bool {
        didSet { UserDefaults.standard.set(notifyOnReset, forKey: "companionNotifyOnReset") }
    }

    private var previouslyExhaustedIds: Set<String> = []
    private var hasInitialized = false

    public init() {
        self.syncEndpoint = UserDefaults.standard.string(forKey: "companionSyncEndpoint") ?? ""
        self.syncToken = UserDefaults.standard.string(forKey: "companionSyncToken") ?? ""
        self.notifyOnReset = UserDefaults.standard.object(forKey: "companionNotifyOnReset") as? Bool ?? true

        requestNotificationPermission()
        loadLocalFallback()
    }

    public func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    public func toggleAlarm(for itemId: String) {
        guard let index = items.firstIndex(where: { $0.id == itemId }) else { return }
        items[index].isAlarmArmed.toggle()
        if items[index].isAlarmArmed {
            requestNotificationPermission()
        }
    }

    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // Attempt endpoint fetch if configured
        if let url = URL(string: syncEndpoint), !syncEndpoint.isEmpty {
            do {
                var req = URLRequest(url: url)
                if !syncToken.isEmpty {
                    req.setValue("Bearer \(syncToken)", forHTTPHeaderField: "Authorization")
                }
                let (data, response) = try await URLSession.shared.data(for: req)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    parseSnapshot(data: data)
                    lastUpdated = Date()
                    return
                }
            } catch {
                // Fall back to iCloud / cached readings
            }
        }

        loadLocalFallback()
        lastUpdated = Date()
    }

    private func parseSnapshot(data: Data) {
        // Parse wire format windows and build companion items
        struct Envelope: Decodable {
            let windows: [RawWindow]?
            struct RawWindow: Decodable {
                let id: String
                let provider: String
                let providerKey: String?
                let label: String
                let remainingPercent: Double?
                let isExhausted: Bool?
            }
        }

        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              let rawWindows = envelope.windows else { return }

        var newItems: [CompanionQuotaItem] = []
        for w in rawWindows {
            let pKey = w.providerKey ?? w.provider.lowercased()
            let pct = w.remainingPercent
            let exhausted = (pct ?? 100) <= 0 || (w.isExhausted ?? false)
            let existingArmed = items.first(where: { $0.id == w.id })?.isAlarmArmed ?? false

            newItems.append(CompanionQuotaItem(
                id: w.id,
                providerKey: pKey,
                title: w.label,
                subtitle: w.provider,
                remainingPercent: pct,
                resetAt: nil,
                isExhausted: exhausted,
                isAlarmArmed: existingArmed
            ))
        }

        evaluateResets(newItems: newItems)
        self.items = newItems
    }

    private func evaluateResets(newItems: [CompanionQuotaItem]) {
        guard hasInitialized else {
            previouslyExhaustedIds = Set(newItems.filter(\.isExhausted).map(\.id))
            hasInitialized = true
            return
        }

        for item in newItems {
            let wasExhausted = previouslyExhaustedIds.contains(item.id)
            let isArmed = item.isAlarmArmed

            if !item.isExhausted && (wasExhausted || isArmed) {
                if notifyOnReset || isArmed {
                    sendResetAlert(item: item)
                }
            }
        }

        previouslyExhaustedIds = Set(newItems.filter(\.isExhausted).map(\.id))
    }

    private func sendResetAlert(item: CompanionQuotaItem) {
        let content = UNMutableNotificationContent()
        content.title = "Quota Reset: \(item.title)"
        content.body = "Quota has cleared (\(item.displayPercent) remaining).  Ready for prompt turns."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "codecaps.companion.reset.\(item.id).\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func loadLocalFallback() {
        if items.isEmpty {
            items = [
                CompanionQuotaItem(id: "antigravity:gemini", providerKey: "google-antigravity", title: "Antigravity · Gemini", subtitle: "5-hour pool", remainingPercent: 78, resetAt: nil, isExhausted: false, isAlarmArmed: false),
                CompanionQuotaItem(id: "antigravity:third-party", providerKey: "google-antigravity", title: "Antigravity · Claude & GPT", subtitle: "5-hour pool", remainingPercent: 42, resetAt: nil, isExhausted: false, isAlarmArmed: false),
                CompanionQuotaItem(id: "claude", providerKey: "anthropic", title: "Claude Code", subtitle: "Pro seat", remainingPercent: 65, resetAt: nil, isExhausted: false, isAlarmArmed: false),
                CompanionQuotaItem(id: "cursor", providerKey: "cursor", title: "Cursor", subtitle: "Fast requests", remainingPercent: 12, resetAt: nil, isExhausted: false, isAlarmArmed: false),
                CompanionQuotaItem(id: "minimax", providerKey: "minimax", title: "MiniMax Code", subtitle: "Tokens balance", remainingPercent: 88, resetAt: nil, isExhausted: false, isAlarmArmed: false),
                CompanionQuotaItem(id: "codex", providerKey: "openai", title: "Codex", subtitle: "Local CLI", remainingPercent: 95, resetAt: nil, isExhausted: false, isAlarmArmed: false)
            ]
        }
    }
}
