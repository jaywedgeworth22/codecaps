import Foundation

/// The sound the reset alarm plays when a previously exhausted quota
/// becomes usable again.  Picker value, raw value, and display label
/// are the same as the macOS app so a sound picked on either device
/// reads sensibly on the other (the App Group defaults key is
/// `alarmSound`, mirroring the macOS `ResetAlarmManager` storage).
///
/// This file is intentionally a near-verbatim mirror of
/// `Sources/QuotaCore/ResetAlarmSound.swift`.  The iOS app target does
/// not currently import QuotaCore (the Xcode project is generated
/// from `ios/CodeCapsCompanion/project.yml` with no Swift package
/// dependency declared), and adding the SPM dep would balloon this
/// change beyond its scope.  The two enums share a raw-value
/// contract; if either side adds a new case, the other gets it
/// alongside.
public enum ResetAlarmSound: String, CaseIterable, Codable, Sendable {
    case systemDefault = "system.default"
    case glass = "Glass"
    case submarine = "Submarine"
    case frog = "Frog"
    case blow = "Blow"
    case bottle = "Bottle"
    case tink = "Tink"
    case sosumi = "Sosumi"
    case silent = "silent"

    /// Owner-facing picker label, sentence case per fleet UI rule for
    /// value text with Title Case preserved where macOS's system sound
    /// catalogue capitalises the name.
    public var displayName: String {
        switch self {
        case .systemDefault: return "Default chime"
        case .glass: return "Glass"
        case .submarine: return "Submarine"
        case .frog: return "Frog"
        case .blow: return "Blow"
        case .bottle: return "Bottle"
        case .tink: return "Tink"
        case .sosumi: return "Sosumi"
        case .silent: return "Silent (banner only)"
        }
    }

    /// Short prose justifying the choice for an owner who has not
    /// heard the system sounds since macOS Ventura.
    public var pickerDetail: String {
        switch self {
        case .systemDefault: return "The platform's standard alert tone."
        case .glass: return "A bright tap — easy to hear in a quiet room."
        case .submarine: return "A low, longer tone — easy to hear through headphones."
        case .frog: return "A short ribbit — distinctive but unobtrusive."
        case .blow: return "An airy puff — barely registers if the office is loud."
        case .bottle: return "A cork pop — punchy and brief."
        case .tink: return "A small bell — light, single-tone."
        case .sosumi: return "The classic Mac alert."
        case .silent: return "Banner only — no sound plays; the row in Glance still highlights."
        }
    }

    public var isAudible: Bool { self != .silent }

    /// Convenience for the iOS picker ordering.  Same order as on Mac.
    public static let defaultPickerOrder: [ResetAlarmSound] = [
        .systemDefault, .blow, .bottle, .frog, .glass, .sosumi, .submarine, .tink, .silent,
    ]
}
