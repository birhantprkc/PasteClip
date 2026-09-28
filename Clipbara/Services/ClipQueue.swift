import AppKit

/// Clip Queue: while it is on, every copy joins the queue, and each ⌘V the
/// user presses pastes the next one in order (#9).
///
/// The item due next is always what sits on the clipboard. After the user's
/// ⌘V is released, it is dropped and the following item takes its place.
/// Seeing that ⌘V happen in other apps needs Accessibility permission, the
/// same grant as pasting into the active app.
@MainActor
@Observable
final class ClipQueue {
    private(set) var isActive = false
    private(set) var list = ClipQueueList<ClipboardItem>()
    private(set) var hasPermission = false

    var pastesNewestFirst: Bool {
        get { list.pastesNewestFirst }
        set {
            list.pastesNewestFirst = newValue
            lineUpNext()
        }
    }

    @ObservationIgnored private weak var appState: AppState?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var permissionTimer: Timer?
    @ObservationIgnored private var pasteKeyCode = PasteKeyCode.qwertyV
    /// Key code of a ⌘V that is down and not yet released.
    @ObservationIgnored private var pendingPasteKey: UInt16?
    @ObservationIgnored private let window = ClipQueueWindowController()

    func attach(to appState: AppState) {
        self.appState = appState
    }

    func toggle() {
        if isActive { stop() } else { start() }
    }

    func start() {
        guard !isActive else { return }
        isActive = true
        list.removeAll()
        pasteKeyCode = PasteKeyCode.current()
        hasPermission = DirectPaste.hasPermission
        installKeyMonitor()
        startPermissionPolling()
        window.show(queue: self)
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        list.removeAll()
        removeKeyMonitor()
        permissionTimer?.invalidate()
        permissionTimer = nil
        pendingPasteKey = nil
        window.hide()
    }

    /// A copy Clipbara just recorded.
    func capture(_ item: ClipboardItem) {
        guard isActive else { return }
        // A snapshot, so pruning or deleting history can't pull the model out
        // from under the list.
        let entry = list.append(item.detachedCopy())
        // The clipboard already holds what was just copied.
        guard list.next?.id != entry.id else { return }
        lineUpNext()
    }

    func remove(id: UUID) {
        let wasNext = list.next?.id == id
        list.remove(id: id)
        if wasNext { lineUpNext() }
    }

    // MARK: - Clipboard

    private func lineUpNext() {
        guard isActive, let next = list.next, let appState else { return }
        appState.clipboardMonitor.skipNextChange()
        appState.pasteService.write(
            item: next.item,
            asPlainText: UserDefaults.standard.bool(forKey: PasteService.alwaysPlainTextDefaultsKey)
        )
    }

    private func userDidPaste() {
        guard isActive, list.consumeNext() != nil else { return }
        lineUpNext()
    }

    // MARK: - Watching for ⌘V

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event)
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    private func handle(_ event: NSEvent) {
        // Clipbara's own "paste into the active app" is not the user pasting.
        if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == DirectPaste.syntheticEventMarker {
            return
        }
        switch event.type {
        case .keyDown:
            if Self.isPasteChord(event, pasteKeyCode: pasteKeyCode) {
                pendingPasteKey = event.keyCode
            }
        case .keyUp:
            if let pending = pendingPasteKey, event.keyCode == pending {
                pendingPasteKey = nil
                userDidPaste()
            }
        default:
            break
        }
    }

    /// ⌘V, with or without ⇧ or ⌥ (Paste and Match Style in many apps).
    private static func isPasteChord(_ event: NSEvent, pasteKeyCode: CGKeyCode) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard flags.contains(.command), !flags.contains(.control) else { return false }
        return event.keyCode == pasteKeyCode
            || event.charactersIgnoringModifiers?.lowercased() == "v"
    }

    // MARK: - Permission

    private func startPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshPermission()
            }
        }
    }

    private func refreshPermission() {
        let granted = DirectPaste.hasPermission
        guard granted != hasPermission else { return }
        hasPermission = granted
        // A monitor added before the grant never receives key events.
        if granted { installKeyMonitor() }
    }
}

extension ClipboardItem {
    /// An unmanaged copy with the same content, safe to keep after the
    /// original is deleted from history.
    func detachedCopy() -> ClipboardItem {
        let copy = ClipboardItem(
            contentType: contentType,
            rawData: rawData,
            textContent: textContent,
            thumbnailData: thumbnailData,
            sourceAppName: sourceAppName,
            sourceAppBundleId: sourceAppBundleId,
            contentHash: contentHash
        )
        copy.userTitle = userTitle
        copy.copiedAt = copiedAt
        return copy
    }
}
