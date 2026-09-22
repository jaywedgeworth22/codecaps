import AppKit
import Foundation
import QuotaCore
import UserNotifications

/// The payload sent when a quota reset alert is triggered.
///
/// Carries the picked `ResetAlarmSound` so a test (and a future custom
/// delivery handler) can verify the alert honours the Settings picker
/// instead of trusting an external `UNNotificationSound` round-trip.
public struct ResetAlarmNotification: Equatable, Sendable {
    public let id: String
    public let sectionId: String
    public let title: String
    public let body: String
    public let remainingPercent: Int
    public let sound: ResetAlarmSound
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

    /// Which sound the alarm plays.  Persisted as the raw value (a system
    /// sound name), so the migration just writes the new key and the
    /// legacy `soundOnReset` Bool is read once in `init`.  Defaults to
    /// `systemDefault` so a fresh install lands on the platform chime,
    /// matching the previous behaviour when `soundOnReset` was true.
    @Published public var alarmSound: ResetAlarmSound {
        didSet { defaults.set(alarmSound.rawValue, forKey: "alarmSound") }
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

    /// Injectable sound player for unit testing.  Kept for the
    /// `sendTestNotification()` flow and for owners who set the picker
    /// to a system name we expose via `NSSound(named:)` even when
    /// notifications are off, so the preview button in Settings still
    /// plays the chosen tone.
    var onPlaySound: (() -> Void)?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.notifyOnReset = defaults.object(forKey: "notifyOnReset") as? Bool ?? true
        // One-time migration from the legacy boolean: a fresh owner who
        // previously had `soundOnReset = true` lands on `.systemDefault`;
        // one who had turned it off lands on `.silent`.  Once the new key
        // is written, the legacy key is never read again.  Resolve the
        // value into a local first because reading `self.alarmSound`
        // inside `didSet` before every stored property is initialised
        // makes Swift reject the init.
        let resolved: ResetAlarmSound
        if let raw = defaults.string(forKey: "alarmSound"),
           let migrated = ResetAlarmSound(rawValue: raw) {
            resolved = migrated
        } else if let legacySoundOn = defaults.object(forKey: "soundOnReset") as? Bool {
            resolved = legacySoundOn ? .systemDefault : .silent
            defaults.set(resolved.rawValue, forKey: "alarmSound")
        } else {
            resolved = .systemDefault
        }
        self.alarmSound = resolved
        let savedArmed = defaults.stringArray(forKey: "armedResetAlarmSectionIds") ?? []
        self.armedSectionIds = Set(savedArmed)
    }

    /// Plays the picked sound.  Used by the Settings "Preview" button so
    /// the owner can hear a sound before saving; called both with an
    /// armed payload (during a real reset alert) and with no payload at
    /// all (during a preview), so this is parameterless and emits via
    /// `NSSound(named:)`.  `.silent` and `.systemDefault` are special-cased
    /// so a preview of `Default chime` does not double-fire alongside the
    /// system chime the notification would deliver.
    public func previewChosenSound() {
        let sound = alarmSound
        guard sound.isAudible else { return }
        if let onPlaySound {
            onPlaySound()
            return
        }
        switch sound {
        case .systemDefault:
            NSSound.beep()
        default:
            NSSound(named: sound.rawValue)?.play()
        }
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

    /// Resolves the picked sound into the `UNNotificationSound` value
    /// the alert carries.  `.silent` produces `nil` (the banner still
    /// appears; the alert is just muted); `.systemDefault` hands back
    /// the platform default chime; every other case builds the named
    /// system sound from `ResetAlarmSound.rawValue`.
    private func notificationSound(for sound: ResetAlarmSound) -> UNNotificationSound? {
        switch sound {
        case .silent:
            return nil
        case .systemDefault:
            return .default
        default:
            return UNNotificationSound(named: UNNotificationSoundName(sound.rawValue))
        }
    }

    private func dispatchAlert(for section: DisplaySection) {
        let pct = Int((section.remainingPercent ?? 100).rounded())
        let title = "Quota Reset: \(section.title)"
        let body = "All quotas have cleared (\(pct)% remaining)." + sentenceGap + "Ready to use again."

        let payload = ResetAlarmNotification(
            id: UUID().uuidString,
            sectionId: section.id,
            title: title,
            body: body,
            remainingPercent: pct,
            sound: alarmSound
        )

        // Deliver via custom test handler if installed
        if let onNotification {
            onNotification(payload)
        } else if Self.canUseUserNotifications {
            // Deliver via macOS User Notifications; the sound picked in
            // Settings travels on the payload so the notification owns the
            // audio output.  We no longer fire a second `NSSound(named:)`
            // after, which used to make the alarm ring twice.
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = notificationSound(for: alarmSound)

            let request = UNNotificationRequest(
                identifier: "codecaps.reset.\(section.id).\(Date().timeIntervalSince1970)",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
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
                remainingPercent: 100,
                sound: alarmSound
            ))
        } else if Self.canUseUserNotifications {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = notificationSound(for: alarmSound)
            let request = UNNotificationRequest(
                identifier: "codecaps.test.\(Date().timeIntervalSince1970)",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
    }
}
