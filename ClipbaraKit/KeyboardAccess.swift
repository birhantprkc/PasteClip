import Foundation

/// Whether the keyboard may insert clips, published by the app from the App Store
/// trial state. The keyboard cannot check purchases itself, so it reads this.
///
/// Missing means the app has not published anything yet, which is treated as open:
/// like the app, an unknown state never locks anyone out.
enum KeyboardAccess: Equatable {
    case open
    /// Open until the trial ends; the keyboard checks the date itself, so it locks on
    /// time even if Clipbara is not opened again.
    case trial(endsAt: Date)
    case trialNotStarted
    case trialExpired

    private static let modeKey = "keyboardAccessMode"
    private static let trialEndKey = "keyboardAccessTrialEndsAt"

    static func read(from defaults: UserDefaults = ClipStore.defaults) -> KeyboardAccess {
        switch defaults.string(forKey: modeKey) {
        case "trial":
            let end = defaults.double(forKey: trialEndKey)
            return end > 0 ? .trial(endsAt: Date(timeIntervalSince1970: end)) : .open
        case "notStarted": return .trialNotStarted
        case "expired": return .trialExpired
        default: return .open
        }
    }

    func publish(to defaults: UserDefaults = ClipStore.defaults) {
        switch self {
        case .open:
            defaults.set("open", forKey: Self.modeKey)
        case .trial(let end):
            defaults.set("trial", forKey: Self.modeKey)
            defaults.set(end.timeIntervalSince1970, forKey: Self.trialEndKey)
        case .trialNotStarted:
            defaults.set("notStarted", forKey: Self.modeKey)
        case .trialExpired:
            defaults.set("expired", forKey: Self.modeKey)
        }
    }

    /// The state that applies right now.
    func current(now: Date = .now) -> KeyboardAccess {
        if case .trial(let end) = self, now >= end { return .trialExpired }
        return self
    }

    var allowsInserting: Bool {
        switch self {
        case .open, .trial: true
        case .trialNotStarted, .trialExpired: false
        }
    }

    init(state: AccessState, trialEnd: Date?) {
        switch state {
        case .unlocked: self = .open
        case .trialActive: self = trialEnd.map { .trial(endsAt: $0) } ?? .open
        case .trialNotStarted: self = .trialNotStarted
        case .trialExpired: self = .trialExpired
        }
    }
}
