import AppKit
import XCTest

@MainActor
final class PanelContentContainerTests: XCTestCase {
    private func makeContainer(width: CGFloat = 1342) -> (PanelContentContainer, NSView) {
        let container = PanelContentContainer(frame: NSRect(x: 0, y: 0, width: width, height: 280))
        let host = NSView(frame: container.bounds)
        container.addSubview(host)
        container.hostedView = host
        return (container, host)
    }

    func testHostFollowsTheContainerThroughResizes() {
        let (container, host) = makeContainer()

        container.setFrameSize(NSSize(width: 720, height: 280))
        XCTAssertEqual(host.frame, NSRect(x: 0, y: 0, width: 720, height: 280))

        container.setFrameSize(NSSize(width: 1440, height: 280))
        XCTAssertEqual(host.frame, NSRect(x: 0, y: 0, width: 1440, height: 280))
    }

    /// The #38 state: the host had drifted narrower and off the left edge.
    /// A plain width mask kept that gap forever; the container must close it.
    func testADriftedHostIsRestoredOnTheNextResize() {
        let (container, host) = makeContainer()
        host.frame = NSRect(x: -40, y: 0, width: 325, height: 280)

        container.setFrameSize(NSSize(width: 1440, height: 280))

        XCTAssertEqual(host.frame, NSRect(x: 0, y: 0, width: 1440, height: 280))
    }

    func testFittingRestoresADriftedHostWithoutAResize() {
        let (container, host) = makeContainer()
        host.frame = NSRect(x: 0, y: 0, width: 325, height: 280)

        container.fitHostedViewWidth()

        XCTAssertEqual(host.frame.width, 1342)
    }

    /// The slide animation owns the vertical offset; resizing must not reset it.
    func testResizingKeepsTheSlideOffset() {
        let (container, host) = makeContainer()
        host.setFrameOrigin(NSPoint(x: 0, y: -280))

        container.setFrameSize(NSSize(width: 720, height: 280))

        XCTAssertEqual(host.frame, NSRect(x: 0, y: -280, width: 720, height: 280))
    }
}
