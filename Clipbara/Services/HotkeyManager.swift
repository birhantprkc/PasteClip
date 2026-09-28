import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleHistoryPanel = Self(
        "toggleHistoryPanel",
        default: .init(.v, modifiers: [.shift, .command])
    )
    /// No default: users pick one in the welcome tour or Settings.
    static let toggleClipQueue = Self("toggleClipQueue")
    static let clearHistory = Self(
        "clearHistory",
        default: .init(.delete, modifiers: [.shift, .command])
    )
}
