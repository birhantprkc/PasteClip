import AppKit
import SwiftUI

/// The small floating list shown while a Clip Queue is on.
///
/// It never becomes key: if it took keyboard focus, the user's next ⌘V would
/// land here instead of in the app they are pasting into.
@MainActor
final class ClipQueueWindowController {
    static let width: CGFloat = 300
    private static let margin: CGFloat = 12

    private var panel: ClipQueuePanel?

    func show(queue: ClipQueue) {
        if panel == nil {
            let panel = ClipQueuePanel(
                contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 120)
            )
            let host = FirstMouseHostingView(
                rootView: ClipQueueView(queue: queue) { [weak self] height in
                    self?.resize(toHeight: height)
                }
            )
            // Sized by hand from the reported height, like the paywall window.
            host.sizingOptions = []
            panel.contentView = host
            self.panel = panel
        }
        placeAtTopRight()
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func placeAtTopRight() {
        guard let panel else { return }
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: visible.maxX - size.width - Self.margin,
            y: visible.maxY - size.height - Self.margin
        ))
    }

    /// Resizes on the next turn, outside the layout pass that reported the
    /// height, keeping the top edge in place.
    private func resize(toHeight height: CGFloat) {
        DispatchQueue.main.async { [weak self] in
            guard let panel = self?.panel, height > 0,
                  abs(panel.frame.height - height) > 0.5 else { return }
            var frame = panel.frame
            frame.origin.y += frame.height - height
            frame.size = NSSize(width: Self.width, height: height)
            panel.setFrame(frame, display: true)
        }
    }
}

final class ClipQueuePanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets buttons respond to the first click in a window that never becomes key.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
