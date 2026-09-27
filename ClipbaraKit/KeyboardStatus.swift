import Foundation

/// What the keyboard last reported about itself, so the app can tell whether it has
/// been added. iOS offers no public way for an app to ask. The keyboard writes this
/// each time it appears; without Full Access the write may not reach the app, so an
/// empty value means "not seen yet", never "off".
struct KeyboardStatus: Equatable {
    var lastSeen: Date?
    var hasFullAccess = false

    private static let seenKey = "keyboardLastSeenAt"
    private static let fullAccessKey = "keyboardHasFullAccess"

    static func read(from defaults: UserDefaults = ClipStore.defaults) -> KeyboardStatus {
        let seen = defaults.object(forKey: seenKey) as? Double
        return KeyboardStatus(
            lastSeen: seen.map(Date.init(timeIntervalSince1970:)),
            hasFullAccess: defaults.bool(forKey: fullAccessKey)
        )
    }

    static func record(hasFullAccess: Bool, in defaults: UserDefaults = ClipStore.defaults) {
        defaults.set(Date().timeIntervalSince1970, forKey: seenKey)
        defaults.set(hasFullAccess, forKey: fullAccessKey)
    }

    var isAdded: Bool { lastSeen != nil }
}
