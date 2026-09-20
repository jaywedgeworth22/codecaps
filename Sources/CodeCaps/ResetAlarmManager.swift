import AppKit
import Foundation
import QuotaCore
import UserNotifications

/// The payload sent when a quota reset alert is triggered.
public struct ResetAlarmNotification: Equatable, Sendable {
    public let id: String
    public let sectionId: String
    public let title: String
    public let body: String
    public let remainingPercent: Int
}

/// Manages reset alerts and alarms when exhausted quotas clear.
///
/// Ensures that an alert is only fired when ALL controlling quotas for a model
/// or platform are clear and the model can actually be used again.  For example,
/// if an Antigravity 5-hour window resets while the weekly limit is still at 0%
/// (exhausted/masked), the alert is suppressed until the weekly cap also clears.
@MainActor
public final class ResetAlarmManager: ObservableObject {
    private let defaults: UserDefaults

    @Published public var notifyOnReset: Bool {
        didSet { defaults.set(notifyOnReset, forKey: "notifyOnReset") }
    }

    @Published public var soundOnReset: Bool {
        didSet { defaults.set(soundOnReset, forKey: "soundOnReset") }
    }

    @Published public var armedSectionIds: Set<String> {
        didSet { defaults.set(Array(armedSectionIds), forKey: "armedResetAlarmSectionIds") }
    }

    /// The IDs of sections observed as exhausted/blocked on previous evaluations.
    public private(set) var exhaustedSectionIds: Set<String> = []

    /// Whether this manager has performed its initial baseline pass.
    private var hasInitialized = false

    /// Injectable notification handler for unit testing.
    var onNotification: ((ResetAlarmNotification) -> Void)?

    /// Injectable sound player for unit testing.
    var onPlaySound: (() -> Void)?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.notifyOnReset = defaults.object(forKey: "notifyOnReset") as? Bool ?? true
        self.soundOnReset = defaults.object(forKey: "soundOnReset") as? Bool ?? true
        let savedArmed = defaults.stringArray(forKey: "armedResetAlarmSectionIds") ?? []
        self.armedSectionIds = Set(savedArmed)
    }

    private static var isRunningUnderTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.processName == "xctest"
            || NSClassFromString("XCTestCase") != nil
    }

    private static var canUseUserNotifications: Bool {
        guard !isRunningUnderTests else { return false }
        guard let id = Bundle.main.bundleIdentifier, !id.contains("xctest") else { return false }
        return true
    }

    // MARK: - Permission

    public func requestNotificationPermission() {
        guard Self.canUseUserNotifications else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: - Arming

    public func isAlarmArmed(for sectionId: String) -> Bool {
        armedSectionIds.contains(sectionId)
    }

    public func toggleAlarm(for sectionId: String) {
        if armedSectionIds.contains(sectionId) {
            armedSectionIds.remove(sectionId)
        } else {
            armedSectionIds.insert(sectionId)
            requestNotificationPermission()
        }
    }

    // MARK: - Usability Evaluation

    /// Whether a section is currently exhausted or blocked.
    func isSectionExhausted(_ section: DisplaySection) -> Bool {
        // If headline remaining percent is zero, it is definitely exhausted.
        if let pct = section.remainingPercent, pct <= 0 {
            return true
        }

        // For Antigravity pools, if any window is masked, the weekly cap is exhausted.
        if !section.maskedWindowIds.isEmpty {
            return true
        }

        // Check all primary fresh windows in this section.
        let activeWindows = section.section.windows.filter {
            $0.isFresh && !$0.window.isSupplementaryVideoQuota && !section.isMasked($0)
        }
        guard !activeWindows.isEmpty else { return false }

        return activeWindows.contains { ($0.remainingPercent ?? 100) <= 0 }
    }

    /// Whether a section can genuinely be used again (all controlling caps cleared).
    func isSectionUsable(_ section: DisplaySection) -> Bool {
        // Headline remaining percent must be present and greater than zero.
        guard let headline = section.remainingPercent, headline > 0 else {
            return false
        }

        // Antigravity: if weekly is exhausted, 5-hour is masked, so maskedWindowIds must be empty.
        guard section.maskedWindowIds.isEmpty else {
            return false
        }

        // Every unmasked active window must have positive remaining percentage.
        let activeWindows = section.section.windows.filter {
            $0.isFresh && !$0.window.isSupplementaryVideoQuota && !section.isMasked($0)
        }
        guard !activeWindows.isEmpty else {
            return headline > 0
        }

        return activeWindows.allSatisfy { ($0.remainingPercent ?? 100) > 0 }
    }

    // MARK: - Evaluation Cycle

    /// Evaluates current sections against previous states and dispatches alerts
    /// when a previously exhausted or user-armed model becomes usable again.
    func evaluate(currentSections: [DisplaySection], now: Date = Date()) {
        var currentExhausted: Set<String> = []

        for section in currentSections {
            let blocked = isSectionExhausted(section)
            let usable = isSectionUsable(section)

            if blocked {
                currentExhausted.insert(section.id)
            }

            // On initial run, record baseline exhaustion without triggering alerts.
            guard hasInitialized else { continue }

            let wasExhausted = exhaustedSectionIds.contains(section.id)
            let isArmed = armedSectionIds.contains(section.id)

            // Alert triggers when a previously exhausted or user-armed model is now usable
            // AND all controlling caps are completely clear.
            if usable && (wasExhausted || isArmed) {
                if notifyOnReset || isArmed {
                    dispatchAlert(for: section)
                }
                // Clear the one-shot alarm if it was armed.
                armedSectionIds.remove(section.id)
            }
        }

        exhaustedSectionIds = currentExhausted
        hasInitialized = true
    }

    // MARK: - Dispatch

    private func dispatchAlert(for section: DisplaySection) {
        let pct = Int((section.remainingPercent ?? 100).rounded())
        let title = "Quota Reset: \(section.title)"
        let body = "All quotas have cleared (\(pct)% remaining)." + sentenceGap + "Ready to use again."

        let payload = ResetAlarmNotification(
            id: UUID().uuidString,
            sectionId: section.id,
            title: title,
            body: body,
            remainingPercent: pct
        )

        // Deliver via custom test handler if installed
        if let onNotification {
            onNotification(payload)
        } else if Self.canUseUserNotifications {
            // Deliver via macOS User Notifications
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            if soundOnReset {
                content.sound = .default
            }

            let request = UNNotificationRequest(
                identifier: "codecaps.reset.\(section.id).\(Date().timeIntervalSince1970)",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }

        if soundOnReset {
            if let onPlaySound {
                onPlaySound()
            } else {
                NSSound(named: "Glass")?.play()
            }
        }
    }

    /// Sends an immediate test notification to verify notification delivery and sound.
    public func sendTestNotification() {
        requestNotificationPermission()
        let title = "CodeCaps Reset Alert Test"
        let body = "Reset alerts and alarms are working properly." + sentenceGap + "Sound and banners active."

        if let onNotification {
            onNotification(ResetAlarmNotification(
                id: UUID().uuidString,
                sectionId: "test",
                title: title,
                body: body,
                remainingPercent: 100
            ))
        } else if Self.canUseUserNotifications {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            if soundOnReset {
                content.sound = .default
            }
            let request = UNNotificationRequest(
                identifier: "codecaps.test.\(Date().timeIntervalSince1970)",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }

        if soundOnReset {
            if let onPlaySound {
                onPlaySound()
            } else {
                NSSound(named: "Glass")?.play()
            }
        }
    }
}
