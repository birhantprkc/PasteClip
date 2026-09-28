import AppKit
import SwiftUI

/// Brings the Settings window in front of other apps' windows.
///
/// Clipbara is a menu bar app and is not the active app when Settings is
/// chosen from the menu. `openSettings()` followed by `NSApp.activate` could
/// leave the window behind whatever the user had open, so the window is
/// ordered front explicitly, including the first time, once it exists.
@MainActor
enum SettingsWindowFront {
    private static weak var window: NSWindow?
    private static var wantsFront = false
    /// Until when a focus change back to the previous app is undone.
    private static var reclaimUntil: Date?
    private static var isObservingResign = false

    /// Call right after `openSettings()`.
    static func bring() {
        NSApp.activate(ignoringOtherApps: true)
        observeResignOnce()
        reclaimUntil = Date().addingTimeInterval(1.5)
        wantsFront = true
        orderFront()
        // SwiftUI may create or reorder the window after this turn, and the
        // first time the window only exists once its content attaches.
        DispatchQueue.main.async { orderFront() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { wantsFront = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            reclaimUntil = nil
            window?.level = .normal
        }
    }

    /// About a quarter second after Settings came forward, focus went back to
    /// the app that was in front before the menu opened, and Settings dropped
    /// behind its windows. Seen with the menu bar manager Thaw; whether
    /// anything else does it is untested. Take focus back once.
    private static func observeResignOnce() {
        guard !isObservingResign else { return }
        isObservingResign = true
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                reclaimFocusIfNeeded()
            }
        }
    }

    private static func reclaimFocusIfNeeded() {
        guard let until = reclaimUntil, Date() < until,
              let window, window.isVisible else { return }
        reclaimUntil = nil
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKey()
    }

    fileprivate static func attach(_ window: NSWindow) {
        self.window = window
        orderFront()
    }

    private static func orderFront() {
        guard wantsFront, let window else { return }
        // Held above normal windows while focus may still bounce back to the
        // previous app, so the window never visibly drops behind it.
        window.level = .floating
        window.orderFrontRegardless()
        window.makeKey()
    }
}

/// Reports the hosting window of the Settings content to `SettingsWindowFront`.
struct SettingsWindowReader: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ReaderView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ReaderView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            SettingsWindowFront.attach(window)
        }
    }
}
