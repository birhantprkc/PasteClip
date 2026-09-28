import AppKit

/// Hosts the panel's SwiftUI view and keeps it exactly as wide as the panel.
///
/// The hosting view used to follow the panel through `autoresizingMask`, which
/// only applies the change in width. Once the two ever disagreed, every later
/// resize kept the same gap, so the content could stay squeezed against the left
/// edge until the app was relaunched. Deriving the width from the container on
/// every resize makes that state impossible to keep. The vertical position is
/// left alone because the slide animation owns it.
@MainActor
final class PanelContentContainer: NSView {
    weak var hostedView: NSView?

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        fitHostedViewWidth()
    }

    /// Snaps the hosted view to the container's width and height, keeping its
    /// vertical offset.
    func fitHostedViewWidth() {
        guard let hostedView else { return }
        let target = NSRect(
            x: 0,
            y: hostedView.frame.minY,
            width: bounds.width,
            height: bounds.height
        )
        if hostedView.frame != target {
            hostedView.frame = target
        }
    }
}
