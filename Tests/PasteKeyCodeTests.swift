import CoreGraphics
import XCTest

final class PasteKeyCodeTests: XCTestCase {
    /// ANSI key positions for the letters these tests need.
    private let qwerty: [CGKeyCode: String] = [9: "v", 47: ".", 41: ";"]
    /// Dvorak puts "v" on the key QWERTY calls ".".
    private let dvorak: [CGKeyCode: String] = [9: "k", 47: "v", 41: "s"]
    /// A Korean layout types Hangul, never a Latin "v".
    private let hangul: [CGKeyCode: String] = [9: "\u{314D}", 47: "."]

    private func layout(_ map: [CGKeyCode: String]) -> (CGKeyCode) -> String? {
        { map[$0] }
    }

    func testQwertyUsesTheVKey() {
        XCTAssertEqual(PasteKeyCode.find(in: [layout(qwerty)]), 9)
    }

    func testDvorakUsesTheKeyThatTypesV() {
        XCTAssertEqual(PasteKeyCode.find(in: [layout(dvorak)]), 47)
    }

    func testANonLatinLayoutFallsBackToTheAsciiLayout() {
        XCTAssertEqual(PasteKeyCode.find(in: [layout(hangul), layout(dvorak)]), 47)
    }

    func testNoMatchFallsBackToTheQwertyPosition() {
        XCTAssertEqual(PasteKeyCode.find(in: [layout(hangul)]), 9)
        XCTAssertEqual(PasteKeyCode.find(in: []), 9)
    }

    func testUppercaseResultsStillMatch() {
        XCTAssertEqual(PasteKeyCode.find(in: [layout([9: "V"])]), 9)
    }
}
